"""Tests for __project_view_refresh.py, the +view rows of the myprojects report."""

import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("project_view", REPO / "scripts/__project_view_refresh.py")
pv = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pv)

NOW = datetime(2026, 11, 11, 12, 0, tzinfo=UTC)


def stamp(days_ago):
    return (NOW - timedelta(days=days_ago)).isoformat().replace("+00:00", "Z")


def issue(ident, state="Todo", kind="unstarted", assignee="Someone", me=False, updated=1,
          prs=(), blockers=(), completed=None, title="A title"):
    return {
        "identifier": ident, "title": title, "url": f"https://linear.app/loft/issue/{ident.lower()}",
        "updatedAt": stamp(updated), "completedAt": stamp(completed) if completed is not None else None,
        "canceledAt": None, "state": {"name": state, "type": kind},
        "assignee": {"name": assignee, "isMe": me} if assignee else None,
        "attachments": {"nodes": [{"url": u} for u in prs]},
        "inverseRelations": {"nodes": [{"type": "blocks", "issue": {"identifier": b, "state": {"type": t}}}
                                       for b, t in blockers]},
    }


def project(pid, name, issues, led=True, listed=True, update_days=0, health="onTrack", target=None,
            status="In Progress"):
    updates = [] if update_days is None else [
        {"createdAt": stamp(update_days), "health": health, "user": {"name": "Piotr Zaniewski"}}]
    return {
        "id": pid, "name": name, "url": f"https://linear.app/loft/project/{pid}",
        "targetDate": target, "startDate": "2026-11-03", "status": {"name": status, "type": "started"},
        "lead": {"name": "Piotr Zaniewski" if led else "Caue Santos", "isMe": led},
        "projectUpdates": {"nodes": updates}, "issues": issues, "listed": listed, "led": led,
    }


def assigned(ident, project_name=None, pid=None, state="Triage", kind="triage", title="Inbox item"):
    return {"identifier": ident, "title": title, "url": f"https://linear.app/loft/issue/{ident.lower()}",
            "state": {"name": state, "type": kind},
            "project": {"id": pid, "name": project_name} if project_name else None}


def github(mine=None, prs=None, teams=("loft-sh/eng-devops",)):
    return {"login": "Piotr1215", "mine": mine or {}, "teams": set(teams), "prs": prs or {}}


def other_pr(ref, author="vcauesantos", state="OPEN", draft=False, request=("Team", "eng-devops")):
    owner = ref.split("/", 1)[0]
    kind, who = request
    node = ({"__typename": "Team", "slug": who, "organization": {"login": owner}} if kind == "Team"
            else {"__typename": "User", "login": who})
    return {"url": f"https://github.com/{ref.replace('#', '/pull/')}", "state": state, "isDraft": draft,
            "reviewDecision": "REVIEW_REQUIRED", "title": "fix(ci): pick release versions",
            "author": {"login": author}, "reviewRequests": {"nodes": [{"requestedReviewer": node}]}}


def snapshot(projects, assigned_issues=()):
    return {"projects": {p["id"]: p for p in projects},
            "assigned": list(assigned_issues) if assigned_issues is not None else None,
            "wanted": [p["id"] for p in projects], "failures": []}


class NamingTests(unittest.TestCase):
    def test_kebab_matches_the_issue_sync_project_names(self):
        self.assertEqual(pv.kebab("Issue to PR Agentic Pipeline"), "issue-to-pr-agentic-pipeline")
        self.assertEqual(pv.kebab("CI infrastructure improvements"), "ci-infrastructure-improvements")
        self.assertEqual(pv.kebab("Brand: vCluster Brand Skills for AI Tools"),
                         "brand-vcluster-brand-skills-for-ai-tools")

    def test_row_uuid_is_stable_per_key(self):
        self.assertEqual(pv.row_uuid("issue:DEVOPS-1"), pv.row_uuid("issue:DEVOPS-1"))
        self.assertNotEqual(pv.row_uuid("issue:DEVOPS-1"), pv.row_uuid("issue:DEVOPS-2"))


class NoTaskRowTests(unittest.TestCase):
    def test_assigned_issue_without_a_task_shows_under_its_project(self):
        snap = snapshot([], [assigned("ENGAI-138", "AI Maintenance", "p1"),
                             assigned("DEVOPS-1838", "LoftRocks Maintenance", "p2")])
        rows, _ = pv.build_rows(snap, [], github(), NOW)
        self.assertEqual(rows["issue:ENGAI-138"]["project"], "ai-maintenance")
        self.assertEqual(rows["issue:DEVOPS-1838"]["project"], "loftrocks-maintenance")
        self.assertTrue(rows["issue:ENGAI-138"]["description"].startswith("no task · ENGAI-138 Triage · "))
        self.assertEqual(rows["issue:ENGAI-138"]["annotations"], ["https://linear.app/loft/issue/engai-138"])
        self.assertEqual(rows["issue:ENGAI-138"]["rank"], 1)

    def test_any_open_task_with_the_issue_id_suppresses_the_row(self):
        snap = snapshot([], [assigned("DEVOPS-1828", "Cloud Infrastructure Maintenance", "p1", "Todo", "unstarted"),
                             assigned("DEVOPS-1872", "CI infrastructure improvements", "p2", "Todo", "unstarted")])
        tasks = [{"uuid": "a", "linear_issue_id": "DEVOPS-1828", "tags": ["piotr"], "status": "pending"},
                 {"uuid": "b", "linear_issue_id": "DEVOPS-1872", "tags": ["work"], "status": "waiting"}]
        rows, _ = pv.build_rows(snap, tasks, github(), NOW)
        self.assertNotIn("issue:DEVOPS-1828", rows)
        self.assertNotIn("issue:DEVOPS-1872", rows)

    def test_a_view_row_never_counts_as_the_issue_task(self):
        snap = snapshot([], [assigned("ENGAI-138", "AI Maintenance", "p1")])
        tasks = [{"uuid": "v", "linear_issue_id": "ENGAI-138", "tags": ["view"], "status": "pending"}]
        rows, _ = pv.build_rows(snap, tasks, github(), NOW)
        self.assertIn("issue:ENGAI-138", rows)

    def test_project_less_issue_follows_the_team_project(self):
        snap = snapshot([], [assigned("ENGAI-139"), assigned("REV-1")])
        rows, _ = pv.build_rows(snap, [], github(), NOW)
        self.assertEqual(rows["issue:ENGAI-139"]["project"], "ai")
        self.assertEqual(rows["issue:REV-1"]["project"], "no-project")

    def test_links_in_titles_never_reach_the_row(self):
        snap = snapshot([], [assigned("DEVOPS-1879", "Prod", "p1",
                                      title="helper fails when https://ip-api.com/json answers 403")])
        rows, _ = pv.build_rows(snap, [], github(), NOW)
        self.assertNotIn("http", rows["issue:DEVOPS-1879"]["description"])


class StandingTests(unittest.TestCase):
    def row(self, proj, tasks=(), gh=None, assigned_issues=()):
        rows, _ = pv.build_rows(snapshot([proj], assigned_issues), list(tasks),
                                github() if gh is None else gh, NOW)
        return rows.get(f"standing:{proj['id']}")

    def test_standing_summarises_state_update_and_open_issues(self):
        proj = project("p1", "CI infrastructure improvements", [
            issue("DEVOPS-1", "In Progress", "started", "Piotr Zaniewski", True),
            issue("DEVOPS-2", "In Review", "started"),
            issue("DEVOPS-3", "Todo"), issue("DEVOPS-4", "Triage", "triage", None),
            issue("DEVOPS-5", "Backlog", "backlog"), issue("DEVOPS-6", "Parked", "started"),
            issue("DEVOPS-7", "Released", "completed", completed=2),
        ], update_days=0, target="2026-12-08")
        row = self.row(proj)
        self.assertEqual(row["project"], "ci-infrastructure-improvements")
        self.assertEqual(row["rank"], 9)
        self.assertEqual(row["description"],
                         "standing · In Progress, target 8 Dec · updated today, on track · "
                         "6 open: 2 started, 1 todo, 1 triage, 1 backlog, 1 parked · 7d: 6 changed, 1 closed")
        self.assertEqual(row["annotations"][0], "https://linear.app/loft/project/p1")

    def test_stuck_counts_blocked_and_stalled_but_not_parked(self):
        proj = project("p1", "Self-hosted ai stack", [
            issue("DEVOPS-1580", blockers=[("DEVOPS-1579", "unstarted")]),
            issue("DEVOPS-1581", blockers=[("DEVOPS-1500", "completed")]),
            issue("DEVOPS-1105", "In Progress", "started", updated=12),
            issue("DEVOPS-1809", "Parked", "started", updated=30),
        ], led=False, update_days=7, health="offTrack", target="2027-06-30")
        row = self.row(proj)
        self.assertIn("target 30 Jun 2027 ·", row["description"])
        self.assertIn("updated 7d ago, off track", row["description"])
        self.assertIn("stuck: 1 blocked, 1 stalled", row["description"])
        detail = row["annotations"][1]
        self.assertIn("blocked: DEVOPS-1580 by DEVOPS-1579", detail)
        self.assertIn("stalled 7d+: DEVOPS-1105 Someone (12d)", detail)

    def test_old_and_missing_updates_and_a_passed_target(self):
        proj = project("p1", "Prod release", [issue("DEVOPS-1")], update_days=126, target="2026-03-31")
        self.assertIn("target 31 Mar passed · last update Jul 2026, on track", self.row(proj)["description"])
        proj = project("p2", "AI Maintenance", [issue("DEVOPS-2")], update_days=None, status="Maintenance")
        self.assertIn("standing · Maintenance · no update yet ·", self.row(proj)["description"])

    def test_my_prs_and_handoffs_count_on_the_row(self):
        mine = "loft-sh/loft-enterprise#9403"
        proj = project("p1", "CI infrastructure improvements", [
            issue("DEVOPS-1872", "In Progress", "started", prs=[f"https://github.com/{mine.replace('#', '/pull/')}"])])
        gh = github(mine={mine: {"isDraft": False, "reviewDecision": "REVIEW_REQUIRED"}})
        tasks = [{"uuid": "h", "project": "ci-infrastructure-improvements", "tags": ["piotr"],
                  "linear_issue_id": "DEVOPS-1828", "description": "click Approve", "status": "pending"}]
        row = self.row(proj, tasks, gh)
        self.assertTrue(row["description"].endswith("· my PRs: 1 awaiting review · 1 handoff"))
        self.assertIn("my PRs: loft-enterprise#9403 awaiting review (DEVOPS-1872)", row["annotations"][1])
        self.assertIn("handoffs: DEVOPS-1828", row["annotations"][1])

    def test_backlog_tasks_are_counted_and_listed_on_the_row(self):
        proj = project("p1", "AI Maintenance", [issue("DEVOPS-1818", "Backlog", "backlog")])
        tasks = [{"uuid": f"b{n}", "project": "ai-maintenance", "tags": ["backlog", "work"],
                  "linear_issue_id": ident, "description": "later", "status": "pending"}
                 for n, ident in enumerate(("DEVOPS-1818", "DEVOPS-1306"))]
        row = self.row(proj, tasks)
        self.assertTrue(row["description"].endswith("· my backlog: 2"))
        self.assertIn("my backlog: DEVOPS-1306, DEVOPS-1818", row["annotations"][1])

    def test_github_down_says_prs_unavailable(self):
        proj = project("p1", "CI infrastructure improvements", [issue("DEVOPS-1")])
        rows, scopes = pv.build_rows(snapshot([proj]), [], None, NOW)
        self.assertIn("· PRs unavailable", rows["standing:p1"]["description"])
        self.assertFalse(scopes["github"])

    def test_member_projects_show_only_with_work_or_life(self):
        dead = project("p1", "Staging: Content Development", [issue("MAR-1", updated=40)], led=False, update_days=500)
        self.assertIsNone(self.row(dead))
        alive = project("p2", "Snyk replacement options", [issue("ENGSEC-7", updated=40)], led=False, update_days=5)
        self.assertIsNotNone(self.row(alive))
        busy = project("p3", "Release checklist automation", [issue("DEVOPS-1135", updated=2)], led=False,
                       update_days=500)
        self.assertIsNotNone(self.row(busy))
        mine = project("p4", "Prod release", [issue("DEVOPS-1879", updated=40)], led=False, update_days=500)
        self.assertIsNotNone(self.row(mine, assigned_issues=[assigned("DEVOPS-1879", "Prod release", "p4")]))
        led = project("p5", "vClusterCloud Maintenance", [issue("DEVOPS-1247", updated=90)], update_days=600)
        self.assertIsNotNone(self.row(led))


class ReviewAskTests(unittest.TestCase):
    def rows(self, prs, gh):
        proj = project("p1", "GitHub Asks", [issue("DEVOPS-1400", "In Review", "started", prs=prs)])
        rows, _ = pv.build_rows(snapshot([proj]), [], gh, NOW)
        return {k: v for k, v in rows.items() if k.startswith("ask:")}

    def test_team_request_on_an_attached_pr_is_an_ask(self):
        ref = "loft-sh/loft-enterprise#9373"
        asks = self.rows(["https://github.com/loft-sh/loft-enterprise/pull/9373"],
                         github(prs={ref: other_pr(ref)}))
        row = asks[f"ask:p1:{ref}"]
        self.assertEqual(row["project"], "github-asks")
        self.assertEqual(row["rank"], 2)
        self.assertTrue(row["description"].startswith("review ask · loft-enterprise#9373 · vcauesantos · "))
        self.assertTrue(row["description"].endswith("(DEVOPS-1400) · via eng-devops"))
        self.assertEqual(row["annotations"], ["https://github.com/loft-sh/loft-enterprise/issues/9373"])

    def test_direct_request_has_no_team_suffix(self):
        ref = "loft-sh/vcluster-docs#3111"
        asks = self.rows([f"https://github.com/{ref.replace('#', '/pull/')}"],
                         github(prs={ref: other_pr(ref, request=("User", "piotr1215"))}))
        self.assertTrue(asks[f"ask:p1:{ref}"]["description"].endswith("(DEVOPS-1400)"))

    def test_own_draft_closed_and_unrequested_prs_are_not_asks(self):
        refs = ["loft-sh/a#1", "loft-sh/b#2", "loft-sh/c#3", "loft-sh/d#4"]
        urls = [f"https://github.com/{r.replace('#', '/pull/')}" for r in refs]
        gh = github(mine={refs[0]: {"isDraft": False, "reviewDecision": None}},
                    prs={refs[1]: other_pr(refs[1], draft=True), refs[2]: other_pr(refs[2], state="MERGED"),
                         refs[3]: other_pr(refs[3], request=("Team", "eng-docs"))})
        self.assertEqual(self.rows(urls, gh), {})


class SafetyTests(unittest.TestCase):
    def test_rows_never_carry_work_piotr_linear_or_pull_links(self):
        ref = "loft-sh/loft-enterprise#9373"
        proj = project("p1", "GitHub Asks", [issue("DEVOPS-1400", "In Review", "started",
                                                   prs=["https://github.com/loft-sh/loft-enterprise/pull/9373"])])
        rows, scopes = pv.build_rows(snapshot([proj], [assigned("DEVOPS-1838", "LoftRocks", "p2")]), [],
                                     github(prs={ref: other_pr(ref)}), NOW)
        payload, _ = pv.plan(rows, scopes, [], NOW)
        self.assertEqual(len(payload), 3)
        for row in payload:
            self.assertEqual(row["tags"], ["view"])
            self.assertNotIn("linear_issue_id", row)
            text = json.dumps(row)
            self.assertNotRegex(text, r"github\.com/[^/]+/[^/]+/pull/\d+")


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.rows = {"issue:DEVOPS-1": {"project": "p", "rank": 1, "description": "no task · DEVOPS-1",
                                        "annotations": ["https://linear.app/loft/issue/devops-1"]},
                     "standing:p1": {"project": "p", "rank": 9, "description": "standing · v1",
                                     "annotations": ["https://linear.app/loft/project/p1", "detail v1"]}}
        self.scopes = {"assigned": True, "github": True, "projects": {"p1"}, "wanted": {"p1"}}

    def stored(self, payload):
        """What task export would return for imported rows."""
        return [{**row, "entry": row.get("entry", "20261101T000000Z")} for row in payload]

    def test_rerun_with_the_same_rows_writes_nothing(self):
        payload, _ = pv.plan(self.rows, self.scopes, [], NOW)
        again, changes = pv.plan(self.rows, self.scopes, self.stored(payload), NOW + timedelta(minutes=10))
        self.assertEqual(again, [])
        self.assertEqual(changes, {"add": [], "change": [], "delete": []})

    def test_a_change_keeps_the_entry_and_unchanged_annotation_stamps(self):
        first, _ = pv.plan(self.rows, self.scopes, [], NOW)
        stored = self.stored(first)
        self.rows["standing:p1"]["description"] = "standing · v2"
        self.rows["standing:p1"]["annotations"][1] = "detail v2"
        later = NOW + timedelta(hours=1)
        payload, changes = pv.plan(self.rows, self.scopes, stored, later)
        self.assertEqual(len(changes["change"]), 1)
        row = payload[0]
        old = next(r for r in stored if r["view_key"] == "standing:p1")
        self.assertEqual(row["entry"], old["entry"])
        self.assertEqual(row["annotations"][0]["entry"], old["annotations"][0]["entry"])
        self.assertEqual(row["annotations"][1]["entry"], pv.tw_time(later + timedelta(seconds=1)))

    def test_a_done_row_comes_back_while_its_source_holds(self):
        payload, _ = pv.plan(self.rows, self.scopes, [], NOW)
        stored = self.stored(payload)
        stored[0]["status"] = "completed"
        again, _ = pv.plan(self.rows, self.scopes, stored, NOW)
        self.assertEqual([r["status"] for r in again], ["pending"])

    def test_obsolete_rows_go_only_when_their_source_was_read(self):
        payload, _ = pv.plan(self.rows, self.scopes, [], NOW)
        stored = self.stored(payload)
        _, changes = pv.plan({}, self.scopes, stored, NOW)
        self.assertEqual(sorted(r["view_key"] for r in changes["delete"]), ["issue:DEVOPS-1", "standing:p1"])
        self.assertTrue(all(r["status"] == "deleted" and r["end"] for r in changes["delete"]))
        blind = {"assigned": False, "github": False, "projects": set(), "wanted": {"p1"}}
        payload, changes = pv.plan({}, blind, stored, NOW)
        self.assertEqual(payload, [])


class FailureTests(unittest.TestCase):
    """A failed run fails the unit only once the view is an hour stale."""

    def setUp(self):
        self.state = tempfile.TemporaryDirectory(prefix="project-view-state-")
        self.addCleanup(self.state.cleanup)
        patch = mock.patch.object(pv, "STATE_DIR", Path(self.state.name))
        patch.start()
        self.addCleanup(patch.stop)

    def last_run(self, minutes_ago):
        (Path(self.state.name) / "last-run.json").write_text(
            json.dumps({"at": (NOW - timedelta(minutes=minutes_ago)).isoformat()}))

    def test_a_fresh_view_warns_and_passes(self):
        self.last_run(20)
        with mock.patch("sys.stderr") as err:
            self.assertEqual(pv.failed(RuntimeError("Linear timed out"), NOW), 0)
        self.assertIn("WARN Linear timed out", "".join(c.args[0] for c in err.write.call_args_list))

    def test_a_stale_or_never_refreshed_view_fails(self):
        with mock.patch("sys.stderr"):
            self.assertEqual(pv.failed(RuntimeError("no key"), NOW), 1)
            self.last_run(61)
            self.assertEqual(pv.failed(RuntimeError("no key"), NOW), 1)


@unittest.skipUnless(shutil.which("task"), "task is not installed")
class TaskwarriorTests(unittest.TestCase):
    """The rows round-trip through a real Taskwarrior and the report shows them."""

    def setUp(self):
        self.data = tempfile.TemporaryDirectory(prefix="task-project-view-")
        self.addCleanup(self.data.cleanup)
        rc = Path(self.data.name) / "taskrc"
        rc.write_text(f"include {REPO / '.taskrc'}\ndata.location={self.data.name}\n"
                      "hooks=off\nconfirmation=off\nrecurrence=off\ncolor=off\n")
        self.env = {**os.environ, "TASKRC": str(rc), "TASKDATA": self.data.name}
        patches = [mock.patch.object(pv, "TASK_CMD", ["task", f"rc.data.location={self.data.name}"]),
                   mock.patch.dict(os.environ, {"TASKRC": str(rc), "TASKDATA": self.data.name})]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)

    def task(self, *args):
        result = subprocess.run(["task", f"rc.data.location={self.data.name}", "rc.hooks=off",
                                 "rc.confirmation=off", "rc.verbose=nothing", "rc.defaultwidth=250", *args],
                                env=self.env, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                timeout=20, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_report_lists_own_work_then_view_rows_and_reruns_are_quiet(self):
        project_name = "ci-infrastructure-improvements"
        self.task("rc.context=none", "add", "+work", f"project:{project_name}", "linear_issue_id:DEVOPS-1872",
                  "parallel job steps")
        self.task("rc.context=none", "add", "+work", "+piotr", f"project:{project_name}",
                  "linear_issue_id:DEVOPS-1828", "a handoff row")
        self.task("rc.context=none", "add", "+work", "project:talks", "not linear work")
        self.task("rc.context=none", "add", "+work", "+backlog", f"project:{project_name}",
                  "linear_issue_id:DEVOPS-1797", "compare runner costs")
        self.task("rc.context=none", "add", "+work", "+gordon", "linear_issue_id:DEVOPS-9", "gordon job")
        proj = project("p1", "CI infrastructure improvements",
                       [issue("DEVOPS-1872", "In Progress", "started", "Piotr Zaniewski", True)])
        snap = snapshot([proj], [assigned("DEVOPS-1879", "CI infrastructure improvements", "p1")])
        tasks = pv.task_json("(", "status:pending", "or", "status:waiting", ")")
        rows, scopes = pv.build_rows(snap, tasks, github(), NOW)
        payload, changes = pv.plan(rows, scopes, pv.task_json("+view"), NOW)
        self.assertEqual(len(changes["add"]), 2)
        pv.apply(payload)

        report = self.task("rc.context=none", "myprojects")
        lines = [line for line in report.splitlines() if line.strip()]
        body = [line for line in lines if project_name[:10] in line]
        self.assertEqual(len(body), 3, report)
        self.assertIn("parallel job steps", body[0])
        self.assertIn("no task · DEVOPS-1879", body[1])
        self.assertIn("standing · In Progress", body[2])
        self.assertIn("my backlog: 1 · 1 handoff", body[2])
        for hidden in ("a handoff row", "not linear work", "gordon job", "compare runner costs"):
            self.assertNotIn(hidden, report)
        self.assertNotIn("standing", self.task("rc.context=work", "inbox"))

        tasks = pv.task_json("(", "status:pending", "or", "status:waiting", ")")
        rows, scopes = pv.build_rows(snap, tasks, github(), NOW + timedelta(minutes=10))
        again, _ = pv.plan(rows, scopes, pv.task_json("+view"), NOW + timedelta(minutes=10))
        self.assertEqual(again, [])


if __name__ == "__main__":
    unittest.main()
