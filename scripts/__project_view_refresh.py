#!/usr/bin/env python3
"""Keep the +view rows of the taskwarrior-tui `myprojects` report live.

The report (key 2 in taskwarrior-tui) lists Piotr's own Linear-linked tasks
grouped by project. Under each project's tasks it shows the rows this script
writes from Linear and GitHub:

  no task     an open issue assigned to Piotr that no open task carries (Linear
              Triage issues never sync, so these are mostly his Triage inbox)
  review ask  an open PR, attached to one of the project's open issues, that
              asks Piotr or one of his teams for review
  standing    where the project is: state, target, last update, open issues by
              state, what is stuck (blocked, stalled, triage), what changed in
              7 days, his own PRs. Its annotation (b brief) lists the issues.

WHY: on 11 Nov Piotr asked for a per-project view for him alone, continuous and
tactical. Linear project updates are weekly snapshots written for everyone.

View rows are ordinary tasks tagged +view, one fixed uuid per row key (stored in
the view_key UDA), so a rerun rewrites them in place and only real changes reach
the task database. They carry no +work, so every work-context report hides
them; no +piotr, so they never reach the handoff board; no linear_issue_id, so
the issue sync and issue prep never adopt them; and no github.com/<o>/<r>/pull/N
URL, so the PR movement watcher (__pr_movement_nudge.sh) never starts watching a
PR because of them. Writes go through one `task import` with hooks off, so the
intake records and the other hooks never see them. A row Piotr marks done comes
back on the next run while its source still holds: these rows mirror Linear and
GitHub and are changed there.

A source that fails leaves the rows it feeds as they were: a project whose
issues cannot be read keeps its rows, a failed assigned-issue read keeps the
no-task rows, and a failed GitHub read keeps the review asks and says "PRs
unavailable" on the standing row.

Usage: __project_view_refresh.py [--dry-run]
Runs from project-view.timer every 10 minutes. --dry-run reads every source and
prints the rows it would add, change and delete, writing nothing.

Env: PROJECT_VIEW_TASK_CMD (task), PROJECT_VIEW_GH_CMD (gh), LINEAR_API_KEY or
PROJECT_VIEW_LINEAR_KEY_CMD (pass show work/LINEAR_API_KEY),
PROJECT_VIEW_LINEAR_URL, PROJECT_VIEW_STATE (~/.local/state/project-view).
"""
import argparse
import importlib.util
import json
import os
import re
import shlex
import subprocess
import sys
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from pathlib import Path

TASK_CMD = shlex.split(os.environ.get("PROJECT_VIEW_TASK_CMD") or "task")
GH_CMD = shlex.split(os.environ.get("PROJECT_VIEW_GH_CMD") or "gh")
LINEAR_URL = os.environ.get("PROJECT_VIEW_LINEAR_URL", "https://api.linear.app/graphql")
LINEAR_KEY_CMD = os.environ.get("PROJECT_VIEW_LINEAR_KEY_CMD", "pass show work/LINEAR_API_KEY")
STATE_DIR = Path(os.environ.get("PROJECT_VIEW_STATE") or Path.home() / ".local/state/project-view")

TAG = "view"
NAMESPACE = uuid.UUID("5d1f3c2e-7a4b-4c8e-9f60-2b7e1d3a9c41")
RANK = {"issue": 1, "ask": 2, "standing": 9}
DONE = {"completed", "canceled", "duplicate"}
WINDOW = timedelta(days=7)
# A member-only project with no work of Piotr's shows only while it is alive:
# a status update or an issue change inside this window.
MEMBER_ALIVE = timedelta(days=30)
# Past this age a status update reads as a month, not a day count.
STALE_UPDATE = timedelta(days=60)
# A failed run fails the unit only once the view is this stale, so a short
# Linear, GitHub or network outage logs a WARN instead of a failure record.
STALE_VIEW = timedelta(hours=1)
PAGES = 10
GH_CHUNK = 25
# The issue sync files a project-less issue under its team's project
# (TEAM_PREFIX_PROJECT in __github_issue_sync.sh); a no-task row follows suit.
TEAM_PROJECT = {"DOC": "docs-maintenance", "DEVOPS": "operations", "ENGAI": "ai"}
HEALTH = {"onTrack": "on track", "atRisk": "at risk", "offTrack": "off track"}
# My PR states, most actionable first.
PR_NOTES = ("changes requested", "approved", "awaiting review", "draft")
PR_URL = re.compile(r"https?://github\.com/([\w.-]+)/([\w.-]+)/pull/(\d+)")
LINK = re.compile(r"(?:https?://|www\.)\S+")

PROJECT_FIELDS = """id name url targetDate startDate status { name type }
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
    issues(first: 50, after: $after, filter: {or: [
      {state: {type: {nin: ["completed", "canceled", "duplicate"]}}},
      {completedAt: {gte: "-P7D"}}, {canceledAt: {gte: "-P7D"}}]}) {
      pageInfo { hasNextPage endCursor }
      nodes { identifier title url updatedAt completedAt canceledAt
              state { name type } assignee { name isMe }
              attachments(first: 20) { nodes { url } }
              inverseRelations(first: 20) { nodes { type issue { identifier state { type } } } } } } }
}""".replace("FIELDS", PROJECT_FIELDS)


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
    match = PR_URL.match(url or "")
    return f"{match[1]}/{match[2]}#{match[3]}".lower() if match else None


def short_ref(ref):
    """repo#n from owner/repo#n."""
    return ref.split("/", 1)[1]


def row_uuid(key):
    """The fixed uuid of a view row."""
    return str(uuid.uuid5(NAMESPACE, key))


# Sources ---------------------------------------------------------------------

class Linear:
    """A small Linear GraphQL client that reads its key once."""

    def __init__(self, key):
        self.key = key

    def query(self, text, variables=None):
        body = json.dumps({"query": text, "variables": variables or {}}).encode()
        request = urllib.request.Request(LINEAR_URL, data=body, headers={
            "Authorization": self.key, "Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=30) as response:
            reply = json.load(response)
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


def read_project(linear, project_id):
    """One project's fields and its open and recently closed issues."""
    issues, fields = [], None
    after = None
    for _ in range(PAGES):
        data = linear.query(Q_PROJECT, {"id": project_id, "after": after})["project"]
        fields = fields or {k: v for k, v in data.items() if k != "issues"}
        issues.extend(data["issues"]["nodes"])
        if not data["issues"]["pageInfo"]["hasNextPage"]:
            return {**fields, "issues": issues}
        after = data["issues"]["pageInfo"]["endCursor"]
    raise RuntimeError(f"more than {PAGES} pages of issues")


def read_linear(linear):
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
    return {"projects": projects, "assigned": assigned, "wanted": sorted(wanted), "failures": failures}


def gh_graphql(query):
    """Run one gh GraphQL query; partial data from a failed call still counts."""
    result = subprocess.run([*GH_CMD, "api", "graphql", "-f", f"query={query}"],
                            capture_output=True, text=True, timeout=60, check=False)
    try:
        reply = json.loads(result.stdout or "{}")
    except json.JSONDecodeError:
        reply = {}
    if not reply.get("data"):
        raise RuntimeError((result.stderr or "gh api graphql failed").strip().splitlines()[-1])
    return reply["data"]


def read_github(refs):
    """Piotr's open PRs, his teams, and the state of every attached PR in refs."""
    viewer = gh_graphql("query { viewer { login pullRequests(states: OPEN, first: 100) "
                        "{ nodes { url isDraft reviewDecision } } } }")["viewer"]
    login = viewer["login"]
    mine = {pr_ref(n["url"]): n for n in viewer["pullRequests"]["nodes"] if pr_ref(n["url"])}
    owners = sorted({ref.split("/", 1)[0] for ref in refs})
    teams = set()
    if owners:
        fields = " ".join(
            f'o{i}: organization(login: {json.dumps(owner)}) '
            f'{{ login teams(first: 100, userLogins: [{json.dumps(login)}]) {{ nodes {{ slug }} }} }}'
            for i, owner in enumerate(owners))
        for org in gh_graphql(f"query {{ {fields} }}").values():
            if org:
                teams.update(f"{org['login'].lower()}/{t['slug']}" for t in org["teams"]["nodes"])
    prs = {}
    wanted = sorted(refs)
    for start in range(0, len(wanted), GH_CHUNK):
        chunk = wanted[start:start + GH_CHUNK]
        fields = []
        for i, ref in enumerate(chunk):
            repo, number = ref.split("#")
            owner, name = repo.split("/")
            fields.append(
                f'p{i}: repository(owner: {json.dumps(owner)}, name: {json.dumps(name)}) '
                f'{{ pullRequest(number: {number}) {{ url state isDraft reviewDecision title '
                f'author {{ login }} reviewRequests(first: 20) {{ nodes {{ requestedReviewer '
                f'{{ __typename ... on User {{ login }} ... on Team {{ slug organization {{ login }} }} }} }} }} }} }}')
        data = gh_graphql("query { " + " ".join(fields) + " }")
        for i, ref in enumerate(chunk):
            pr = (data.get(f"p{i}") or {}).get("pullRequest")
            if pr:
                prs[ref] = pr
    return {"login": login, "mine": mine, "teams": teams, "prs": prs}


def task_json(*args):
    """Export tasks through Taskwarrior with no context and no hooks."""
    result = subprocess.run([*TASK_CMD, "rc.context=none", "rc.hooks=off", "rc.verbose=nothing",
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


def standing(project, tasks, github, now):
    """The standing row's one-line description and its detail annotation."""
    issues = project["issues"]
    open_ = [i for i in issues if i["state"]["type"] not in DONE]
    closed = [i for i in issues if i["state"]["type"] in DONE
              and (parse_time(i.get("completedAt")) or parse_time(i.get("canceledAt")) or now - 2 * WINDOW) >= now - WINDOW]
    changed = [i for i in open_ if parse_time(i["updatedAt"]) >= now - WINDOW]
    stalled = [i for i in open_ if bucket(i) == "started" and parse_time(i["updatedAt"]) < now - WINDOW]
    blocked = []
    for issue in open_:
        blockers = [r["issue"]["identifier"] for r in issue["inverseRelations"]["nodes"]
                    if r["type"] == "blocks" and r["issue"]["state"]["type"] not in DONE]
        if blockers:
            blocked.append((issue, blockers))
    counts = {}
    for issue in open_:
        counts[bucket(issue)] = counts.get(bucket(issue), 0) + 1
    order = ("started", "todo", "triage", "backlog", "parked")

    target = parse_time(project.get("targetDate") and project["targetDate"] + "T00:00:00+00:00")
    state = project["status"]["name"]
    if target:
        state += f", target {day(target, now)}" + (" passed" if target.date() < now.date() else "")
    updates = project["projectUpdates"]["nodes"]
    if updates:
        update = updates[0]
        when = parse_time(update["createdAt"])
        health = HEALTH.get(update.get("health"), update.get("health") or "no health")
        if now - when <= STALE_UPDATE:
            update_line = f"{health}, updated {ago(when, now)}"
        else:
            update_line = f"{health}, last update {when.strftime('%b')} {when.year}"
    else:
        update_line = "no update yet"
    summary = f"{len(open_)} open"
    if open_:
        summary += ": " + ", ".join(f"{counts[k]} {k}" for k in order if counts.get(k))
    # What needs Piotr leads and the slow facts trail: a 190-column tui pane
    # shows about 60 characters of the description.
    attention = []
    if counts.get("triage"):
        attention.append(f"{counts['triage']} in triage")
    stuck = [f"{n} {label}" for n, label in ((len(blocked), "blocked"), (len(stalled), "stalled")) if n]
    if stuck:
        attention.append("stuck: " + ", ".join(stuck))

    refs = {}
    for issue in open_:
        for ref in attached_refs(issue):
            refs.setdefault(ref, []).append(issue["identifier"])
    mine_lines, other_lines, mine_counts = [], [], {}
    if github is None:
        attention.append("PRs unavailable")
    else:
        for ref, ids in sorted(refs.items()):
            if ref in github["mine"]:
                note = pr_note(github["mine"][ref])
                mine_counts[note] = mine_counts.get(note, 0) + 1
                mine_lines.append(f"{short_ref(ref)} {note} ({', '.join(ids)})")
                continue
            pr = github["prs"].get(ref)
            if pr and pr["state"] == "OPEN":
                other_lines.append(f"{short_ref(ref)} {pr['author']['login'] if pr.get('author') else 'ghost'}, "
                                   f"{pr_note(pr)} ({', '.join(ids)})")
        if mine_counts:
            attention.append("my PRs: " + ", ".join(f"{mine_counts[note]} {note}" for note in PR_NOTES
                                                    if mine_counts.get(note)))
    parts = ["standing", *attention, update_line]
    if changed or closed:
        parts.append(f"7d: {len(changed)} changed, {len(closed)} closed")
    parts += [summary, state]
    handoffs = [t for t in tasks if "piotr" in (t.get("tags") or [])]
    # The report leaves +backlog tasks out, as byproject does; count them here.
    backlog = [t for t in tasks if "backlog" in (t.get("tags") or []) and t not in handoffs]
    if backlog:
        parts.append(f"my backlog: {len(backlog)}")
    if handoffs:
        parts.append(f"{len(handoffs)} handoff" + ("s" if len(handoffs) > 1 else ""))

    def names(rows, extra=lambda i: ""):
        return ", ".join(f"{i['identifier']} {(i.get('assignee') or {}).get('name', 'unassigned')}{extra(i)}"
                         for i in rows) or "none"

    lead = (project.get("lead") or {}).get("name", "no lead")
    start = parse_time(project.get("startDate") and project["startDate"] + "T00:00:00+00:00")
    lines = [
        (f"standing of {project['name']}: lead {lead}, {project['status']['name']}, "
         f"start {day(start) + ' ' + str(start.year) if start else 'none'}, "
         f"target {day(target) + ' ' + str(target.year) if target else 'none'}"),
        ("last update: " + (f"{day(when)} {when.year} by {(updates[0].get('user') or {}).get('name', 'unknown')}, {health}"
                            if updates else "none")),
        f"open {len(open_)}: " + (", ".join(f"{k} {counts[k]}" for k in order if counts.get(k)) or "none"),
        "started: " + names([i for i in open_ if bucket(i) == "started"]),
        "triage: " + names([i for i in open_ if bucket(i) == "triage"],
                           lambda i: f" ({clean(i['title'], 50)})"),
        "blocked: " + (", ".join(f"{i['identifier']} by {', '.join(b)}" for i, b in blocked) or "none"),
        "stalled 7d+: " + names(stalled, lambda i: f" ({(now - parse_time(i['updatedAt'])).days}d)"),
        "closed in 7d: " + (", ".join(i["identifier"] for i in closed) or "none"),
        "changed in 7d: " + (", ".join(i["identifier"] for i in changed) or "none"),
    ]
    if github is None:
        lines.append("PRs: GitHub unavailable on the last run")
    else:
        lines.append("my PRs: " + ("; ".join(mine_lines) or "none"))
        lines.append("other open PRs: " + ("; ".join(other_lines) or "none"))
    if backlog:
        lines.append("my backlog: " + ", ".join(sorted(t.get("linear_issue_id") or clean(t["description"], 50)
                                                      for t in backlog)))
    if handoffs:
        lines.append("handoffs: " + "; ".join(t.get("linear_issue_id") or clean(t["description"], 50) for t in handoffs))
    return " · ".join(parts), "\n".join(lines)


def build_rows(snapshot, tasks, github, now):
    """Every view row the sources call for, keyed by view_key.

    Returns (rows, scopes): scopes names what this run could judge, so a row
    outside it is kept rather than deleted.
    """
    live = [t for t in tasks if TAG not in (t.get("tags") or [])]
    tracked = {t["linear_issue_id"] for t in live if t.get("linear_issue_id")}
    by_project = {}
    for task in live:
        by_project.setdefault(task.get("project") or "", []).append(task)
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
            "annotations": [issue["url"]],
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
        rows[f"standing:{pid}"] = {
            "project": name, "rank": RANK["standing"], "description": description,
            "annotations": [project["url"], detail],
        }
        if github is None:
            continue
        seen = set()
        for issue in project["issues"]:
            if issue["state"]["type"] in DONE:
                continue
            for ref in attached_refs(issue):
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
                    "description": f"review ask · {short_ref(ref)} · {author} · {clean(pr['title'], 60)} "
                                   f"({issue['identifier']}){suffix}",
                    # /issues/N redirects to the PR on GitHub, and the PR
                    # movement watcher only reads /pull/N links (see module doc).
                    "annotations": [f"https://github.com/{owner_repo}/issues/{number}"],
                }

    scopes = {
        "assigned": assigned is not None,
        "github": github is not None,
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
        pid = rest.split(":", 1)[0]
        return scopes["github"] and (pid in scopes["projects"] or pid not in scopes["wanted"])
    return True


def plan(rows, scopes, existing, now):
    """The task import payload that turns the existing view rows into rows.

    Unchanged rows are left out, an annotation whose text did not change keeps
    its entry stamp, and a row no source calls for is deleted only when this run
    could judge it.
    """
    by_uuid = {t["uuid"]: t for t in existing}
    payload, changes = [], {"add": [], "change": [], "delete": []}
    for key, row in sorted(rows.items()):
        uid = row_uuid(key)
        old = by_uuid.get(uid)
        old_notes = {a["description"]: a["entry"] for a in (old or {}).get("annotations") or []}
        notes = []
        for offset, text in enumerate(row["annotations"]):
            notes.append({"entry": old_notes.get(text) or tw_time(now + timedelta(seconds=offset)),
                          "description": text})
        want = {"uuid": uid, "status": "pending", "description": row["description"],
                "project": row["project"], "tags": [TAG], "view_rank": row["rank"],
                "view_key": key, "annotations": notes}
        if old:
            want["entry"] = old["entry"]
            same = (old.get("status") == "pending" and old.get("description") == want["description"]
                    and old.get("project") == want["project"] and sorted(old.get("tags") or []) == [TAG]
                    and float(old.get("view_rank") or 0) == float(row["rank"])
                    and old.get("view_key") == key
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
        if key in rows or not judged(key, scopes):
            continue
        gone = {k: v for k, v in old.items() if k not in ("id", "urgency", "modified", "wait")}
        gone.update(status="deleted", end=tw_time(now))
        changes["delete"].append(gone)
        payload.append(gone)
    return payload, changes


def apply(payload):
    """Write the payload with one task import, hooks off."""
    if not payload:
        return
    result = subprocess.run([*TASK_CMD, "rc.context=none", "rc.hooks=off", "rc.verbose=nothing",
                             "rc.confirmation=off", "import", "-"],
                            input=json.dumps(payload), capture_output=True, text=True, timeout=60, check=False)
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
        warn(f"state file not written ({error}); the rows are still current")


def failed(error, now):
    """Report a run that could not refresh: 1 once the view is stale, else 0."""
    try:
        last = datetime.fromisoformat(json.loads((STATE_DIR / "last-run.json").read_text())["at"])
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


def add_ci_status(rows, scopes, tasks, read_only=False):
    """Update the CI standing row, or leave it untouched on failed inputs."""
    # Preserve the existing CI row when its evidence or model is unavailable.
    ci_keys = [key for key, row in rows.items()
               if key.startswith("standing:") and row["project"] == "ci-infrastructure-improvements"]
    for key in ci_keys:
        try:
            spec = importlib.util.spec_from_file_location("ci_status", Path(__file__).with_name("__ci_project_status.py"))
            ci = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(ci)
            data = json.loads(ci.PAGE.read_text())
            status, handoff_titles = ci.generate(data, tasks, read_only=read_only)
            rows[key]["description"] = status["description"]
            rows[key]["annotations"] = ["brief: " + ci.format_brief(status, handoff_titles)]
        except Exception as error:
            warn(f"CI status unavailable ({error}); keeping its existing row")
            rows.pop(key)
            scopes["projects"].discard(key.split(":", 1)[1])

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--dry-run", action="store_true", help="read every source, write nothing")
    args = parser.parse_args(argv)
    now = datetime.now(UTC).replace(microsecond=0)
    try:
        snapshot = read_linear(Linear(linear_key()))
        tasks = task_json("(", "status:pending", "or", "status:waiting", ")")
        existing = task_json(f"+{TAG}")
    except Exception as error:  # noqa: BLE001 - nothing can be judged without these
        return 1 if args.dry_run else failed(error, now)
    refs = set()
    for project in snapshot["projects"].values():
        for issue in project["issues"]:
            if issue["state"]["type"] not in DONE:
                refs.update(attached_refs(issue))
    failures = list(snapshot["failures"])
    try:
        github = read_github(refs)
    except Exception as error:  # noqa: BLE001 - PR facts are optional for the view
        github = None
        failures.append(f"github: {error}")
        warn(f"GitHub unreadable ({error}); review asks stay as they were and standing says PRs unavailable")
    rows, scopes = build_rows(snapshot, tasks, github, now)
    add_ci_status(rows, scopes, tasks, read_only=args.dry_run)
    payload, changes = plan(rows, scopes, existing, now)
    if args.dry_run:
        for kind in ("add", "change", "delete"):
            for row in changes[kind]:
                print(f"{kind:6} {row.get('project', '')}: {row.get('description', '')}")
        print(f"project-view: dry run, {len(rows)} rows, {len(payload)} writes skipped")
        return 0
    try:
        apply(payload)
    except Exception as error:  # noqa: BLE001
        return failed(error, now)
    summary = {"at": now.isoformat(), "rows": len(rows), "added": len(changes["add"]),
               "changed": len(changes["change"]), "deleted": len(changes["delete"]), "failures": failures}
    write_state(summary)
    print(f"project-view: {len(rows)} rows, {summary['added']} added, {summary['changed']} changed, "
          f"{summary['deleted']} deleted" + (f", {len(failures)} sources failed" if failures else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
