#!/usr/bin/env python3
"""Query the Perplexity Agent API and print a cited answer.

Sonar and /chat/completions retire on 2026-09-27; this speaks the replacement
POST /v1/agent surface. Presets replace model names: they bundle model, system
prompt, tool config and step budget, and Perplexity re-tunes them with every
frontier release, so a preset name tracks the state of the art at a stable cost
profile. Step budgets: fast 1, low 5, medium 15, high 15, xhigh 100 (plus code
sandbox), wide-research 100.

Runs go through background mode and get polled, rather than streamed. A
streamed run dies with its connection: something between here and Perplexity
closes an idle SSE stream at four minutes, and an xhigh run cut that way comes
back from a later GET with status "cancelled", the work gone and still billed.
A background run has no connection to lose. Verified 2026-08-14: an xhigh
query failed at exactly 4:00 while streaming, and the same query survives here.
"""
import argparse
import json
import os
import subprocess
import sys
import time

import requests

API_BASE = "https://api.perplexity.ai"
PRESETS = ("fast", "low", "medium", "high", "xhigh", "wide-research")

# xhigh and wide-research run up to 100 retrieval steps, so the ceiling is
# generous. PPLX_MAX_WAIT overrides it for an unusually deep run.
MAX_WAIT = int(os.getenv("PPLX_MAX_WAIT", "900"))
HTTP_TIMEOUT = (10, 60)
TERMINAL = ("completed", "failed", "cancelled", "incomplete")


def parse_args():
    parser = argparse.ArgumentParser(description="Query the Perplexity Agent API.")
    parser.add_argument("query", type=str, help="The query to send to the API.")
    parser.add_argument(
        "--preset",
        choices=PRESETS,
        default="fast",
        help="Agent API preset (default: fast).",
    )
    parser.add_argument(
        "--pro",
        action="store_true",
        help="Shorthand for --preset low, the successor to sonar-pro.",
    )
    parser.add_argument(
        "--recency",
        choices=("hour", "day", "week", "month", "year"),
        help="Restrict sources to this recency window (default: no restriction).",
    )
    parser.add_argument(
        "--domain",
        action="append",
        metavar="DOMAIN",
        help="Restrict sources to this domain; repeatable.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit {id, answer, results[]} as JSON. Sources carry the fields a "
        "search result carries, so a picker can treat them as results.",
    )
    parser.add_argument(
        "--continue",
        dest="continue_from",
        metavar="RESPONSE_ID",
        help="Continue the thread from a previous run id, so a follow-up "
        "question can say 'it' and mean what the last answer was about.",
    )
    args = parser.parse_args()
    if args.pro:
        args.preset = "low"
    return args


def build_body(args):
    # A continued turn carries only the new question: the thread already holds
    # the system message and everything said so far, so repeating it would put
    # the instructions in twice.
    if args.continue_from:
        messages = [{"type": "message", "role": "user", "content": args.query}]
    else:
        messages = [
            {"type": "message", "role": "system", "content": "Be precise and concise."},
            {"type": "message", "role": "user", "content": args.query},
        ]

    body = {
        "preset": args.preset,
        "background": True,
        "input": messages,
    }
    if args.continue_from:
        body["previous_response_id"] = args.continue_from
    filters = {}
    if args.recency:
        filters["search_recency_filter"] = args.recency
    if args.domain:
        filters["search_domain_filter"] = args.domain
    if filters:
        body["tools"] = [{"type": "web_search", "filters": filters}]
    return body


def progress(message):
    """Progress goes to stderr so stdout stays a clean answer for pipes."""
    if sys.stderr.isatty():
        print(f"  {message}", file=sys.stderr, flush=True)


def count_sources(agent_response):
    return sum(
        len(item.get("results") or [])
        for item in agent_response.get("output") or []
        if item.get("type") == "search_results"
    )


def poll(session, run_id):
    """Poll a background run to a terminal state and return the response object."""
    deadline = time.monotonic() + MAX_WAIT
    last_report = None
    delay = 2

    while True:
        response = session.get(f"{API_BASE}/v1/agent/{run_id}", timeout=HTTP_TIMEOUT)
        if not response.ok:
            raise RuntimeError(f"poll failed: {response.status_code} {response.text}")
        agent_response = response.json()

        status = agent_response.get("status")
        report = (status, count_sources(agent_response))
        if report != last_report:
            progress(f"{status}, {report[1]} sources")
            last_report = report

        if status in TERMINAL:
            return agent_response

        if time.monotonic() > deadline:
            raise RuntimeError(
                f"run {run_id} still {status} after {MAX_WAIT}s; "
                "raise PPLX_MAX_WAIT or use a cheaper preset"
            )

        time.sleep(delay)
        # Deep runs spend minutes between visible changes; stop hammering.
        delay = min(delay + 1, 10)


def cancel(session, run_id):
    """An abandoned run keeps billing until the server hears otherwise."""
    try:
        session.post(f"{API_BASE}/v1/agent/{run_id}/cancel", json={}, timeout=HTTP_TIMEOUT)
    except requests.RequestException:
        # The run may already be terminal; nothing actionable either way.
        pass


def answer_text(agent_response):
    return "".join(
        part.get("text", "")
        for item in agent_response.get("output") or []
        if item.get("type") == "message"
        for part in (item.get("content") or [])
        if part.get("type") == "output_text"
    )


def collect_sources(agent_response):
    """Every source the run cited, in order, deduped by url.

    Each carries the fields a search result carries (title, url, snippet,
    date), which is what lets a picker treat these as results rather than as
    bare citations.
    """
    sources = []
    seen = set()
    for item in agent_response.get("output") or []:
        if item.get("type") != "search_results":
            continue
        for result in item.get("results") or []:
            url = result.get("url")
            if not url or url in seen:
                continue
            seen.add(url)
            sources.append(
                {
                    "id": result.get("id"),
                    "title": result.get("title") or url,
                    "url": url,
                    "snippet": result.get("snippet") or "",
                    "date": result.get("date") or "",
                }
            )
    return sources


def format_answer(agent_response):
    """Answer text plus a references block keyed by search-result id.

    The answer body is never rewritten: bracketed tokens also appear in code
    and slice syntax, so renumbering inline references risks corrupting it.
    """
    text = answer_text(agent_response)
    sources = collect_sources(agent_response)
    if not sources:
        return text

    ids = [source["id"] for source in sources]
    ids_usable = all(isinstance(i, int) for i in ids) and len(set(ids)) == len(ids)

    references = "\n\n## References\n\n"
    for position, source in enumerate(sources, 1):
        label = source["id"] if ids_usable else position
        references += f"[{label}]: {source['url']}\n"
    return text + references


# The key reaches an interactive shell through direnv, which only runs from
# ~/.zshrc. A tmux popup (M-g runs this behind __ddgx.sh) is a non-interactive
# shell inheriting the tmux server environment, so the variable is simply absent
# there and the search died on a machine that holds the secret. Decrypt the same
# password-store entry _pass_export reads in ~/.envrc, by the same gpg call, so
# the fallback cannot disagree with the export about where the value lives.
# PPLX_PASS_ENTRY overrides the entry for a store laid out differently.
PASS_ENTRY = os.getenv("PPLX_PASS_ENTRY", "work/PPLX_API_KEY")


def resolve_api_key():
    key = os.getenv("PPLX_API_KEY")
    if key:
        return key
    store = os.getenv("PASSWORD_STORE_DIR") or os.path.expanduser(
        "~/.password-store"
    )
    try:
        out = subprocess.run(
            ["gpg", "-dq", "--", os.path.join(store, PASS_ENTRY + ".gpg")],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return out.stdout.strip() if out.returncode == 0 else ""


def main():
    args = parse_args()

    api_key = resolve_api_key()
    if not api_key:
        sys.exit(
            "PPLX_API_KEY is not set and %s could not be decrypted" % PASS_ENTRY
        )

    session = requests.Session()
    session.headers.update(
        {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    )

    try:
        response = session.post(
            f"{API_BASE}/v1/agent", json=build_body(args), timeout=HTTP_TIMEOUT
        )
    except requests.RequestException as error:
        sys.exit(f"network error calling Perplexity: {error}")

    if not response.ok:
        sys.exit(f"Perplexity API error: {response.status_code} {response.text}")

    run_id = response.json().get("id")
    if not run_id:
        sys.exit("Perplexity accepted the run but returned no id")
    progress(f"run {run_id} ({args.preset})")

    try:
        agent_response = poll(session, run_id)
    except KeyboardInterrupt:
        cancel(session, run_id)
        sys.exit(130)
    except requests.RequestException as error:
        sys.exit(f"network error while polling Perplexity: {error}")
    except RuntimeError as error:
        sys.exit(str(error))

    status = agent_response.get("status")
    if status in ("failed", "cancelled"):
        detail = (agent_response.get("error") or {}).get("message") or status
        sys.exit(f"Perplexity run {status}: {detail}")

    if status == "incomplete":
        reason = (agent_response.get("incomplete_details") or {}).get("reason", "unknown")
        print(f"[partial answer, run incomplete: {reason}]\n", file=sys.stderr)

    if args.json:
        print(json.dumps({
            # The id a follow-up passes back as --continue.
            "id": agent_response.get("id") or run_id,
            "answer": answer_text(agent_response),
            "results": collect_sources(agent_response),
        }))
    else:
        print(format_answer(agent_response))


if __name__ == "__main__":
    main()
