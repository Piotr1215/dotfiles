#!/usr/bin/env python3
"""Refresh per-project context and source rows in the myprojects report.

Each relevant Linear project has one +view header with view_key=standing:<id>.
The newest brief: annotation holds its full deterministic Markdown overview:
verified recent completions, current issues and PR states, milestones and real
local action rows. After a successful batched import the same text is atomically
published to $XDG_STATE_HOME/taskwarrior/briefs/<header UUID>/project-status.md.
The existing project-view.timer schedules this reader every ten minutes.
Generated rows also carry string UDAs view_kind, view_title, view_state and
view_issue so the TUI can render source data without decoding descriptions.
Project state is the Linear project status; its highlighted issue has a separate
view_issue value. Existing descriptions remain compatible with older clients.

Issue and review rows keep their own issue:/ask: identity and canonical link:
annotations. They are context/source rows, never +piotr handoff copies. Actual
+piotr tasks retain their UUID and native project. Their optional view_project
UDA is set only by exact, unambiguous source ownership. Failed sources preserve
previous verified context and grouping, with source-age details in the brief.
An explicit unresolved ownership assessment uses view_project=!unassigned to
keep a native administrative or conflicting project from grouping it by fallback.
Legacy tasks without explicit source evidence keep their native project grouping;
that grouping is separate from an automatically verified association.
Real handoff grouping uses a final batched recheck and guarded view_project-only
modify commands. Real task snapshots never enter the generated-row import.

Usage: __project_view_refresh.py [--dry-run]. Dry runs write no tasks or files.
Env: PROJECT_VIEW_TASK_CMD (task), PROJECT_VIEW_GH_CMD (gh), LINEAR_API_KEY or
PROJECT_VIEW_LINEAR_KEY_CMD (pass show work/LINEAR_API_KEY),
PROJECT_VIEW_LINEAR_URL, PROJECT_VIEW_STATE (~/.local/state/project-view).
"""
import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import threading
import urllib.error
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from email.utils import parsedate_to_datetime
from pathlib import Path

TASK_CMD = shlex.split(os.environ.get("PROJECT_VIEW_TASK_CMD") or "task")
GH_CMD = shlex.split(os.environ.get("PROJECT_VIEW_GH_CMD") or "gh")
LINEAR_URL = os.environ.get("PROJECT_VIEW_LINEAR_URL", "https://api.linear.app/graphql")
LINEAR_KEY_CMD = os.environ.get("PROJECT_VIEW_LINEAR_KEY_CMD", "pass show work/LINEAR_API_KEY")
STATE_DIR = Path(os.environ.get("PROJECT_VIEW_STATE") or Path.home() / ".local/state/project-view")
BRIEFS_DIR = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "taskwarrior/briefs"

TAG = "view"
UNASSIGNED = "!unassigned"
NAMESPACE = uuid.UUID("5d1f3c2e-7a4b-4c8e-9f60-2b7e1d3a9c41")
RANK = {"issue": 1, "ask": 2, "standing": 9}
DONE = {"completed", "canceled", "duplicate"}
WINDOW = timedelta(days=7)
# A member-only project with no work of Piotr's shows only while it is alive:
# a status update or an issue change inside this window.
MEMBER_ALIVE = timedelta(days=30)
# A failed run fails the unit only once the view is this stale, so a short
# Linear, GitHub or network outage logs a WARN instead of a failure record.
STALE_VIEW = timedelta(hours=1)
RATE_FALLBACK = timedelta(minutes=15)
RATE_MAX = timedelta(hours=24)
RATE_MIN = timedelta(seconds=30)
# https://linear.app/developers/rate-limiting documents UTC epoch milliseconds
# for the named reset headers; Retry-After is a delay in seconds.
RATE_HEADERS = {"retry-after", "x-ratelimit-limit", "x-ratelimit-remaining", "x-ratelimit-reset",
                "x-ratelimit-requests-limit", "x-ratelimit-requests-remaining", "x-ratelimit-requests-reset",
                "x-ratelimit-complexity-limit", "x-ratelimit-complexity-remaining", "x-ratelimit-complexity-reset",
                "x-ratelimit-endpoint-requests-limit", "x-ratelimit-endpoint-requests-remaining",
                "x-ratelimit-endpoint-requests-reset",
                "ratelimit-limit", "ratelimit-remaining", "ratelimit-reset", "x-complexity"}
PAGES = 10
GH_CHUNK = 25
REFERENCE_LIMIT = 200
LINEAR_CHUNK = 25
HISTORY_LIMIT = 100
ISSUE_PAGE_SIZE = 20
PROJECT_ISSUE_LIMIT = 500
PROJECT_ISSUE_PAGES = PROJECT_ISSUE_LIMIT // ISSUE_PAGE_SIZE
HISTORY_PAGES = HISTORY_LIMIT // ISSUE_PAGE_SIZE
DONE_LIMIT = 20
# The issue sync files a project-less issue under its team's project
# (TEAM_PREFIX_PROJECT in __github_issue_sync.sh); a no-task row follows suit.
TEAM_PROJECT = {"DOC": "docs-maintenance", "DEVOPS": "operations", "ENGAI": "ai"}
HEALTH = {"onTrack": "on track", "atRisk": "at risk", "offTrack": "off track"}
PR_URL = re.compile(r"https://github\.com/([\w.-]+)/([\w.-]+)/pull/(\d+)")
LINK = re.compile(r"(?:https?://|www\.)\S+")
EXACT_URL = re.compile(r"https://[^\s<>\[\]()]+")
ISSUE_ID = re.compile(r"[A-Z][A-Z0-9]*-\d+", re.IGNORECASE)
LINEAR_ISSUE_URL = re.compile(r"https://linear\.app/([\w-]+)/issue/([a-z][a-z0-9]*-\d+)(?:/[\w.-]+)?", re.IGNORECASE)
SOURCE_HEADING = "\n\n## Source status\n"
VIEW_METADATA = ("view_kind", "view_title", "view_state", "view_issue")
TASK_UDA = ["rc.uda.view_project.type=string", "rc.uda.view_key.type=string",
            "rc.uda.view_rank.type=numeric", *(f"rc.uda.{field}.type=string" for field in VIEW_METADATA)]

PROJECT_FIELDS = """id name description url targetDate startDate status { name type }
  lead { name isMe }
  projectUpdates(first: 1) { nodes { createdAt health user { name } } }"""

Q_PROJECTS = """query ($after: String) {
  projects(first: 50, after: $after, filter: {
    or: [{lead: {isMe: {eq: true}}}, {members: {some: {isMe: {eq: true}}}}],
    status: {type: {in: ["started", "planned", "paused"]}}
  }) { pageInfo { hasNextPage endCursor } nodes { id lead { isMe } } }
}"""

Q_ASSIGNED = """query ($after: String) {
  viewer { assignedIssues(first: 100, after: $after,
           filter: {state: {type: {nin: ["completed", "canceled", "duplicate"]}}}) {
    pageInfo { hasNextPage endCursor }
    nodes { identifier title url state { name type } project { id name } } } }
}"""

Q_PROJECT = """query ($id: String!, $after: String) {
  project(id: $id) { FIELDS
    issues(first: 20, after: $after, filter: {or: [
      {state: {type: {nin: ["completed", "canceled", "duplicate"]}}},
      {completedAt: {gte: "-P7D"}}, {canceledAt: {gte: "-P7D"}}]}) {
      pageInfo { hasNextPage endCursor }
      nodes { identifier title url updatedAt completedAt canceledAt
              state { name type } assignee { name isMe }
              projectMilestone { id name }
              attachments(first: 100) { pageInfo { hasNextPage } nodes { url } }
              inverseRelations(first: 100) { pageInfo { hasNextPage }
                nodes { type issue { identifier state { type } } } } } } }
}""".replace("FIELDS", PROJECT_FIELDS)

Q_MILESTONES = """query ($id: String!, $after: String) {
  project(id: $id) { projectMilestones(first: 100, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes { id name description targetDate sortOrder progress status updatedAt }
  } }
}"""

# History needs PR attachments for proof and ownership; only open work renders
# blockers, assignees and issue-to-milestone assignments.
Q_COMPLETED = """query ($id: String!, $after: String) {
  project(id: $id) { issues(first: 20, after: $after, orderBy: updatedAt, includeArchived: true,
      filter: {state: {type: {eq: "completed"}}}) {
    pageInfo { hasNextPage endCursor }
    nodes { identifier title url updatedAt completedAt state { type }
      attachments(first: 100) { pageInfo { hasNextPage } nodes { url } }
    }
  } }
}"""


def warn(message):
    """Log a skipped source with what happens next."""
    print(f"project-view: WARN {message}", file=sys.stderr)


def kebab(name):
    """Turn a Linear project name into the Taskwarrior project the issue sync writes."""
    text = re.sub(r"\s+", "-", (name or "").strip().lower())
    text = re.sub(r"[^a-z0-9._-]", "", text)
    return re.sub(r"-+", "-", text).strip("-")


def parse_time(value):
    """Read a Linear or GitHub ISO timestamp as an aware datetime, or None."""
    if not value:
        return None
    return datetime.fromisoformat(value)


def tw_time(moment):
    """Format a datetime as a Taskwarrior UTC stamp."""
    return moment.astimezone(UTC).strftime("%Y%m%dT%H%M%SZ")


def day(moment, now=None):
    """Short date, for example 8 Dec; the year joins when it is not now's year."""
    text = f"{moment.day} {moment.strftime('%b')}"
    return text if now is None or moment.year == now.year else f"{text} {moment.year}"


def ago(moment, now):
    """How long ago, in whole days: today, 1d ago, 12d ago."""
    days = (now - moment).days
    return "today" if days <= 0 else f"{days}d ago"


def clean(text, limit=70):
    """One line of a title with links removed, so key 1 never offers them."""
    text = LINK.sub("[link]", " ".join(str(text or "").split()))
    return text if len(text) <= limit else text[:limit - 1] + "…"


def pr_ref(url):
    """owner/repo#n for a GitHub PR URL, or None."""
    match = PR_URL.fullmatch(url or "")
    return f"{match[1]}/{match[2]}#{match[3]}".lower() if match else None


def short_ref(ref):
    """repo#n from owner/repo#n."""
    return ref.split("/", 1)[1]


def row_uuid(key):
    """The fixed uuid of a view row."""
    return str(uuid.uuid5(NAMESPACE, key))


# Sources ---------------------------------------------------------------------

def safe_rate_headers(headers):
    """Keep only recognized numeric limits and a parsed retry date, never auth."""
    safe = {}
    for name, value in (headers or {}).items():
        name, value = name.lower(), str(value).strip()
        if name not in RATE_HEADERS:
            continue
        if re.fullmatch(r"\d+(?:\.\d+)?", value):
            safe[name] = value
        elif name == "retry-after":
            try:
                stamp = parsedate_to_datetime(value)
            except (TypeError, ValueError):
                try:
                    stamp = parse_time(value)
                except (TypeError, ValueError):
                    continue
            if stamp and stamp.tzinfo:
                safe[name] = stamp.astimezone(UTC).isoformat()
    return safe


def rate_limit_record(headers, now):
    safe = safe_rate_headers(headers)
    retry = safe.get("retry-after")
    deadline = None
    if retry:
        try:
            deadline = now + timedelta(seconds=float(retry)) if re.fullmatch(r"\d+(?:\.\d+)?", retry) else parse_time(retry)
        except (OverflowError, ValueError):
            pass
    if deadline is None:
        resets = []
        for name, value in safe.items():
            if name.endswith("reset"):
                try:
                    number = float(value)
                    stamp = (now + timedelta(seconds=number) if name == "ratelimit-reset" else
                             datetime.fromtimestamp(number / 1000 if number > 100_000_000_000 else number, UTC))
                    if stamp > now:
                        resets.append(stamp)
                except (OverflowError, ValueError, OSError):
                    pass
        deadline = max(resets) if resets else now + RATE_FALLBACK
    deadline = max(now + RATE_MIN, min(deadline, now + RATE_MAX))
    return {"status": 429, "observed_at": now.isoformat(), "retry_at": deadline.isoformat(), "headers": safe}


class LinearRateLimited(RuntimeError):
    def __init__(self, record):
        self.record = record
        super().__init__(f"Linear rate limited (HTTP 429); retry at {record['retry_at']}")


class Linear:
    """A small Linear GraphQL client that reads its key once."""

    def __init__(self, key, on_rate_limit=None):
        self.key = key
        self.rate_limit = None
        self.request_count = 0
        self._stop = threading.Event()
        self._lock = threading.Lock()
        self._on_rate_limit = on_rate_limit

    def query(self, text, variables=None):
        with self._lock:
            if self._stop.is_set():
                raise LinearRateLimited(self.rate_limit)
            self.request_count += 1
        body = json.dumps({"query": text, "variables": variables or {}}).encode()
        request = urllib.request.Request(LINEAR_URL, data=body, headers={
            "Authorization": self.key, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                reply = json.load(response)
        except urllib.error.HTTPError as error:
            if error.code != 429:
                raise
            record = rate_limit_record(error.headers, datetime.now(UTC))
            with self._lock:
                if self.rate_limit is None or record["retry_at"] > self.rate_limit["retry_at"]:
                    self.rate_limit = record
                    self._stop.set()
                    if self._on_rate_limit:
                        self._on_rate_limit(record)
            raise LinearRateLimited(self.rate_limit) from None
        if reply.get("errors"):
            raise RuntimeError(reply["errors"][0].get("message", "Linear error"))
        return reply["data"]

    def pages(self, text, path, variables=None):
        """Yield every node of a paginated connection, failing on a partial read."""
        after = None
        for _ in range(PAGES):
            data = self.query(text, {**(variables or {}), "after": after})
            node = data
            for step in path:
                node = node[step]
            yield from node["nodes"]
            if not node["pageInfo"]["hasNextPage"]:
                return
            after = node["pageInfo"]["endCursor"]
        raise RuntimeError(f"more than {PAGES} pages")


def linear_key():
    """LINEAR_API_KEY, else the first line the key command prints."""
    key = os.environ.get("LINEAR_API_KEY", "").strip()
    if key:
        return key
    result = subprocess.run(shlex.split(LINEAR_KEY_CMD), capture_output=True, text=True, timeout=30, check=False)
    if result.returncode != 0 or not result.stdout.strip():
        raise RuntimeError(f"no Linear key: `{LINEAR_KEY_CMD}` failed")
    return result.stdout.strip().splitlines()[0]


def complete_issue_links(issues, fields=("attachments", "inverseRelations")):
    """Never infer ownership or blockers from a truncated nested connection."""
    for issue in issues:
        for field in fields:
            if issue[field].get("pageInfo", {}).get("hasNextPage"):
                raise RuntimeError(f"{issue['identifier']} has more than 100 {field}")


def issue_cursor(connection, seen, source):
    """A partial issue connection requires a new, nonempty continuation cursor."""
    if not connection["pageInfo"]["hasNextPage"]:
        return None
    after = connection["pageInfo"].get("endCursor")
    if not isinstance(after, str) or not after or after in seen:
        raise RuntimeError(f"{source} pagination cursor missing or repeated")
    seen.add(after)
    return after


def read_completed(linear, project_id):
    """Read up to 100 completed issues in small pages, with intentional truncation."""
    issues, after, seen = [], None, set()
    for _ in range(HISTORY_PAGES):
        data = linear.query(Q_COMPLETED, {"id": project_id, "after": after})["project"]["issues"]
        complete_issue_links(data["nodes"], fields=("attachments",))
        issues.extend(data["nodes"])
        after = issue_cursor(data, seen, "completed issue history")
        if after is None:
            return issues, False
    return issues, True


def read_project(linear, project_id):
    """One project, up to 500 current issues and a bounded completion history."""
    issues, fields, after, seen = [], None, None, set()
    for _ in range(PROJECT_ISSUE_PAGES):
        data = linear.query(Q_PROJECT, {"id": project_id, "after": after})["project"]
        fields = fields or {k: v for k, v in data.items() if k != "issues"}
        complete_issue_links(data["issues"]["nodes"])
        issues.extend(data["issues"]["nodes"])
        after = issue_cursor(data["issues"], seen, "project issues")
        if after is None:
            break
    else:
        raise RuntimeError(f"more than {PROJECT_ISSUE_LIMIT} current project issues ({PROJECT_ISSUE_PAGES} pages)")
    milestones = list(linear.pages(Q_MILESTONES, ["project", "projectMilestones"], {"id": project_id}))
    history, truncated = read_completed(linear, project_id)
    all_issues = {i["identifier"]: i for i in [*issues, *history]}
    return {**fields, "issues": list(all_issues.values()), "milestones": milestones,
            "history_truncated": truncated, "history_count": len(history)}


def task_urls(task):
    """Explicit URLs, including Markdown destinations, rather than prose IDs."""
    text = "\n".join([task.get("description") or "", task.get("url") or "",
                      *(a.get("description") or "" for a in task.get("annotations") or [])])
    return {url.rstrip(".,;:") for url in EXACT_URL.findall(text)}


def referenced_identifiers(tasks):
    identifiers = set()
    for task in tasks:
        if "piotr" not in (task.get("tags") or []) or TAG in (task.get("tags") or []):
            continue
        ident = task.get("linear_issue_id") or ""
        if ISSUE_ID.fullmatch(ident):
            identifiers.add(ident.upper())
        for url in task_urls(task):
            match = LINEAR_ISSUE_URL.fullmatch(url)
            if match:
                identifiers.add(match[2].upper())
    return identifiers


def read_referenced(linear, identifiers):
    """Bounded batches resolve handoff references outside the recent issue window."""
    wanted = sorted(identifiers)
    if len(wanted) > REFERENCE_LIMIT:
        raise RuntimeError(f"more than {REFERENCE_LIMIT} unresolved handoff issue references")
    found = []
    for start in range(0, len(wanted), LINEAR_CHUNK):
        chunk = wanted[start:start + LINEAR_CHUNK]
        fields = " ".join(f'i{i}: issue(id: {json.dumps(ident)}) '
                          '{ identifier title url state { name type } project { id name } }'
                          for i, ident in enumerate(chunk))
        data = linear.query("query { " + fields + " }")
        for i, ident in enumerate(chunk):
            issue = data.get(f"i{i}")
            if issue:
                if issue["identifier"].upper() != ident:
                    raise RuntimeError("Linear returned a different issue for an exact reference")
                found.append(issue)
    return found


def read_linear(linear, tasks=()):
    """Projects Piotr leads or is in, his open assigned issues, and each project's issues.

    The project list must read whole, or the run stops: without it no row can
    be called obsolete. A project or the assigned list that fails is reported in
    failures and its rows are kept.
    """
    listed = {n["id"]: bool((n.get("lead") or {}).get("isMe"))
              for n in linear.pages(Q_PROJECTS, ["projects"])}
    failures, assigned = [], None
    try:
        assigned = list(linear.pages(Q_ASSIGNED, ["viewer", "assignedIssues"]))
    except Exception as error:  # noqa: BLE001 - any failure keeps the no-task rows
        failures.append(f"assigned issues: {error}")
        warn(f"assigned issues unreadable ({error}); the no-task rows stay as they were")
    wanted = set(listed)
    wanted.update(i["project"]["id"] for i in assigned or [] if i.get("project"))
    projects = {}
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pid: pool.submit(read_project, linear, pid) for pid in sorted(wanted)}
    for pid, future in futures.items():
        try:
            projects[pid] = {**future.result(), "listed": pid in listed, "led": listed.get(pid, False)}
        except Exception as error:  # noqa: BLE001 - one project failing keeps its rows
            failures.append(f"project {pid}: {error}")
            warn(f"project {pid} unreadable ({error}); its rows stay as they were")
    known = {i["identifier"].upper() for p in projects.values() for i in p["issues"]}
    known.update(i["identifier"].upper() for i in assigned or [])
    referenced, reference_failure, reference_rate_limited = [], False, False
    try:
        referenced = read_referenced(linear, referenced_identifiers(tasks) - known)
        structured = {t["linear_issue_id"].upper() for t in tasks
                      if "piotr" in (t.get("tags") or []) and TAG not in (t.get("tags") or [])
                      and ISSUE_ID.fullmatch(t.get("linear_issue_id") or "")}
        routes = {(match[1].lower(), match[2].upper()) for task in tasks
                  if "piotr" in (task.get("tags") or []) and TAG not in (task.get("tags") or [])
                  for url in task_urls(task) if (match := LINEAR_ISSUE_URL.fullmatch(url))}
        referenced = [i for i in referenced if i["identifier"].upper() in structured
                      or ((match := LINEAR_ISSUE_URL.fullmatch(i["url"]))
                          and (match[1].lower(), match[2].upper()) in routes)]
    except Exception as error:
        reference_failure = True
        reference_rate_limited = isinstance(error, LinearRateLimited)
        failures.append(f"handoff issue ownership: {error}")
        warn(f"handoff issue ownership unavailable ({error}); previous grouping stays")
    additional = {i["project"]["id"] for i in referenced if i.get("project")} - wanted
    wanted.update(additional)
    if additional:
        with ThreadPoolExecutor(max_workers=4) as pool:
            futures = {pid: pool.submit(read_project, linear, pid) for pid in sorted(additional)}
        for pid, future in futures.items():
            try:
                projects[pid] = {**future.result(), "listed": False, "led": False}
            except Exception as error:
                failures.append(f"project {pid}: {error}")
                warn(f"referenced project {pid} unavailable ({error}); previous grouping stays")
    return {"projects": projects, "assigned": assigned, "wanted": sorted(wanted), "failures": failures,
            "referenced": referenced, "reference_failure": reference_failure,
            "reference_rate_limited": reference_rate_limited, "rate_limit": linear.rate_limit}


def gh_graphql(query):
    """Run one gh GraphQL query; incomplete replies cannot verify ownership."""
    result = subprocess.run([*GH_CMD, "api", "graphql", "-f", f"query={query}"],
                            capture_output=True, text=True, timeout=60, check=False)
    try:
        reply = json.loads(result.stdout or "{}")
    except json.JSONDecodeError:
        reply = {}
    if result.returncode or reply.get("errors") or not reply.get("data"):
        raise RuntimeError((result.stderr or "gh api graphql failed").strip().splitlines()[-1])
    return reply["data"]


def read_github(refs):
    """Piotr's open PRs, his teams, and the state of every attached PR in refs."""
    viewer = gh_graphql("query { viewer { login } }")["viewer"]
    login = viewer["login"]
    mine = {}
    after = None
    for _ in range(PAGES):
        page = gh_graphql("query { viewer { pullRequests(states: OPEN, first: 100, after: "
                          + json.dumps(after) + ") { pageInfo { hasNextPage endCursor } "
                          "nodes { url state title isDraft reviewDecision } } } }")["viewer"]["pullRequests"]
        mine.update({pr_ref(n["url"]): n for n in page["nodes"] if pr_ref(n["url"])})
        if not page["pageInfo"]["hasNextPage"]:
            break
        after = page["pageInfo"]["endCursor"]
    else:
        raise RuntimeError(f"more than {PAGES} pages of own PRs")
    owners = sorted({ref.split("/", 1)[0] for ref in refs})
    teams = set()
    if owners:
        fields = " ".join(
            f'o{i}: organization(login: {json.dumps(owner)}) '
            f'{{ login teams(first: 100, userLogins: [{json.dumps(login)}]) '
            f'{{ pageInfo {{ hasNextPage }} nodes {{ slug }} }} }}'
            for i, owner in enumerate(owners))
        for org in gh_graphql(f"query {{ {fields} }}").values():
            if org:
                if org["teams"]["pageInfo"]["hasNextPage"]:
                    raise RuntimeError("more than 100 teams in an organization")
                teams.update(f"{org['login'].lower()}/{t['slug']}" for t in org["teams"]["nodes"])
    prs, unavailable = read_attached_prs(refs)
    return {"login": login, "mine": mine, "teams": teams, "prs": prs,
            "unavailable_refs": unavailable}


def read_attached_prs(refs):
    """Isolate unreadable PRs without discarding a healthy batch.

    A failing batch is bisected to single refs. For n refs in each original
    chunk, at most 2*n-1 queries run; a healthy chunk needs one. Null or
    incomplete PR replies remain unknown rather than being treated as closed.
    """
    prs, unavailable = {}, set()

    def read_chunk(chunk):
        fields = []
        for i, ref in enumerate(chunk):
            repo, number = ref.split("#")
            owner, name = repo.split("/")
            fields.append(
                f'p{i}: repository(owner: {json.dumps(owner)}, name: {json.dumps(name)}) '
                f'{{ pullRequest(number: {number}) {{ url state mergedAt closedAt isDraft reviewDecision title '
                f'author {{ login }} reviewRequests(first: 100) {{ pageInfo {{ hasNextPage }} nodes {{ requestedReviewer '
                f'{{ __typename ... on User {{ login }} ... on Team {{ slug organization {{ login }} }} }} }} }} }} }}')
        try:
            data = gh_graphql("query { " + " ".join(fields) + " }")
        except Exception:  # One unreadable repository must not poison other refs.
            if len(chunk) == 1:
                unavailable.add(chunk[0])
                return
            middle = len(chunk) // 2
            read_chunk(chunk[:middle])
            read_chunk(chunk[middle:])
            return
        for i, ref in enumerate(chunk):
            pr = (data.get(f"p{i}") or {}).get("pullRequest")
            if (not pr or not pr.get("state") or not pr.get("url")
                    or pr.get("reviewRequests", {}).get("pageInfo", {}).get("hasNextPage") is not False):
                unavailable.add(ref)
            else:
                prs[ref] = pr

    wanted = sorted(refs)
    for start in range(0, len(wanted), GH_CHUNK):
        read_chunk(wanted[start:start + GH_CHUNK])
    return prs, unavailable


def task_json(*args):
    """Export tasks through Taskwarrior with no context and no hooks."""
    result = subprocess.run([*TASK_CMD, *TASK_UDA, "rc.context=none", "rc.hooks=off", "rc.verbose=nothing",
                             "rc.confirmation=off", *args, "export"],
                            capture_output=True, text=True, timeout=60, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"task export failed: {result.stderr.strip()}")
    return json.loads(result.stdout or "[]")


# Rows ------------------------------------------------------------------------

def attached_refs(issue):
    """The GitHub PRs attached to an issue, as owner/repo#n."""
    return sorted({r for r in (pr_ref(a["url"]) for a in issue["attachments"]["nodes"]) if r})


def requested(pr, login, teams):
    """Who on Piotr's side a PR asks: 'you', 'via <team>', or None."""
    via = None
    for node in pr["reviewRequests"]["nodes"]:
        who = node.get("requestedReviewer") or {}
        if who.get("__typename") == "User" and who.get("login", "").lower() == login.lower():
            return "you"
        if who.get("__typename") == "Team":
            team = f"{who['organization']['login'].lower()}/{who['slug']}"
            if team in teams:
                via = via or f"via {who['slug']}"
    return via


def pr_note(pr):
    """A PR's review state in a few words."""
    if pr.get("isDraft"):
        return "draft"
    return {"APPROVED": "approved", "CHANGES_REQUESTED": "changes requested"}.get(
        pr.get("reviewDecision"), "awaiting review")


def bucket(issue):
    """The open-issue bucket a state falls in."""
    if issue["state"]["name"].lower() == "parked":
        return "parked"
    return {"unstarted": "todo"}.get(issue["state"]["type"], issue["state"]["type"])


def markdown(text):
    """Keep source titles on one Markdown line, including their full wording."""
    return " ".join(str(text or "").split()).replace("[", "\\[").replace("]", "\\]")


def issue_link(issue):
    return f"[{issue['identifier']} {markdown(issue['title'])}]({issue['url']})"


def active_issues(project):
    """The same source-backed activity ordering used by the brief and row."""
    return sorted((i for i in project["issues"] if i["state"]["type"] not in DONE),
                  key=lambda i: (bucket(i) != "started", i["identifier"]))


def standing(project, tasks, github, now):
    """A deterministic, evidence-backed overview shared by every project."""
    issues = project["issues"]
    open_ = active_issues(project)
    completed = sorted((i for i in issues if i["state"]["type"] == "completed"
                        and parse_time(i.get("completedAt"))),
                       key=lambda i: (i["completedAt"], i["identifier"]), reverse=True)
    milestones = sorted(project.get("milestones") or [],
                        key=lambda m: (m.get("sortOrder") or 0, m["id"]))
    achieved = [m for m in milestones if m.get("status") == "done"]
    target = project.get("targetDate") or "not set"
    lead = (project.get("lead") or {}).get("name") or "unassigned"
    lines = [f"# {markdown(project['name'])}", "", f"[Linear project]({project['url']})",
             f"State: {project['status']['name']}. Lead: {lead}. Target: {target}."]
    if project.get("description"):
        lines.extend(["", project["description"].strip()])
    updates = (project.get("projectUpdates") or {}).get("nodes") or []
    if updates:
        update = updates[0]
        lines.extend(["", "Latest project update: " + update["createdAt"][:10]
                      + ", " + HEALTH.get(update.get("health"), update.get("health") or "no health") + "."])
    lines.extend(["", "## Done", "", "Verified achievements so far:"])
    for milestone in achieved:
        lines.append(f"- [Milestone {markdown(milestone['name'])}]({project['url']}). "
                     f"Linear status done; source ID {milestone['id']}; "
                     f"source updated {milestone.get('updatedAt') or 'unknown'}. "
                     "The source does not provide a completion date.")
    lines.extend(f"- {issue_link(i)}. Linear completed {i['completedAt'][:10]}." for i in completed[:DONE_LIMIT])
    refs = {}
    for issue in issues:
        for ref in attached_refs(issue):
            refs.setdefault(ref, []).append(issue["identifier"])
    merged = []
    if github is not None:
        for ref in sorted(refs):
            if ref in github.get("unavailable_refs", ()):
                continue
            pr = github["prs"].get(ref)
            when = parse_time((pr or {}).get("mergedAt"))
            if pr and pr["state"] == "MERGED" and when:
                merged.append((pr["mergedAt"], f"- [{ref} {markdown(pr.get('title'))}]({pr['url']}). "
                               f"GitHub merged {pr['mergedAt'][:10]} ({', '.join(refs[ref])})."))
    lines.extend(text for _, text in sorted(merged, reverse=True)[:DONE_LIMIT])
    if not completed and not merged and not achieved:
        lines.append("- No verified completions in the available source history.")
    lines.extend(["", f"History scope: all project milestones; up to {HISTORY_LIMIT} most recently updated completed issues "
                  f"(including archived issues), with up to {DONE_LIMIT} shown by completion date; "
                  f"up to {DONE_LIMIT} merged PRs attached to the fetched issues."])
    if project.get("history_truncated") or len(completed) > DONE_LIMIT or len(merged) > DONE_LIMIT:
        lines.append("History is truncated; open Linear for the complete record.")
    lines.extend(["", "## Now", ""])
    for issue in open_:
        owner = (issue.get("assignee") or {}).get("name") or "unassigned"
        milestone = (issue.get("projectMilestone") or {}).get("name")
        text = f"- {issue_link(issue)}. {issue['state']['name']}; owner {owner}"
        if milestone:
            text += f"; milestone {markdown(milestone)}"
        blockers = sorted(r["issue"]["identifier"] for r in issue["inverseRelations"]["nodes"]
                          if r["type"] == "blocks" and r["issue"]["state"]["type"] not in DONE)
        if blockers:
            text += "; waiting on " + ", ".join(blockers)
        if issue.get("updatedAt"):
            text += "; source updated " + issue["updatedAt"][:10]
        lines.append(text + ".")
    if not open_:
        lines.append("- No open issues in the verified project source.")
    if github is None:
        lines.append("- GitHub unavailable. Current PR and review states are unknown.")
    else:
        for ref in sorted(refs):
            if ref in github.get("unavailable_refs", ()):
                url = "https://github.com/" + ref.replace("#", "/pull/")
                lines.append(f"- [{ref}]({url}). GitHub unavailable; current PR and review states are unknown.")
                continue
            pr = github["prs"].get(ref) or github["mine"].get(ref)
            if not pr:
                lines.append(f"- {ref}: GitHub state unavailable.")
                continue
            if pr.get("state", "OPEN") == "MERGED":
                continue
            state = pr_note(pr) if pr.get("state", "OPEN") == "OPEN" else pr["state"].lower()
            url = pr.get("url") or "https://github.com/" + ref.replace("#", "/pull/")
            lines.append(f"- [{ref} {markdown(pr.get('title'))}]({url}). {state} "
                         f"({', '.join(refs[ref])}).")
    lines.extend(["", "## Milestones", ""])
    for milestone in milestones:
        progress = milestone.get("progress")
        progress_text = f"{progress * 100:g}%" if isinstance(progress, (int, float)) and 0 <= progress <= 1 else "unavailable"
        text = (f"- [{markdown(milestone['name'])}]({project['url']}). "
                f"State: {milestone.get('status') or 'unavailable'}; progress: {progress_text}; "
                f"target: {milestone.get('targetDate') or 'not set'}; source ID {milestone['id']}.")
        if milestone.get("description"):
            text += " " + markdown(milestone["description"])
        lines.append(text)
    if not milestones:
        lines.append("- No milestones are defined in the verified project source.")
    lines.extend(["", "## Next", "", "Use the action rows under this project in myprojects."])
    for task in sorted(tasks, key=lambda t: (t.get("priority") not in ("H",), t.get("uuid", ""))):
        state = "waiting" if task.get("status") == "waiting" or task.get("wait") else "pending"
        ident = task.get("linear_issue_id") or task.get("uuid", "")
        lines.append(f"- {markdown(task.get('description'))} ({ident}; {state}).")
    if not tasks:
        lines.append("No local action rows are linked to this project.")
    lines.extend(["", "Current-work scope: all open issues plus recent closed issues and the bounded completion history. "
                  "Completion and merge records do not establish deployment."])
    activity = open_[0] if open_ else None
    summary = (f"{activity['identifier']} {clean(activity['title'], 70)} ({activity['state']['name']})"
               if activity else project["status"]["name"])
    return "standing · " + summary, "\n".join(lines)


def pending_for_grouping(task):
    """Match Taskwarrior's pending filter, including its virtual waiting state."""
    if task.get("status") != "pending":
        return False
    try:
        wait = parse_time(task.get("wait"))
        return wait is None or wait <= datetime.now(UTC)
    except (TypeError, ValueError):
        return False


def association_plan(snapshot, tasks, github_available=True, unavailable_refs=()):
    """Add grouping only for exact structured links with one verified owner.

    Native project and all other task fields remain unchanged. Any incomplete
    source keeps prior grouping. Successful conflicting or unresolved evidence
    marks grouping !unassigned instead of guessing from a title or team project.
    No-evidence legacy tasks retain native grouping, and an existing unresolved
    marker persists when its source links disappear.
    """
    if snapshot.get("failures") or snapshot.get("assigned") is None or not github_available:
        return [], tasks
    projects = snapshot["projects"]
    identifiers, urls, prs = {}, {}, {}
    def add(index, key, pid):
        if key:
            index.setdefault(key, set()).add(pid)
    for pid, project in projects.items():
        for issue in project["issues"]:
            add(identifiers, issue["identifier"], pid)
            add(urls, issue["url"], pid)
            for ref in attached_refs(issue):
                add(prs, ref, pid)
    for issue in [*(snapshot.get("assigned") or []), *(snapshot.get("referenced") or [])]:
        pid = (issue.get("project") or {}).get("id")
        if pid in projects:
            add(identifiers, issue["identifier"], pid)
            add(urls, issue["url"], pid)
    changes, resolved = [], []
    unavailable_refs = set(unavailable_refs)
    for task in tasks:
        if (not pending_for_grouping(task) or "piotr" not in (task.get("tags") or [])
                or TAG in (task.get("tags") or [])):
            resolved.append(task)
            continue
        if any(pr_ref(url) in unavailable_refs for url in task_urls(task)):
            # Ownership based on this source is unknown. Keep its last verified
            # grouping while unrelated exact references can still proceed.
            resolved.append(task)
            continue
        owners, unresolved, assessed = set(), False, False
        ident = task.get("linear_issue_id")
        if ident:
            assessed = True
            found = identifiers.get(ident.upper(), set())
            owners.update(found)
            unresolved = not found
        for url in task_urls(task):
            ref = pr_ref(url)
            if url in urls:
                assessed = True
                owners.update(urls[url])
            elif LINEAR_ISSUE_URL.fullmatch(url):
                assessed = True
                # Linear's exact issue route identifies the same entity even
                # after a title slug changes. Require its source workspace too.
                match = LINEAR_ISSUE_URL.fullmatch(url)
                source_owners = set()
                for source_url, projects_here in urls.items():
                    source_match = LINEAR_ISSUE_URL.fullmatch(source_url)
                    if (source_match and source_match[1].lower() == match[1].lower()
                            and source_match[2].upper() == match[2].upper()):
                        source_owners.update(projects_here)
                owners.update(source_owners)
                unresolved = unresolved or not source_owners
            elif ref:
                assessed = True
                found = prs.get(ref, set())
                owners.update(found)
                unresolved = unresolved or not found
            elif url.startswith("https://linear.app/") and "/issue/" in url:
                assessed = True
                unresolved = True
        slug = kebab(projects[next(iter(owners))]["name"]) if len(owners) == 1 and not unresolved else ""
        # Two projects sharing a native slug are equally ambiguous for grouping.
        if slug and sum(kebab(p["name"]) == slug for p in projects.values()) != 1:
            slug = ""
        if not slug and (assessed or task.get("view_project")):
            # An explicit failed assessment must suppress native-project
            # fallback too. This reserved value cannot equal a source slug.
            slug = UNASSIGNED
        updated = dict(task)
        if slug != (task.get("view_project") or ""):
            updated["view_project"] = slug
            changes.append({"uuid": task["uuid"], "view_project": slug,
                            "expected": association_evidence(task)})
        resolved.append(updated)
    return changes, resolved


def association_evidence(task):
    """Fields used to reject an association whose local evidence changed."""
    return {"project": task.get("project") or "", "linear_issue_id": task.get("linear_issue_id") or "",
            "description": task.get("description") or "", "urls": sorted(task_urls(task)),
            "view_project": task.get("view_project") or ""}


def apply_associations(intents):
    """Revalidate once, then atomically modify only a pending handoff's grouping.

    Taskwarrior import replaces omitted fields, so real task snapshots must
    never enter the view-row import. Native project, issue ID, description and
    prior grouping also remain filters at mutation time. Annotation URLs are
    checked in the final batched export; unrelated new annotations survive.
    """
    result = {"changed": 0, "skipped": 0}
    if not intents:
        return result
    selectors = []
    for intent in intents:
        uid = intent["uuid"]
        if str(uuid.UUID(uid)) != uid.lower():
            raise ValueError("association UUID must be canonical")
        if selectors:
            selectors.append("or")
        selectors.append("uuid:" + uid)
    current = {t["uuid"]: t for t in task_json("(", *selectors, ")")}
    for intent in intents:
        task = current.get(intent["uuid"])
        if (not task or not pending_for_grouping(task) or "piotr" not in (task.get("tags") or [])
                or TAG in (task.get("tags") or []) or association_evidence(task) != intent["expected"]):
            result["skipped"] += 1
            continue
        expected = intent["expected"]
        reply = subprocess.run([*TASK_CMD, *TASK_UDA, "rc.context=none", "rc.hooks=off",
                                "rc.confirmation=off", "rc.bulk=0", "rc.verbose=nothing",
                                "uuid:" + intent["uuid"], "status:pending", "+piotr", "-view",
                                "project.is:" + expected["project"],
                                "linear_issue_id.is:" + expected["linear_issue_id"],
                                "description.is:" + expected["description"],
                                "view_project.is:" + expected["view_project"],
                                "modify", "view_project:" + intent["view_project"]],
                               capture_output=True, text=True, encoding="utf-8", timeout=60, check=False)
        if reply.returncode == 0:
            result["changed"] += 1
        elif reply.returncode == 1 and not reply.stdout.strip() and not reply.stderr.strip():
            # Taskwarrior reports no match this way with verbose=nothing. A
            # completion or guarded-field edit after the export wins the race.
            result["skipped"] += 1
        else:
            raise RuntimeError(f"task grouping modify failed: {reply.stderr.strip()}")
    return result


def build_rows(snapshot, tasks, github, now):
    """Every view row the sources call for, keyed by view_key.

    Returns (rows, scopes): scopes names what this run could judge, so a row
    outside it is kept rather than deleted.
    """
    live = [t for t in tasks if TAG not in (t.get("tags") or [])]
    tracked = {t["linear_issue_id"] for t in live if t.get("linear_issue_id")}
    by_project = {}
    for task in live:
        group = task.get("view_project") or task.get("project") or ""
        by_project.setdefault(group, []).append(task)
    rows = {}

    assigned = snapshot["assigned"]
    mine_by_project = {}
    for issue in assigned or []:
        if issue.get("project"):
            mine_by_project.setdefault(issue["project"]["id"], []).append(issue)
        if issue["identifier"] in tracked:
            continue
        if issue.get("project"):
            project = kebab(issue["project"]["name"])
        else:
            project = TEAM_PROJECT.get(issue["identifier"].split("-")[0], "no-project")
        key = f"issue:{issue['identifier']}"
        rows[key] = {
            "project": project, "rank": RANK["issue"],
            "description": f"no task · {issue['identifier']} {issue['state']['name']} · {clean(issue['title'])}",
            "view_kind": "issue", "view_title": clean(issue["title"], 200),
            "view_state": issue["state"]["name"], "view_issue": issue["identifier"],
            "annotations": [issue["url"], "link: " + issue["url"]],
        }

    for pid, project in snapshot["projects"].items():
        name = kebab(project["name"])
        tasks_here = [t for t in by_project.get(name, []) if t.get("linear_issue_id") or "piotr" in (t.get("tags") or [])]
        updates = project["projectUpdates"]["nodes"]
        last_update = parse_time(updates[0]["createdAt"]) if updates else None
        recent = any(parse_time(i["updatedAt"]) >= now - WINDOW for i in project["issues"])
        has_work = bool(tasks_here or mine_by_project.get(pid))
        alive = (last_update and last_update >= now - MEMBER_ALIVE) or recent
        if not (project["led"] or has_work or alive):
            continue
        description, detail = standing(project, tasks_here, github, now)
        activity = next(iter(active_issues(project)), None)
        rows[f"standing:{pid}"] = {
            "project": name, "rank": RANK["standing"], "description": description,
            "view_kind": "project", "view_title": clean(activity["title"] if activity else project["name"], 200),
            "view_state": project["status"]["name"], "view_issue": activity["identifier"] if activity else "",
            "annotations": [project["url"], "brief: " + detail.rstrip() + "\n"],
        }
        if github is None:
            continue
        seen = set()
        for issue in project["issues"]:
            if issue["state"]["type"] in DONE:
                continue
            for ref in attached_refs(issue):
                if ref in github.get("unavailable_refs", ()):
                    continue
                pr = github["prs"].get(ref)
                if ref in seen or ref in github["mine"] or not pr or pr["state"] != "OPEN" or pr.get("isDraft"):
                    continue
                who = requested(pr, github["login"], github["teams"])
                if not who:
                    continue
                seen.add(ref)
                owner_repo, number = ref.split("#")
                author = (pr.get("author") or {}).get("login", "ghost")
                suffix = "" if who == "you" else f" · {who}"
                rows[f"ask:{pid}:{ref}"] = {
                    "project": name, "rank": RANK["ask"],
                    "view_kind": "ask", "view_title": clean(pr["title"], 200),
                    "view_state": pr_note(pr), "view_issue": issue["identifier"],
                    "description": f"review ask · {short_ref(ref)} · {author} · {clean(pr['title'], 60)} "
                                   f"({issue['identifier']}){suffix}",
                    # Keep the original row link and an explicit canonical target.
                    "annotations": [f"https://github.com/{owner_repo}/issues/{number}",
                                    f"link: https://github.com/{owner_repo}/pull/{number}"],
                }

    scopes = {
        "assigned": assigned is not None,
        "github": github is not None,
        "unavailable_refs": set(github.get("unavailable_refs", ())) if github is not None else set(),
        "projects": set(snapshot["projects"]),
        "wanted": set(snapshot["wanted"]),
    }
    return rows, scopes


def judged(key, scopes):
    """Whether this run read enough to delete a row with this key."""
    kind, _, rest = key.partition(":")
    if kind == "issue":
        return scopes["assigned"]
    if kind == "standing":
        return rest in scopes["projects"] or rest not in scopes["wanted"]
    if kind == "ask":
        pid, _, ref = rest.partition(":")
        if ref in scopes.get("unavailable_refs", ()):
            return False
        return scopes["github"] and (pid in scopes["projects"] or pid not in scopes["wanted"])
    return False


def plan(rows, scopes, existing, now):
    """The task import payload that turns the existing view rows into rows.

    Unchanged rows are left out, an annotation whose text did not change keeps
    its entry stamp, and a row no source calls for is deleted only when this run
    could judge it.
    """
    by_key = {t.get("view_key"): t for t in existing if TAG in (t.get("tags") or [])}
    payload, changes = [], {"add": [], "change": [], "delete": []}
    for key, row in sorted(rows.items()):
        old = by_key.get(key)
        uid = old["uuid"] if old else row_uuid(key)
        old_notes = {a["description"]: a["entry"] for a in (old or {}).get("annotations") or []}
        # Keep human annotations and fields; replace only this writer's content.
        notes = [a for a in (old or {}).get("annotations") or []
                 if not a["description"].startswith(("brief:", "standing of ", "link: "))]
        latest = max((a.get("entry", "") for a in (old or {}).get("annotations") or []), default="")
        note_time = max(now, datetime.strptime(latest, "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC)
                        + timedelta(seconds=1)) if latest else now
        for offset, text in enumerate(row["annotations"]):
            if any(a["description"] == text for a in notes):
                continue
            notes.append({"entry": old_notes.get(text) or tw_time(note_time + timedelta(seconds=offset)),
                          "description": text})
        notes.sort(key=lambda a: a["entry"])
        want = {k: v for k, v in (old or {}).items() if k not in ("id", "urgency", "modified", "wait", "end")}
        want.update({"uuid": uid, "status": "pending", "description": row["description"],
                "project": row["project"], "tags": [TAG], "view_rank": row["rank"],
                "view_key": key, "annotations": notes})
        want.update({field: row.get(field, "") for field in VIEW_METADATA})
        if old:
            want["entry"] = old["entry"]
            same = (old.get("status") == "pending" and old.get("description") == want["description"]
                    and old.get("project") == want["project"] and sorted(old.get("tags") or []) == [TAG]
                    and float(old.get("view_rank") or 0) == float(row["rank"])
                    and old.get("view_key") == key
                    and all((old.get(field) or "") == want[field] for field in VIEW_METADATA)
                    and [a["description"] for a in sorted(old.get("annotations") or [], key=lambda a: a["entry"])]
                    == [n["description"] for n in notes] and not old.get("wait"))
            if same:
                continue
            changes["change"].append(want)
        else:
            changes["add"].append(want)
        payload.append(want)
    for old in existing:
        if old.get("status") not in ("pending", "waiting"):
            continue
        key = old.get("view_key") or ""
        if TAG not in (old.get("tags") or []):
            continue
        if key in rows or not judged(key, scopes):
            continue
        gone = {k: v for k, v in old.items() if k not in ("id", "urgency", "modified", "wait")}
        gone.update(status="deleted", end=tw_time(now))
        changes["delete"].append(gone)
        payload.append(gone)
    return payload, changes


def apply(payload):
    """Write one UTF-8 task import without surrogate escapes, hooks off."""
    if not payload:
        return
    result = subprocess.run([*TASK_CMD, *TASK_UDA, "rc.context=none", "rc.hooks=off", "rc.verbose=nothing",
                             "rc.confirmation=off", "import", "-"],
                            input=json.dumps(payload, ensure_ascii=False), capture_output=True,
                            text=True, encoding="utf-8", timeout=60, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"task import failed: {result.stderr.strip()}")


def write_state(summary):
    """Record the last run for whoever asks how fresh the view is."""
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        tmp = STATE_DIR / "last-run.json.tmp"
        tmp.write_text(json.dumps(summary, indent=2) + "\n")
        tmp.replace(STATE_DIR / "last-run.json")
    except OSError as error:
        warn(f"state file not written ({error}); imported context remains available and the next run retries")


def failed(error, now):
    """Report a run that could not refresh: 1 once the view is stale, else 0."""
    try:
        summary = json.loads((STATE_DIR / "last-run.json").read_text())
        value = summary.get("last_success_at") or (summary.get("at") if not summary.get("failures") else None)
        last = datetime.fromisoformat(value) if value else None
    except (OSError, ValueError, KeyError):
        last = None
    if last and now - last < STALE_VIEW:
        warn(f"{error}; the view rows stay as they were, last refreshed {last.isoformat()}, "
             "the next run retries")
        return 0
    since = f"since {last.isoformat()}" if last else "and has never refreshed"
    print(f"project-view: ERROR {error}; the view is stale {since}. Check the Linear key "
          f"(`{LINEAR_KEY_CMD}`), `gh auth status` and `task diagnostics`", file=sys.stderr)
    return 1


def previous_run():
    """Read refresh metadata without creating state or context files."""
    try:
        return json.loads((STATE_DIR / "last-run.json").read_text())
    except (OSError, ValueError):
        return {}


def active_rate_limit(previous, now):
    """Read a bounded throttle checkpoint without touching credentials or APIs."""
    records = [previous.get("linear_rate_limit")]
    try:
        records.append(json.loads((STATE_DIR / "linear-rate-limit.json").read_text()))
    except (OSError, ValueError):
        pass
    active = []
    for record in records:
        try:
            deadline = parse_time(record["retry_at"])
            observed = parse_time(record["observed_at"])
            if record["status"] == 429 and now < deadline <= now + RATE_MAX and observed.tzinfo:
                active.append({"status": 429, "observed_at": observed.isoformat(),
                               "retry_at": deadline.isoformat(), "headers": safe_rate_headers(record.get("headers"))})
        except (KeyError, TypeError, ValueError, AttributeError):
            pass
    return max(active, key=lambda r: r["retry_at"]) if active else None


def write_rate_limit(record):
    """Persist the first throttle immediately, even if later task writes fail."""
    temp = None
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=STATE_DIR,
                                         prefix=".linear-rate-limit-", delete=False) as handle:
            temp = Path(handle.name)
            handle.write(json.dumps(record) + "\n")
        os.replace(temp, STATE_DIR / "linear-rate-limit.json")
    except OSError:
        warn("Linear throttle checkpoint could not be written; this process still defers further reads")
    finally:
        if temp and temp.exists():
            temp.unlink()


def brief_text(task):
    """The newest generated brief, excluding the previous source-status footer."""
    notes = sorted(task.get("annotations") or [], key=lambda a: a.get("entry", ""), reverse=True)
    for note in notes:
        if note["description"].startswith("brief:"):
            return note["description"][6:].lstrip().partition(SOURCE_HEADING)[0]
    return None


def source_status(rows, scopes, existing, snapshot, github, now, previous):
    """Retain useful verified content when any source needed for it is missing."""
    checks = previous.get("sources") or {}
    project_checks = dict(checks.get("projects") or {})
    gh_check = checks.get("github")
    gh_project_checks = dict(checks.get("github_projects") or {})
    old_rows = {t.get("view_key"): t for t in existing}
    keys = {key for key in rows if key.startswith("standing:")}
    keys.update(key for key, task in old_rows.items() if key and key.startswith("standing:")
                and task.get("status") in ("pending", "waiting") and not judged(key, scopes))
    for key in sorted(keys):
        pid = key.split(":", 1)[1]
        old = old_rows.get(key) or {}
        unavailable = []
        if pid not in snapshot["projects"]:
            if snapshot.get("rate_limit"):
                unavailable.append("Linear project deferred until " + snapshot["rate_limit"]["retry_at"])
            else:
                unavailable.append("Linear project unavailable")
        if snapshot.get("assigned") is None:
            unavailable.append("Linear assigned issues unavailable")
        if snapshot.get("reference_failure") and not snapshot.get("reference_rate_limited"):
            unavailable.append("Linear handoff ownership unavailable")
        missing_refs = set()
        if github is None:
            unavailable.append("GitHub unavailable")
        else:
            project_refs = {ref for issue in snapshot["projects"].get(pid, {}).get("issues", [])
                            for ref in attached_refs(issue)}
            missing_refs = project_refs & set(github.get("unavailable_refs", ()))
            if missing_refs:
                unavailable.append("GitHub unavailable for " + ", ".join(sorted(missing_refs))
                                   + "; current PR states unknown")
        old_brief = brief_text(old)
        retained = bool(unavailable and (old_brief or key not in rows))
        if unavailable and old_brief:
            # A partial read cannot turn an old unknown into a new current fact.
            row = {"project": old.get("project", ""), "rank": RANK["standing"],
                   "description": old.get("description", "standing").split(" · source unavailable")[0],
                   "annotations": ["brief: " + old_brief]}
            row.update({field: old[field] for field in VIEW_METADATA if field in old})
            rows[key] = row
        elif key in rows:
            row = rows[key]
        else:
            # Legacy rows with no brief still keep their useful existing notes.
            detail = "\n\n".join(a["description"] for a in old.get("annotations") or [])
            row = {"project": old.get("project", ""), "rank": RANK["standing"],
                   "description": old.get("description", "standing").split(" · source unavailable")[0],
                   "annotations": ["brief: " + (detail or "Project context is unavailable.")]}
            row.update({field: old[field] for field in VIEW_METADATA if field in old})
            rows[key] = row
        # These stamps describe the content actually displayed. A later good
        # Linear read withheld during a GitHub outage cannot refresh old text.
        if retained:
            linear_snapshot = project_checks.get(pid)
            github_snapshot = gh_project_checks.get(pid, gh_check)
        else:
            linear_snapshot = now.isoformat() if pid in snapshot["projects"] else None
            github_snapshot = now.isoformat() if github is not None and not missing_refs else None
        if linear_snapshot:
            project_checks[pid] = linear_snapshot
        gh_project_checks[pid] = github_snapshot
        if unavailable:
            row.update(view_kind="project", view_state="source unavailable")
            status = ("; ".join(unavailable) + ". Prior context retained when available.\n"
                      + "Linear last verified: " + (linear_snapshot or "unknown") + ".\n"
                      + "GitHub last verified: " + (github_snapshot or "unknown") + ".\n"
                      + "These are source snapshot times. Current state may have changed; the existing timer retries.")
            row["description"] += " · source unavailable"
        else:
            status = (f"Linear last verified: {now.isoformat()}.\n"
                      f"GitHub last verified: {now.isoformat()}.\n"
                      "Expected refresh: every 10 minutes. If these source times stop advancing, treat the context as stale.")
        row["annotations"] = [a for a in row["annotations"] if not a.startswith("brief:")] + [
            "brief: " + next(a[6:].lstrip().partition(SOURCE_HEADING)[0]
                             for a in row["annotations"] if a.startswith("brief:")) + SOURCE_HEADING + status + "\n"]
    return {"projects": project_checks, "github_projects": gh_project_checks,
            "github": now.isoformat() if github is not None else gh_check}


def publish_contexts(rows, existing):
    """Atomically publish imported context; skip identical files for quiet rereads.

    Called only after the whole batched task import succeeded. An import failure
    leaves every prior file in place. A file error is retried on the next run.
    """
    identities = {t.get("view_key"): t["uuid"] for t in existing}
    for key, row in sorted(rows.items()):
        if not key.startswith("standing:"):
            continue
        text = next((a[6:].lstrip() for a in reversed(row["annotations"]) if a.startswith("brief:")), None)
        if text is None:
            continue
        text = text.rstrip() + "\n"
        uid = identities.get(key) or row_uuid(key)
        # Taskwarrior's UUID is the only path component supplied by source data.
        uuid.UUID(uid)
        path = BRIEFS_DIR / uid / "project-status.md"
        if any(parent.is_symlink() for parent in (path, *path.parents)):
            raise OSError(f"refusing a symlink in context path for {uid}")
        try:
            if path.read_text() == text:
                continue
        except FileNotFoundError:
            pass
        path.parent.mkdir(parents=True, exist_ok=True)
        temp_path = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                             prefix=".project-status-", delete=False) as handle:
                temp_path = Path(handle.name)
                handle.write(text)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temp_path, path)
        finally:
            if temp_path and temp_path.exists():
                temp_path.unlink()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--dry-run", action="store_true", help="read every source, write nothing")
    args = parser.parse_args(argv)
    now = datetime.now(UTC).replace(microsecond=0)
    previous = previous_run()
    try:
        # One export includes all live tasks and historical view rows, so identity
        # and association updates use the same local snapshot.
        tasks = task_json("(", "status:pending", "or", "status:waiting", "or", f"+{TAG}", ")")
    except Exception as error:
        return 1 if args.dry_run else failed(error, now)
    existing = [t for t in tasks if TAG in (t.get("tags") or [])]
    live_tasks = [t for t in tasks if t.get("status") in ("pending", "waiting")]
    active_overviews = {t["view_key"].split(":", 1)[1] for t in existing
                        if t.get("status") in ("pending", "waiting")
                        and (t.get("view_key") or "").startswith("standing:")}
    rate_limit = active_rate_limit(previous, now)
    linear = None
    try:
        if rate_limit:
            raise LinearRateLimited(rate_limit)
        linear = Linear(linear_key(), on_rate_limit=None if args.dry_run else write_rate_limit)
        snapshot = read_linear(linear, live_tasks)
    except Exception as error:
        warn(f"Linear unavailable ({error}); preserving project contexts and associations")
        snapshot = {"projects": {}, "assigned": None,
                    "wanted": sorted(active_overviews),
                    "failures": [str(error) if isinstance(error, LinearRateLimited) else "Linear unavailable"]}
    rate_limit = (linear.rate_limit if linear else None) or rate_limit
    if rate_limit:
        snapshot["rate_limit"] = rate_limit
    if snapshot.get("reference_failure") or snapshot.get("assigned") is None:
        # Discovery is incomplete: an earlier task-linked project may still be
        # relevant even though this read could not rediscover its ownership.
        snapshot["wanted"] = sorted(set(snapshot["wanted"]) | active_overviews)
    refs = {ref for project in snapshot["projects"].values() for issue in project["issues"]
            for ref in attached_refs(issue)}
    failures = list(snapshot["failures"])
    unavailable_refs = set()
    try:
        if not snapshot["projects"] and snapshot["failures"]:
            raise RuntimeError("Linear project source unavailable")
        github = read_github(refs)
        unavailable_refs = set(github.get("unavailable_refs", ()))
        if unavailable_refs:
            reason = "GitHub attached PRs unavailable: " + ", ".join(sorted(unavailable_refs))
            failures.append(reason)
            warn(reason + "; only affected contexts and review rows retain prior evidence")
    except Exception as error:
        github = None
        failures.append("GitHub unavailable")
        warn(f"GitHub unreadable ({error}); preserving verified context and associations")
    associations, live_tasks = association_plan(snapshot, live_tasks, github is not None, unavailable_refs)
    rows, scopes = build_rows(snapshot, live_tasks, github, now)
    sources = source_status(rows, scopes, existing, snapshot, github, now, previous)
    payload, changes = plan(rows, scopes, existing, now)
    if args.dry_run:
        for kind in ("add", "change", "delete"):
            for row in changes[kind]:
                print(f"{kind:6} {row.get('project', '')}: {row.get('description', '')}")
        for task in associations:
            group = task.get("view_project")
            print(f"group  {task['uuid']}: {group if group and group != UNASSIGNED else 'unassigned'}")
        print(f"project-view: dry run, {len(rows)} rows, {len(payload) + len(associations)} writes skipped")
        return 0
    try:
        apply(payload)
        association_result = apply_associations(associations)
        publish_contexts(rows, existing)
    except Exception as error:
        return failed(error, now)
    summary = {"at": now.isoformat(), "rows": len(rows), "added": len(changes["add"]),
               "changed": len(changes["change"]), "deleted": len(changes["delete"]),
               "associations": association_result["changed"], "associations_skipped": association_result["skipped"],
               "failures": failures, "sources": sources,
               "unavailable_refs": sorted(unavailable_refs), "linear_rate_limit": rate_limit,
               "linear_requests": linear.request_count if linear else 0}
    summary["last_success_at"] = (previous.get("last_success_at")
                                  or (previous.get("at") if not previous.get("failures") else None)) if failures else now.isoformat()
    write_state(summary)
    print(f"project-view: {len(rows)} rows, {summary['added']} added, {summary['changed']} changed, "
          f"{summary['deleted']} deleted, {summary['associations']} associations changed, "
          f"{summary['associations_skipped']} skipped after local edits"
          + (f", {len(failures)} sources failed" if failures else ""))
    return failed(RuntimeError("; ".join(failures)), now) if failures else 0


if __name__ == "__main__":
    sys.exit(main())
