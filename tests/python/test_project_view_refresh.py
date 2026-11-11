"""Fixture-only source tests and isolated Taskwarrior context roundtrips."""

import copy
import importlib.util
import io
import json
import os
import re
import shutil
import subprocess
import tempfile
import threading
import unittest
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("project_view", REPO / "scripts/__project_view_refresh.py")
pv = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pv)
NOW = datetime(2026, 11, 11, 12, 0, tzinfo=UTC)


def stamp(days=0):
    return (NOW - timedelta(days=days)).isoformat().replace("+00:00", "Z")


def issue(ident, state="Todo", kind="unstarted", title="A title", prs=(), completed=None,
          updated=1, blockers=(), milestone=None):
    return {"identifier": ident, "title": title, "url": f"https://linear.app/loft/issue/{ident.lower()}",
            "updatedAt": stamp(updated), "completedAt": stamp(completed) if completed is not None else None,
            "canceledAt": None, "state": {"name": state, "type": kind},
            "assignee": {"name": "Piotr", "isMe": True}, "projectMilestone": milestone,
            "attachments": {"nodes": [{"url": u} for u in prs]},
            "inverseRelations": {"nodes": [{"type": "blocks", "issue": {"identifier": b,
                                            "state": {"type": t}}} for b, t in blockers]}}


def project(pid="p1", name="Release pipeline", issues=(), led=True, update_days=1):
    return {"id": pid, "name": name, "url": f"https://linear.app/loft/project/{pid}",
            "description": "Make releases reproducible.", "targetDate": "2026-12-08",
            "startDate": "2026-11-03", "status": {"name": "In Progress", "type": "started"},
            "lead": {"name": "Piotr", "isMe": led}, "led": led, "listed": True,
            "projectUpdates": {"nodes": [{"createdAt": stamp(update_days), "health": "onTrack",
                                         "user": {"name": "Piotr"}}]},
            "issues": list(issues), "milestones": []}


def assigned(ident="DEVOPS-1", pid="p1", name="Release pipeline"):
    return {"identifier": ident, "title": "Check prerequisites", "url": f"https://linear.app/loft/issue/{ident.lower()}",
            "project": {"id": pid, "name": name} if pid else None,
            "state": {"name": "Todo", "type": "unstarted"}}


def snapshot(projects=(), assigned_issues=()):
    return {"projects": {p["id"]: p for p in projects}, "assigned": list(assigned_issues),
            "wanted": [p["id"] for p in projects], "failures": []}


def github(prs=None, mine=None):
    return {"login": "Piotr", "mine": mine or {}, "teams": {"loft-sh/eng-devops"}, "prs": prs or {}}


def pr(ref="loft-sh/tool#12", state="OPEN", review="REVIEW_REQUIRED", merged=None, request="Piotr"):
    return {"url": "https://github.com/" + ref.replace("#", "/pull/"), "state": state,
            "title": "Fix release checks", "isDraft": False, "reviewDecision": review,
            "mergedAt": stamp(merged) if merged is not None else None, "closedAt": None,
            "author": {"login": "author"}, "reviewRequests": {"pageInfo": {"hasNextPage": False}, "nodes": [
                {"requestedReviewer": {"__typename": "User", "login": request}}]}}


def handoff(ident="DEVOPS-1", **fields):
    row = {"uuid": "12345678-1234-4234-8234-123456789abc", "status": "pending", "project": "admin",
           "description": "Review the result", "tags": ["piotr", "work"], "entry": "20261101T000000Z",
           "priority": "H", "annotations": [{"entry": "20261102T000000Z", "description": "Human context"}]}
    if ident:
        row["linear_issue_id"] = ident
    row.update(fields)
    return row


def stored(payload):
    return [{"entry": "20261101T000000Z", **row} for row in copy.deepcopy(payload)]


class LinearStatusTests(unittest.TestCase):
    def test_updates_exact_issue_and_preserves_unavailable(self):
        task = {"uuid": "31f19044-2838-4275-b59d-f4e0d971536b", "linear_issue_id": "DEVOPS-1688", "linear_status": "Todo"}
        issue = {"identifier": "DEVOPS-1688", "state": {"name": "Parked"}}
        snapshot = {"projects": {}, "assigned": None, "referenced": [issue]}
        self.assertEqual(pv.status_plan(snapshot, [task]), [(task["uuid"], "DEVOPS-1688", "Todo", "Parked")])
        self.assertEqual(pv.status_plan({"projects": {}, "assigned": None}, [task]), [])
        with mock.patch.object(pv.subprocess, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, "", "")
            pv.apply_statuses(pv.status_plan(snapshot, [task]))
            args = run.call_args.args[0]
            self.assertIn("linear_status.is:Todo", args)
            self.assertIn("linear_status:Parked", args)

    def test_exact_linear_ids_are_fetched_for_regular_tasks(self):
        self.assertEqual(pv.referenced_identifiers([{"linear_issue_id": "DEVOPS-1688", "tags": ["work"]}]), {"DEVOPS-1688"})


class ContextTests(unittest.TestCase):
    def test_achieved_milestones_persist_with_proof_and_due_dates_do_not_claim_done(self):
        proj = project()
        proj["milestones"] = [
            {"id": "design-id", "name": "Design approved", "status": "done", "progress": 1.0,
             "sortOrder": 1, "updatedAt": stamp(90), "targetDate": "2026-07-01"},
            {"id": "release-id", "name": "Release", "status": "overdue", "progress": 0.75,
             "sortOrder": 2, "updatedAt": stamp(1), "targetDate": "2026-10-01"}]
        _, brief = pv.standing(proj, [], github(), NOW)
        done, milestones = brief.split("## Done")[1].split("## Now")[0], brief.split("## Milestones")[1]
        self.assertIn("[Milestone Design approved](https://linear.app/loft/project/p1)", done)
        self.assertIn("Linear status done; source ID design-id; source updated 2026-08-13", done)
        self.assertIn("does not provide a completion date", done)
        self.assertNotIn("Milestone Release", done)
        self.assertIn("State: overdue; progress: 75%", milestones)
        self.assertIn("progress: 100%", milestones)

    def test_history_cap_and_order_are_explicit(self):
        proj = project(issues=[issue(f"DEVOPS-{n}", "Done", "completed", completed=n)
                               for n in range(1, 25)])
        proj["history_truncated"] = True
        _, brief = pv.standing(proj, [], github(), NOW)
        done = brief.split("## Done")[1].split("## Now")[0]
        self.assertEqual(done.count("Linear completed"), 20)
        self.assertLess(done.index("[DEVOPS-1 "), done.index("[DEVOPS-20 "))
        self.assertNotIn("[DEVOPS-21 ", done)
        self.assertIn("100 most recently updated completed issues", done)
        self.assertIn("20 shown by completion date", done)
        self.assertIn("History is truncated", done)

    def test_every_project_has_detailed_done_now_milestones_and_real_next(self):
        ref = "loft-sh/tool#12"
        done = issue("DEVOPS-1", "Done", "completed", "Make builds repeatable", completed=2,
                     prs=[pr(ref)["url"]])
        active = issue("DEVOPS-2", "In Review", "started", "Check rollout logs", prs=[pr(ref)["url"]],
                       blockers=[("DEVOPS-8", "started")], milestone={"id": "m1", "name": "Pilot"})
        a = project(issues=[done, active])
        a["milestones"] = [{"id": "m1", "name": "Pilot", "targetDate": "2026-11-20",
                             "description": "Verify one end-to-end release.", "sortOrder": 1,
                             "progress": 0.75, "status": "next", "updatedAt": stamp(1)}]
        b = project("p2", "Documentation", [issue("DOC-3", title="Write the setup guide")])
        next_row = handoff("DEVOPS-2", view_project="release-pipeline", description="Approve the verified release")
        rows, _ = pv.build_rows(snapshot([a, b]), [next_row], github({ref: pr(ref, state="MERGED", merged=1)}), NOW)
        for pid, name in (("p1", "Release pipeline"), ("p2", "Documentation")):
            row = rows[f"standing:{pid}"]
            brief = row["annotations"][-1]
            self.assertTrue(brief.startswith("brief: # " + name))
            for heading in ("## Done", "## Now", "## Milestones", "## Next"):
                self.assertIn(heading, brief)
            self.assertIn(f"[Linear project](https://linear.app/loft/project/{pid})", brief)
            self.assertNotIn("ci_project_status", brief)
        brief = rows["standing:p1"]["annotations"][-1]
        self.assertIn("[DEVOPS-1 Make builds repeatable](https://linear.app/loft/issue/devops-1)", brief)
        self.assertIn("Linear completed 2026-11-09", brief)
        self.assertIn("GitHub merged 2026-11-10", brief)
        self.assertIn("Check rollout logs", brief)
        self.assertIn("waiting on DEVOPS-8", brief)
        self.assertIn("milestone Pilot", brief)
        self.assertIn("target: 2026-11-20", brief)
        self.assertIn("progress: 75%", brief)
        self.assertIn("Verify one end-to-end release", brief)
        self.assertIn("Approve the verified release (DEVOPS-2; pending)", brief)
        self.assertIn("do not establish deployment", brief)
        self.assertNotIn("changed,", brief)
        self.assertIn("DOC-3 Write the setup guide", rows["standing:p2"]["annotations"][-1])

    def test_canceled_and_missing_timestamp_are_not_done_but_old_verified_completion_is(self):
        canceled = issue("DEVOPS-1", "Canceled", "canceled", completed=1)
        canceled["canceledAt"] = stamp(1)
        items = [canceled, issue("DEVOPS-2", "Done", "completed"),
                 issue("DEVOPS-3", "Done", "completed", completed=8)]
        _, text = pv.standing(project(issues=items), [], github(), NOW)
        done = text.split("## Done")[1].split("## Now")[0]
        for ident in ("DEVOPS-1", "DEVOPS-2"):
            self.assertNotIn(ident, done)
        self.assertIn("DEVOPS-3", done)
        self.assertIn("Linear completed 2026-11-03", done)

    def test_current_pr_review_states_and_unknowns_have_links(self):
        refs = ["loft-sh/tool#12", "loft-sh/tool#13", "loft-sh/tool#14"]
        item = issue("DEVOPS-1", prs=[pr(ref)["url"] for ref in refs])
        gh = github({refs[0]: pr(refs[0], review="CHANGES_REQUESTED"),
                     refs[1]: pr(refs[1], state="CLOSED")})
        _, text = pv.standing(project(issues=[item]), [], gh, NOW)
        self.assertIn("changes requested (DEVOPS-1)", text)
        self.assertIn("](https://github.com/loft-sh/tool/pull/13). closed", text)
        self.assertIn("loft-sh/tool#14: GitHub state unavailable", text)
        _, text = pv.standing(project(issues=[item]), [], None, NOW)
        self.assertIn("Current PR and review states are unknown", text)

    def test_member_project_relevance_uses_source_work_and_activity(self):
        dead = project(issues=[issue("DEVOPS-1", updated=40)], led=False, update_days=500)
        rows, _ = pv.build_rows(snapshot([dead]), [], github(), NOW)
        self.assertNotIn("standing:p1", rows)
        rows, _ = pv.build_rows(snapshot([dead], [assigned()]), [], github(), NOW)
        self.assertIn("standing:p1", rows)
        dead["led"] = True
        rows, _ = pv.build_rows(snapshot([dead]), [], github(), NOW)
        self.assertIn("standing:p1", rows)

    def test_no_ci_import_or_model_dependency(self):
        text = (REPO / "scripts/__project_view_refresh.py").read_text()
        self.assertNotIn("__ci_project_status", text)
        self.assertNotIn("ci-infrastructure-improvements", text)
        self.assertNotIn("importlib", text)


class AssociationTests(unittest.TestCase):
    def test_explicit_local_bucket_membership_survives_source_assessment(self):
        header = handoff(None, tags=["view"], view_key="local:my-bucket", project="my-bucket")
        member = handoff("DEVOPS-999", project="admin", view_project="my-bucket")
        native = handoff("DEVOPS-999", project="my-bucket", view_project="my-bucket")
        self.assertEqual(pv.association_plan(self.snap, [header, member, native]), ([], [header, member, native]))

    def test_unavailable_pr_preserves_only_tasks_that_reference_it(self):
        unavailable = "loft-sh/inaccessible#7"
        self.b["issues"][0]["attachments"]["nodes"].append({"url": pr(unavailable)["url"]})
        bad = handoff(None, description=pr(unavailable)["url"], view_project="previous-project")
        unknown = handoff(None, uuid=str(uuid.uuid4()), description=pr(unavailable)["url"])
        healthy = handoff(None, uuid=str(uuid.uuid4()), description=pr(self.ref)["url"])
        structured = handoff("DOC-3", uuid=str(uuid.uuid4()))
        conflict = handoff(None, uuid=str(uuid.uuid4()), view_project="prior-owner",
                           description=pr(unavailable)["url"] + " " + pr(self.ref)["url"])
        changes, resolved = pv.association_plan(self.snap, [bad, unknown, healthy, structured, conflict],
                                                 unavailable_refs={unavailable})
        self.assertEqual([t["view_project"] for t in changes], ["release-pipeline", "documentation"])
        self.assertEqual(resolved[0], bad)
        self.assertEqual(resolved[1], unknown)
        self.assertEqual(resolved[-1], conflict)

    def test_exact_linear_route_can_keep_working_after_title_slug_changes(self):
        self.a["issues"][0]["url"] = "https://linear.app/loft/issue/DEVOPS-1/new-title"
        task = handoff(None, description="https://linear.app/loft/issue/DEVOPS-1/old-title")
        changes, _ = pv.association_plan(self.snap, [task])
        self.assertEqual(changes[0]["view_project"], "release-pipeline")
        task["description"] = "https://linear.app/other-workspace/issue/DEVOPS-1/new-title"
        self.assertEqual(pv.association_plan(self.snap, [task])[0][0]["view_project"], "!unassigned")

    def test_standalone_pr_without_verified_issue_linkage_remains_unassigned(self):
        task = handoff(None, description="https://github.com/loft-sh/tool/pull/999")
        changes, resolved = pv.association_plan(self.snap, [task])
        self.assertEqual(changes[0]["view_project"], "!unassigned")
        self.assertEqual(resolved[0]["project"], "admin")

    def setUp(self):
        self.ref = "loft-sh/tool#12"
        self.a = project(issues=[issue("DEVOPS-1", prs=[pr(self.ref)["url"]])])
        self.b = project("p2", "Documentation", [issue("DOC-3")])
        self.snap = snapshot([self.a, self.b])

    def test_structured_id_exact_issue_url_and_pr_url_resolve(self):
        tasks = [handoff(), handoff(None, uuid=str(uuid.uuid4()), description="Read this " + self.b["issues"][0]["url"]),
                 handoff(None, uuid=str(uuid.uuid4()), annotations=[{"entry": "20261101T000000Z",
                            "description": "link: " + pr(self.ref)["url"]}])]
        changes, resolved = pv.association_plan(self.snap, tasks)
        self.assertEqual([t["view_project"] for t in changes], ["release-pipeline", "documentation", "release-pipeline"])
        for old, new in zip(tasks, resolved):
            self.assertEqual({k: v for k, v in new.items() if k != "view_project"}, old)
            self.assertEqual(new["project"], "admin")

    def test_multiple_exact_links_to_the_same_owner_are_unambiguous(self):
        task = handoff(description=self.a["issues"][0]["url"] + " " + pr(self.ref)["url"])
        changes, _ = pv.association_plan(self.snap, [task])
        self.assertEqual(changes[0]["view_project"], "release-pipeline")

    def test_prose_team_project_and_similar_urls_do_not_guess_ownership(self):
        tasks = [handoff(None, description="Release pipeline DEVOPS-1 requires review", project="release-pipeline"),
                 handoff(None, description=pr(self.ref)["url"] + "/files"),
                 handoff(None, description="https://example.org/loft/issue/devops-1"),
                 handoff(None, description=self.a["issues"][0]["url"] + "-similar")]
        changes, resolved = pv.association_plan(self.snap, tasks)
        self.assertEqual(len(changes), 1)
        self.assertEqual(changes[0]["uuid"], tasks[-1]["uuid"])
        self.assertTrue(all(not t.get("view_project") for t in resolved[:-1]))
        self.assertEqual(resolved[-1]["view_project"], "!unassigned")

    def test_conflicting_sources_or_unknown_structured_id_remain_unassigned(self):
        tasks = [handoff(description=self.b["issues"][0]["url"], view_project="release-pipeline"),
                 handoff("DEVOPS-999", description=pr(self.ref)["url"], view_project="release-pipeline")]
        changes, resolved = pv.association_plan(self.snap, tasks)
        self.assertEqual([t["view_project"] for t in changes], ["!unassigned", "!unassigned"])
        self.assertTrue(all(t["view_project"] == "!unassigned" for t in resolved))

    def test_shared_pr_duplicate_issue_id_and_slug_collisions_do_not_choose(self):
        self.b["issues"].append(issue("DOC-4", prs=[pr(self.ref)["url"]]))
        task = handoff(None, description=pr(self.ref)["url"], view_project="release-pipeline")
        changes, _ = pv.association_plan(self.snap, [task])
        self.assertEqual(changes[0]["view_project"], "!unassigned")
        self.b["issues"].append(issue("DEVOPS-1"))
        changes, _ = pv.association_plan(self.snap, [handoff(view_project="release-pipeline")])
        self.assertEqual(changes[0]["view_project"], "!unassigned")
        self.b["name"] = self.a["name"]
        changes, _ = pv.association_plan(self.snap, [handoff("DOC-3", view_project="documentation")])
        self.assertEqual(changes[0]["view_project"], "!unassigned")

    def test_failed_exact_assessment_cannot_fall_back_to_matching_native_project(self):
        for task in (handoff(description="Make the critical decision " + self.b["issues"][0]["url"]),
                     handoff("DEVOPS-999", description="Make the critical decision"),
                     handoff(None, description="Make the critical decision https://github.com/loft-sh/tool/pull/999")):
            task["project"] = "release-pipeline"
            changes, resolved = pv.association_plan(self.snap, [task])
            self.assertEqual(changes[0]["view_project"], "!unassigned")
            self.assertEqual(resolved[0]["uuid"], task["uuid"])
            self.assertEqual(resolved[0]["project"], "release-pipeline")
            rows, _ = pv.build_rows(self.snap, resolved, github(), NOW)
            for key in ("standing:p1", "standing:p2"):
                next_section = rows[key]["annotations"][-1].split("## Next")[1]
                self.assertNotIn("Make the critical decision", next_section)

    def test_legacy_no_evidence_keeps_native_fallback_and_unresolved_marker_persists(self):
        legacy = handoff(None, project="release-pipeline", description="Legacy native action")
        marked = handoff(None, project="release-pipeline", view_project="!unassigned", description="Unresolved action")
        changes, resolved = pv.association_plan(self.snap, [legacy, marked])
        self.assertEqual(changes, [])
        self.assertEqual(resolved, [legacy, marked])
        rows, _ = pv.build_rows(self.snap, resolved, github(), NOW)
        next_section = rows["standing:p1"]["annotations"][-1].split("## Next")[1]
        self.assertIn("Legacy native action", next_section)
        self.assertNotIn("Unresolved action", next_section)

    def test_failure_preserves_last_verified_association_and_all_fields(self):
        task = handoff(view_project="release-pipeline", wait="20261201T000000Z", depends=[str(uuid.uuid4())])
        for mode in ("project", "assigned", "github"):
            snap = copy.deepcopy(self.snap)
            if mode == "project":
                snap["failures"] = ["project p1 timed out"]
                snap["projects"].pop("p1")
            elif mode == "assigned":
                snap["assigned"] = None
            changes, resolved = pv.association_plan(snap, [task], mode != "github")
            self.assertEqual(changes, [])
            self.assertEqual(resolved, [task])

    def test_non_handoff_and_view_rows_are_never_reassociated(self):
        tasks = [handoff(tags=["work"]), handoff(tags=["piotr", "view"])]
        self.assertEqual(pv.association_plan(self.snap, tasks), ([], tasks))

    def test_verified_unchanged_grouping_does_not_churn_metadata(self):
        task = handoff(view_project="release-pipeline", modified="20261103T000000Z")
        self.assertEqual(pv.association_plan(self.snap, [task]), ([], [task]))


class SourceRowTests(unittest.TestCase):
    def test_local_buckets_require_two_non_gordon_tasks_and_keep_existing_header(self):
        def task(uid, project_name, tags=()):
            return handoff(None, uuid=uid, project=project_name, tags=list(tags))
        tasks = [task("1", "local-ops"), task("2", "local-ops"),
                 task("3", "single"), task("4", "single", ["gordon"]),
                 task("5", "admin"), task("6", "admin"), task("7", "release-pipeline")]
        linear, local = pv.bucket_candidates(tasks, {"release-pipeline": ["p1"]})
        self.assertEqual(linear, {"release-pipeline"})
        self.assertEqual(local, {"local-ops"})
        snap = snapshot([project()])
        snap["local_buckets"] = local
        rows, scopes = pv.build_rows(snap, tasks, github(), NOW)
        self.assertEqual(rows["local:local-ops"]["view_title"], "Local Ops")
        header = handoff(None, tags=["view"], project="local-ops", view_key="local:local-ops")
        rows, scopes = pv.build_rows(snap, tasks + [header], github(), NOW)
        self.assertNotIn("local:local-ops", rows)
        self.assertNotIn(header, pv.plan(rows, scopes, [header], NOW)[0])

    def test_generated_row_metadata_comes_from_structured_sources(self):
        ref = "loft-sh/tool#12"
        activity = issue("DEVOPS-1", "In Review", "started", title="Explain the release change", prs=[pr(ref)["url"]])
        assigned_issue = assigned("DEVOPS-5")
        snap = snapshot([project(issues=[activity])], [assigned_issue])
        gh = github({ref: pr(ref, review="CHANGES_REQUESTED")})
        rows, scopes = pv.build_rows(snap, [], gh, NOW)
        expected = {"standing:p1": ("project", "Release pipeline", "In Progress", ""),
                    "issue:DEVOPS-5": ("issue", "Check prerequisites", "Todo", "DEVOPS-5"),
                    "ask:p1:" + ref: ("ask", "Fix release checks", "changes requested", "DEVOPS-1")}
        for key, values in expected.items():
            self.assertEqual(tuple(rows[key][field] for field in pv.VIEW_METADATA), values)
        self.assertEqual(rows["standing:p1"]["description"], "Release pipeline")
        self.assertEqual(rows["issue:DEVOPS-5"]["description"], "no task · DEVOPS-5 Todo · Check prerequisites")
        payload, _ = pv.plan(rows, scopes, [], NOW)
        for row in payload:
            self.assertNotIn("linear_issue_id", row)
        for field in pv.VIEW_METADATA:
            self.assertIn(f"rc.uda.{field}.type=string", pv.TASK_UDA)

    def test_project_without_activity_has_no_invented_source_issue(self):
        rows, _ = pv.build_rows(snapshot([project()]), [], github(), NOW)
        row = rows["standing:p1"]
        self.assertEqual(row["view_kind"], "project")
        self.assertEqual(row["view_title"], "Release pipeline")
        self.assertEqual(row["view_state"], "In Progress")
        self.assertEqual(row["view_issue"], "")

    def test_untracked_issue_and_review_keep_separate_identity_and_exact_links(self):
        ref = "loft-sh/tool#12"
        proj = project(issues=[issue("DEVOPS-1", prs=[pr(ref)["url"]])])
        rows, scopes = pv.build_rows(snapshot([proj], [assigned()]), [], github({ref: pr(ref)}), NOW)
        self.assertEqual(set(rows), {"standing:p1", "issue:DEVOPS-1", "ask:p1:" + ref})
        self.assertIn("link: " + assigned()["url"], rows["issue:DEVOPS-1"]["annotations"])
        self.assertIn("link: " + pr(ref)["url"], rows["ask:p1:" + ref]["annotations"])
        payload, _ = pv.plan(rows, scopes, [], NOW)
        for row in payload:
            self.assertEqual(row["tags"], ["view"])
            self.assertNotIn("linear_issue_id", row)
            self.assertNotIn("piotr", row["tags"])

    def test_real_issue_task_suppresses_source_mirror_and_projectless_issue_uses_team(self):
        snap = snapshot([], [assigned(), assigned("ENGAI-3", None)])
        rows, _ = pv.build_rows(snap, [handoff()], github(), NOW)
        self.assertNotIn("issue:DEVOPS-1", rows)
        self.assertEqual(rows["issue:ENGAI-3"]["project"], "ai")
        rows, _ = pv.build_rows(snap, [handoff(tags=["view"])], github(), NOW)
        self.assertIn("issue:DEVOPS-1", rows)

    def test_own_draft_closed_or_unrequested_pr_is_not_a_review_row(self):
        ref = "loft-sh/tool#12"
        proj = project(issues=[issue("DEVOPS-1", prs=[pr(ref)["url"]])])
        draft = pr(ref)
        draft["isDraft"] = True
        for gh in (github({ref: draft}), github({ref: pr(ref, state="CLOSED")}),
                   github({ref: pr(ref, request="someone-else")}), github(mine={ref: pr(ref)})):
            rows, _ = pv.build_rows(snapshot([proj]), [], gh, NOW)
            self.assertFalse(any(k.startswith("ask:") for k in rows))


class PlanTests(unittest.TestCase):
    def test_new_issue_ranks_follow_source_order_after_all_existing_ranks(self):
        first, second = issue("DEVOPS-2"), issue("DEVOPS-1")
        first["sortOrder"], second["sortOrder"] = 10, 20
        proj = project(issues=[second, first])
        rows, scopes = pv.build_rows(snapshot([proj], [assigned("DEVOPS-1"), assigned("DEVOPS-2")]), [], github(), NOW)
        existing = [handoff(view_project="release-pipeline", view_rank=35)]
        payload, _ = pv.plan(rows, scopes, existing, NOW)
        ranks = {row["view_key"]: row.get("view_rank") for row in payload}
        self.assertEqual(ranks["issue:DEVOPS-2"], 40)
        self.assertEqual(ranks["issue:DEVOPS-1"], 50)

    def test_existing_rank_survives_refresh(self):
        first, _ = pv.plan(self.rows, self.scopes, [], NOW)
        old = stored(first)
        old[0]["view_rank"] = 73
        self.rows["standing:p1"]["view_state"] = "Paused"
        changed, _ = pv.plan(self.rows, self.scopes, old, NOW)
        self.assertEqual(changed[0]["view_rank"], 73)
        self.assertEqual(pv.plan(self.rows, self.scopes, stored(changed), NOW)[0], [])

    def test_a_structured_metadata_change_is_applied_once_without_rewriting_other_fields(self):
        first, _ = pv.plan(self.rows, self.scopes, [], NOW)
        old = stored(first)
        old[0]["custom"] = "Keep this"
        old[0]["due"] = "20261201T000000Z"
        self.rows["standing:p1"]["view_state"] = "Paused"
        changed, _ = pv.plan(self.rows, self.scopes, old, NOW)
        self.assertEqual(len(changed), 1)
        self.assertEqual(changed[0]["view_state"], "Paused")
        for field in ("uuid", "description", "project", "tags", "entry", "annotations", "custom", "due"):
            self.assertEqual(changed[0][field], old[0][field])
        self.assertEqual(pv.plan(self.rows, self.scopes, stored(changed), NOW)[0], [])

    def setUp(self):
        self.rows, self.scopes = pv.build_rows(snapshot([project(issues=[issue("DEVOPS-1")])]), [], github(), NOW)

    def test_uuid_is_stable_and_existing_header_identity_is_preserved(self):
        first, _ = pv.plan(self.rows, self.scopes, [], NOW)
        self.assertEqual(first[0]["uuid"], pv.row_uuid("standing:p1"))
        old = stored(first)
        old[0]["uuid"] = "12345678-1234-4234-8234-123456789abc"
        self.rows["standing:p1"]["description"] = "standing · changed"
        again, _ = pv.plan(self.rows, self.scopes, old, NOW)
        self.assertEqual(again[0]["uuid"], old[0]["uuid"])
        self.assertEqual(again[0]["entry"], old[0]["entry"])

    def test_unchanged_refresh_is_quiet_and_human_fields_and_annotations_survive(self):
        first, _ = pv.plan(self.rows, self.scopes, [], NOW)
        old = stored(first)
        old[0]["due"] = "20261201T000000Z"
        old[0]["custom"] = "preserve me"
        old[0]["annotations"].append({"entry": "20261101T000000Z", "description": "Human context"})
        old[0]["annotations"].append({"entry": "20261102T000000Z", "description": "https://example.com/proof"})
        old[0]["annotations"].sort(key=lambda a: a["entry"])
        again, _ = pv.plan(self.rows, self.scopes, old, NOW + timedelta(minutes=10))
        self.assertEqual(again, [])
        self.rows["standing:p1"]["annotations"][-1] = "brief: Changed context\n"
        changed, _ = pv.plan(self.rows, self.scopes, old, NOW + timedelta(hours=1))
        self.assertEqual(changed[0]["custom"], "preserve me")
        self.assertEqual(changed[0]["due"], old[0]["due"])
        self.assertEqual(changed[0]["annotations"][-1]["description"], "brief: Changed context\n")
        self.assertIn("Human context", [a["description"] for a in changed[0]["annotations"]])
        self.assertIn("https://example.com/proof", [a["description"] for a in changed[0]["annotations"]])

    def test_obsolete_rows_delete_only_after_a_complete_source_read(self):
        first, _ = pv.plan(self.rows, self.scopes, [], NOW)
        old = stored(first)
        blind = {"assigned": False, "github": False, "projects": set(), "wanted": {"p1"}}
        payload, _ = pv.plan({}, blind, old, NOW)
        self.assertEqual(payload, [])
        payload, changes = pv.plan({}, self.scopes, old, NOW)
        self.assertEqual([r["status"] for r in changes["delete"]], ["deleted"])
        self.assertTrue(payload[0]["end"])

    def test_an_unrelated_view_key_is_not_adopted_or_deleted(self):
        old = handoff(tags=["view"], view_key="some-other-view")
        payload, _ = pv.plan({}, self.scopes, [old], NOW)
        self.assertEqual(payload, [])


class RefreshTests(unittest.TestCase):
    def test_rate_limited_project_defers_but_completed_project_snapshot_publishes(self):
        a = self.snap["projects"]["p1"]
        b = project("p2", "Other project", [issue("DOC-2", title="Prior other work")])
        snap = snapshot([a, b])
        rows, scopes = pv.build_rows(snap, [], github(), NOW)
        sources = pv.source_status(rows, scopes, [], snap, github(), NOW, {})
        first, _ = pv.plan(rows, scopes, [], NOW)
        old = stored(first)
        a["issues"][0]["title"] = "Fresh completed source read"
        later = NOW + timedelta(minutes=10)
        partial = snapshot([a])
        partial.update(wanted=["p1", "p2"], failures=["project p2 rate limited"], reference_failure=True,
                       reference_rate_limited=True, rate_limit=pv.rate_limit_record({}, later))
        rows, scopes = pv.build_rows(partial, old, github(), later)
        pv.source_status(rows, scopes, old, partial, github(), later, {"sources": sources})
        self.assertIn("Fresh completed source read", rows["standing:p1"]["annotations"][-1])
        self.assertEqual(rows["standing:p1"]["view_state"], "In Progress")
        self.assertIn("Prior other work", rows["standing:p2"]["annotations"][-1])
        self.assertIn("Linear project deferred until " + partial["rate_limit"]["retry_at"],
                      rows["standing:p2"]["annotations"][-1])
        self.assertIn("Linear last verified: " + NOW.isoformat(), rows["standing:p2"]["annotations"][-1])

    def test_failed_source_retains_structured_title_and_issue_with_unavailable_state(self):
        rows, scopes, sources = self.generate()
        first, _ = pv.plan(rows, scopes, [], NOW)
        old = stored(first)
        changed_snap = copy.deepcopy(self.snap)
        changed_snap["projects"]["p1"]["issues"] = [issue("DEVOPS-999", title="Withheld newer action")]
        later = NOW + timedelta(minutes=10)
        rows, scopes = pv.build_rows(changed_snap, old, None, later)
        pv.source_status(rows, scopes, old, changed_snap, None, later, {"sources": sources})
        row = rows["standing:p1"]
        self.assertEqual(row["view_kind"], "project")
        self.assertEqual(row["view_title"], "Release pipeline")
        self.assertEqual(row["view_issue"], "")
        self.assertEqual(row["view_state"], "In Progress")
        payload, _ = pv.plan(rows, scopes, old, later)
        self.assertEqual(payload[0]["view_title"], old[0]["view_title"])
        self.assertEqual(pv.plan(rows, scopes, stored(payload), later)[0], [])

    def test_unreadable_attached_pr_retains_only_affected_context_and_review_row(self):
        healthy, unavailable = "loft-sh/tool#12", "loft-sh/inaccessible#7"
        a = project("p1", "Healthy project", [issue("DEVOPS-1", title="Healthy old title", prs=[pr(healthy)["url"]])])
        b = project("p2", "Affected project", [issue("DOC-2", title="Affected old title", prs=[pr(unavailable)["url"]])])
        snap = snapshot([a, b])
        initial_gh = github({healthy: pr(healthy), unavailable: pr(unavailable)})
        rows, scopes = pv.build_rows(snap, [], initial_gh, NOW)
        sources = pv.source_status(rows, scopes, [], snap, initial_gh, NOW, {})
        first, _ = pv.plan(rows, scopes, [], NOW)
        old = stored(first)
        a["issues"][0]["title"] = "Healthy updated title"
        b["issues"][0]["title"] = "Affected withheld title"
        partial_gh = {**github({healthy: pr(healthy, state="CLOSED")}), "unavailable_refs": {unavailable}}
        later = NOW + timedelta(minutes=10)
        rows, scopes = pv.build_rows(snap, [], partial_gh, later)
        sources = pv.source_status(rows, scopes, old, snap, partial_gh, later, {"sources": sources})
        healthy_text = rows["standing:p1"]["annotations"][-1]
        affected_text = rows["standing:p2"]["annotations"][-1]
        self.assertIn("Healthy updated title", healthy_text)
        self.assertIn("GitHub last verified: " + later.isoformat(), healthy_text)
        self.assertNotIn("source unavailable", rows["standing:p1"]["description"])
        self.assertIn("Affected old title", affected_text)
        self.assertNotIn("Affected withheld title", affected_text)
        self.assertIn("GitHub unreadable for " + unavailable, affected_text)
        self.assertIn("current PR states unknown", affected_text)
        self.assertIn("Linear last verified: " + NOW.isoformat(), affected_text)
        self.assertIn("GitHub last verified: " + NOW.isoformat(), affected_text)
        self.assertEqual(sources["projects"], {"p1": later.isoformat(), "p2": NOW.isoformat()})
        self.assertEqual(sources["github_projects"], {"p1": later.isoformat(), "p2": NOW.isoformat()})
        changed, changes = pv.plan(rows, scopes, old, later)
        self.assertEqual([t["view_key"] for t in changes["delete"]], ["ask:p1:" + healthy])
        self.assertNotIn("ask:p2:" + unavailable, {t["view_key"] for t in changed})
        self.assertFalse(pv.judged("ask:p2:" + unavailable, scopes))

    def test_new_affected_project_marks_unavailable_pr_unknown_without_a_snapshot_claim(self):
        unavailable = "loft-sh/inaccessible#7"
        self.snap["projects"]["p1"]["issues"][0]["attachments"]["nodes"] = [{"url": pr(unavailable)["url"]}]
        partial_gh = {**github(), "unavailable_refs": {unavailable}}
        rows, scopes = pv.build_rows(self.snap, [], partial_gh, NOW)
        sources = pv.source_status(rows, scopes, [], self.snap, partial_gh, NOW, {})
        text = rows["standing:p1"]["annotations"][-1]
        self.assertIn("Current release checks", text)
        self.assertIn("GitHub unavailable; current PR and review states are unknown", text)
        self.assertIn("Linear last verified: " + NOW.isoformat(), text)
        self.assertIn("GitHub last verified: unknown", text)
        self.assertIsNone(sources["github_projects"]["p1"])

    def test_partial_github_summary_and_warning_name_unavailable_refs(self):
        unavailable = "loft-sh/inaccessible#7"
        self.snap["projects"]["p1"]["issues"][0]["attachments"]["nodes"] = [{"url": pr(unavailable)["url"]}]
        self.gh["unavailable_refs"] = {unavailable}
        self.state.mkdir()
        (self.state / "last-run.json").write_text(json.dumps({"at": NOW.isoformat()}))
        patches = self.main_patches()
        with mock.patch.object(pv, "apply"):
            self.assertEqual(pv.main([]), 0)
        summary = json.loads((self.state / "last-run.json").read_text())
        self.assertEqual(summary["unavailable_refs"], [unavailable])
        self.assertEqual(summary["failures"], [])
        warning = "".join(c.args[0] for c in patches[6].write.call_args_list)
        self.assertIn("GitHub attached PR unreadable: " + unavailable, warning)

    def test_outages_preserve_only_active_overviews_and_never_revive_history(self):
        projects = [project(f"p{n}", f"Project {n}", [issue(f"DEVOPS-{n}")]) for n in range(1, 5)]
        snap = snapshot(projects)
        rows, scopes = pv.build_rows(snap, [], github(), NOW)
        sources = pv.source_status(rows, scopes, [], snap, github(), NOW, {})
        payload, _ = pv.plan(rows, scopes, [], NOW)
        old = stored(payload)
        statuses = {"standing:p1": "pending", "standing:p2": "deleted",
                    "standing:p3": "completed", "standing:p4": "waiting"}
        for task in old:
            task["status"] = statuses[task["view_key"]]
        self.state.mkdir()
        (self.state / "last-run.json").write_text(json.dumps({"at": NOW.isoformat(), "sources": sources}))
        self.main_patches(old)
        for mode in ("total", "assigned", "reference"):
            with self.subTest(mode=mode):
                unavailable = {"projects": {}, "assigned": None if mode == "assigned" else [],
                               "wanted": [], "failures": [mode + " unavailable"],
                               "reference_failure": mode == "reference"}
                read = (mock.patch.object(pv, "read_linear", side_effect=RuntimeError("offline"))
                        if mode == "total" else mock.patch.object(pv, "read_linear", return_value=unavailable))
                with read, mock.patch.object(pv, "apply") as apply:
                    self.assertEqual(pv.main([]), 0)
                changed = apply.call_args.args[0]
                self.assertEqual({t["view_key"] for t in changed}, {"standing:p1", "standing:p4"})
                self.assertTrue(all(t["status"] == "pending" for t in changed))
                for task in old:
                    file = self.briefs / task["uuid"] / "project-status.md"
                    self.assertEqual(file.exists(), task["status"] in ("pending", "waiting"))

    def test_actual_current_source_can_reuse_a_deleted_header_uuid(self):
        rows, scopes, sources = self.generate()
        first, _ = pv.plan(rows, scopes, [], NOW)
        old = stored(first)
        old[0].update(status="deleted", uuid="12345678-1234-4234-8234-123456789abc")
        rows, scopes = pv.build_rows(self.snap, old, github(), NOW)
        pv.source_status(rows, scopes, old, self.snap, github(), NOW, {"sources": sources})
        changed, _ = pv.plan(rows, scopes, old, NOW)
        self.assertEqual(len(changed), 1)
        self.assertEqual(changed[0]["uuid"], old[0]["uuid"])
        self.assertEqual(changed[0]["status"], "pending")

    def test_repeated_github_outages_keep_the_displayed_linear_snapshot_time(self):
        rows, scopes, sources = self.generate()
        first, _ = pv.plan(rows, scopes, [], NOW)
        old = stored(first)
        for minutes in (10, 20, 30):
            later = NOW + timedelta(minutes=minutes)
            snap = copy.deepcopy(self.snap)
            snap["projects"]["p1"]["issues"][0]["title"] = f"Withheld newer title at {minutes}"
            rows, scopes = pv.build_rows(snap, old, None, later)
            sources = pv.source_status(rows, scopes, old, snap, None, later, {"sources": sources})
            text = rows["standing:p1"]["annotations"][-1]
            self.assertIn("Current release checks", text)
            self.assertNotIn("Withheld newer title", text)
            self.assertIn("Linear last verified: " + NOW.isoformat(), text)
            self.assertIn("GitHub last verified: " + NOW.isoformat(), text)
            self.assertNotIn(later.isoformat(), text)
            self.assertEqual(sources["projects"]["p1"], NOW.isoformat())
            self.assertEqual(sources["github_projects"]["p1"], NOW.isoformat())
            changed, _ = pv.plan(rows, scopes, old, later)
            if minutes == 10:
                self.assertEqual(len(changed), 1)
                old = stored(changed)
            else:
                self.assertEqual(changed, [])

    def test_retained_github_snapshot_is_per_project_during_partial_failure(self):
        a = self.snap["projects"]["p1"]
        b = project("p2", "Other project", [issue("DOC-2", title="Other work")])
        snap = snapshot([a, b])
        rows, scopes = pv.build_rows(snap, [], github(), NOW)
        sources = pv.source_status(rows, scopes, [], snap, github(), NOW, {})
        first, _ = pv.plan(rows, scopes, [], NOW)
        old = stored(first)
        later = NOW + timedelta(minutes=10)
        partial = snapshot([b])
        partial.update(wanted=["p1", "p2"], failures=["project p1 unavailable"])
        rows, scopes = pv.build_rows(partial, old, github(), later)
        sources = pv.source_status(rows, scopes, old, partial, github(), later, {"sources": sources})
        changed, _ = pv.plan(rows, scopes, old, later)
        old = stored(changed)
        self.assertEqual(sources["github_projects"], {"p1": NOW.isoformat(), "p2": later.isoformat()})
        final = NOW + timedelta(minutes=20)
        rows, scopes = pv.build_rows(snap, old, None, final)
        pv.source_status(rows, scopes, old, snap, None, final, {"sources": sources})
        self.assertIn("GitHub last verified: " + NOW.isoformat(), rows["standing:p1"]["annotations"][-1])
        self.assertIn("GitHub last verified: " + later.isoformat(), rows["standing:p2"]["annotations"][-1])

    def test_dated_source_snapshots_expose_stopped_timer_and_same_time_is_idempotent(self):
        rows, scopes, sources = self.generate()
        first, _ = pv.plan(rows, scopes, [], NOW)
        old = stored(first)
        text = rows["standing:p1"]["annotations"][-1]
        self.assertIn("Linear last verified: " + NOW.isoformat(), text)
        self.assertIn("GitHub last verified: " + NOW.isoformat(), text)
        self.assertIn("Expected refresh: every 10 minutes", text)
        self.assertIn("times stop advancing", text)
        same_rows, same_scopes, _ = self.generate(tasks=old, previous={"sources": sources})
        self.assertEqual(pv.plan(same_rows, same_scopes, old, NOW)[0], [])
        next_rows, next_scopes, _ = self.generate(tasks=old, previous={"sources": sources},
                                                 when=NOW + timedelta(minutes=10))
        self.assertEqual(len(pv.plan(next_rows, next_scopes, old, NOW + timedelta(minutes=10))[0]), 1)

    def test_history_source_failure_preserves_old_done_in_partial_and_total_failure(self):
        self.snap["projects"]["p1"]["issues"].append(
            issue("DEVOPS-50", "Done", "completed", title="Completed release milestone", completed=90))
        rows, scopes, sources = self.generate()
        headers, _ = pv.plan(rows, scopes, [], NOW)
        old = stored(headers)
        for total in (False, True):
            snap = {"projects": {}, "assigned": None if total else [], "wanted": ["p1"],
                    "failures": ["history source failed"]}
            rows, scopes = pv.build_rows(snap, old, None if total else github(), NOW)
            pv.source_status(rows, scopes, old, snap, None if total else github(), NOW, {"sources": sources})
            text = rows["standing:p1"]["annotations"][-1]
            self.assertIn("DEVOPS-50 Completed release milestone", text)
            self.assertIn("Linear completed 2026-08-13", text)
            self.assertIn("Prior context retained", text)

    def test_reference_lookup_failure_retains_project_that_discovery_could_not_repeat(self):
        rows, scopes, sources = self.generate()
        headers, _ = pv.plan(rows, scopes, [], NOW)
        old = stored(headers) + [handoff(view_project="release-pipeline")]
        self.state.mkdir()
        (self.state / "last-run.json").write_text(json.dumps({"at": NOW.isoformat(), "sources": sources}))
        self.main_patches(old)
        failed_snap = {"projects": {}, "assigned": [], "wanted": [], "failures": ["references unavailable"],
                       "reference_failure": True}
        with mock.patch.object(pv, "read_linear", return_value=failed_snap), mock.patch.object(pv, "apply") as apply:
            self.assertEqual(pv.main([]), 0)
        payload = apply.call_args.args[0]
        self.assertEqual(len(payload), 1)
        self.assertEqual(payload[0]["status"], "pending")
        self.assertIn("Linear handoff ownership unavailable", payload[0]["annotations"][-1]["description"])

    def test_repeated_source_failure_does_not_advance_last_success(self):
        self.state.mkdir()
        previous = NOW - timedelta(hours=2)
        (self.state / "last-run.json").write_text(json.dumps({"at": previous.isoformat()}))
        self.main_patches()
        with mock.patch.object(pv, "read_linear", side_effect=RuntimeError("offline")), mock.patch.object(pv, "apply"):
            self.assertEqual(pv.main([]), 1)
        result = json.loads((self.state / "last-run.json").read_text())
        self.assertEqual(result["last_success_at"], previous.isoformat())
        self.assertNotEqual(result["at"], result["last_success_at"])

    def setUp(self):
        folder = tempfile.TemporaryDirectory(prefix="project-view-")
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        self.state, self.briefs = self.root / "state", self.root / "briefs"
        for patch in (mock.patch.object(pv, "STATE_DIR", self.state),
                      mock.patch.object(pv, "BRIEFS_DIR", self.briefs)):
            patch.start()
            self.addCleanup(patch.stop)
        self.snap = snapshot([project(issues=[issue("DEVOPS-1", title="Current release checks")])])
        self.gh = github()

    def generate(self, snap=None, tasks=(), gh=None, previous=None, when=NOW):
        snap = self.snap if snap is None else snap
        gh = self.gh if gh is None else gh
        rows, scopes = pv.build_rows(snap, list(tasks), gh, when)
        sources = pv.source_status(rows, scopes, list(tasks), snap, gh, when, previous or {})
        return rows, scopes, sources

    def test_successful_unchanged_snapshot_does_not_rewrite_tasks_or_files(self):
        rows, scopes, sources = self.generate()
        first, _ = pv.plan(rows, scopes, [], NOW)
        old = stored(first)
        pv.publish_contexts(rows, old)
        path = self.briefs / first[0]["uuid"] / "project-status.md"
        inode = path.stat().st_ino
        later = NOW  # Same observation time and source content are idempotent.
        rows, scopes, _ = self.generate(tasks=old, previous={"sources": sources}, when=later)
        again, _ = pv.plan(rows, scopes, old, later)
        self.assertEqual(again, [])
        pv.publish_contexts(rows, old)
        self.assertEqual(path.stat().st_ino, inode)

    def test_failed_project_or_github_retains_context_with_stable_source_age(self):
        rows, scopes, sources = self.generate()
        first, _ = pv.plan(rows, scopes, [], NOW)
        old = stored(first)
        prior = {"sources": sources}
        for fail in ("project", "github", "assigned"):
            snap = copy.deepcopy(self.snap)
            gh = self.gh
            if fail == "project":
                snap["projects"] = {}
                snap["failures"] = ["project p1 unavailable"]
            elif fail == "github":
                gh = None
                snap["projects"]["p1"]["issues"][0]["title"] = "New partial title"
            else:
                snap["assigned"] = None
            current, current_scopes = pv.build_rows(snap, old, gh, NOW + timedelta(minutes=10))
            pv.source_status(current, current_scopes, old, snap, gh, NOW + timedelta(minutes=10), prior)
            brief = current["standing:p1"]["annotations"][-1]
            self.assertIn("Current release checks", brief)
            self.assertNotIn("New partial title", brief)
            self.assertIn("unavailable", brief)
            self.assertIn(NOW.isoformat(), brief)
            stale, _ = pv.plan(current, current_scopes, old, NOW + timedelta(minutes=10))
            again, _ = pv.plan(current, current_scopes, stored(stale), NOW + timedelta(minutes=20))
            self.assertEqual(again, [])

    def test_new_project_without_github_states_says_unknown(self):
        rows, scopes = pv.build_rows(self.snap, [], None, NOW)
        pv.source_status(rows, scopes, [], self.snap, None, NOW, {})
        text = rows["standing:p1"]["annotations"][-1]
        self.assertIn("Current PR and review states are unknown", text)
        self.assertIn("GitHub last verified: unknown", text)

    def test_atomic_publication_matches_brief_and_uses_existing_uuid(self):
        rows, scopes, _ = self.generate()
        first, _ = pv.plan(rows, scopes, [], NOW)
        old = stored(first)
        old[0]["uuid"] = str(uuid.uuid4())
        with mock.patch.object(pv.os, "replace", wraps=os.replace) as replace:
            pv.publish_contexts(rows, old)
        path = self.briefs / old[0]["uuid"] / "project-status.md"
        self.assertEqual(path.read_text(), rows["standing:p1"]["annotations"][-1][7:])
        replace.assert_called_once()
        self.assertEqual(replace.call_args.args[0].parent, path.parent)
        self.assertEqual(list(path.parent.iterdir()), [path])

    def test_atomic_replace_failure_keeps_old_file_and_cleans_temp(self):
        rows, _, _ = self.generate()
        pv.publish_contexts(rows, [])
        path = self.briefs / pv.row_uuid("standing:p1") / "project-status.md"
        old = path.read_text()
        rows["standing:p1"]["annotations"][-1] = "brief: Changed\n"
        with mock.patch.object(pv.os, "replace", side_effect=OSError("disk full")):
            with self.assertRaises(OSError):
                pv.publish_contexts(rows, [])
        self.assertEqual(path.read_text(), old)
        self.assertEqual(list(path.parent.iterdir()), [path])

    def test_symlink_and_invalid_uuid_paths_are_rejected(self):
        rows, _, _ = self.generate()
        target = self.root / "outside"
        target.mkdir()
        self.briefs.symlink_to(target, target_is_directory=True)
        with self.assertRaises(OSError):
            pv.publish_contexts(rows, [])
        self.assertEqual(list(target.iterdir()), [])
        self.briefs.unlink()
        with self.assertRaises(ValueError):
            pv.publish_contexts(rows, [{"view_key": "standing:p1", "uuid": "../outside"}])

    def main_patches(self, tasks=()):
        patches = [mock.patch.object(pv, "linear_key", return_value="fixture"),
                   mock.patch.object(pv, "read_linear", return_value=self.snap),
                   mock.patch.object(pv, "read_github", return_value=self.gh),
                   mock.patch.object(pv, "task_json", return_value=list(tasks)),
                   mock.patch.object(pv, "datetime", wraps=datetime),
                   mock.patch("sys.stdout"), mock.patch("sys.stderr"),
                   mock.patch.object(pv, "apply_associations", side_effect=lambda intents: {
                       "changed": len(intents), "skipped": 0}),
                   mock.patch.object(pv, "discover_buckets")]
        result = []
        for patch in patches:
            result.append(patch.start())
            self.addCleanup(patch.stop)
        result[4].now.return_value = NOW
        return result

    def test_dry_run_does_not_write_files_import_or_use_per_task_commands(self):
        patches = self.main_patches([handoff()])
        with mock.patch.object(pv, "apply") as apply, mock.patch.object(pv, "publish_contexts") as publish, \
                mock.patch.object(pv, "write_state") as write, mock.patch.object(pv, "apply_associations") as grouping:
            self.assertEqual(pv.main(["--dry-run"]), 0)
        apply.assert_not_called()
        publish.assert_not_called()
        write.assert_not_called()
        grouping.assert_not_called()
        patches[3].assert_called_once()
        self.assertEqual(list(self.root.iterdir()), [])

    def test_import_failure_does_not_publish_files_or_advance_state(self):
        rows, _, _ = self.generate()
        pv.publish_contexts(rows, [])
        path = self.briefs / pv.row_uuid("standing:p1") / "project-status.md"
        original = path.read_text()
        self.main_patches()
        with mock.patch.object(pv, "apply", side_effect=RuntimeError("import failed")), \
                mock.patch.object(pv, "publish_contexts") as publish, mock.patch.object(pv, "write_state") as state:
            self.assertEqual(pv.main([]), 1)
        self.assertEqual(path.read_text(), original)
        publish.assert_not_called()
        state.assert_not_called()

    def test_grouping_failure_does_not_publish_context_or_advance_state(self):
        self.main_patches([handoff()])
        with mock.patch.object(pv, "apply") as apply, \
                mock.patch.object(pv, "apply_associations", side_effect=RuntimeError("modify failed")), \
                mock.patch.object(pv, "publish_contexts") as publish, mock.patch.object(pv, "write_state") as state:
            self.assertEqual(pv.main([]), 1)
        apply.assert_called_once()
        self.assertTrue(all(t["tags"] == ["view"] for t in apply.call_args.args[0]))
        publish.assert_not_called()
        state.assert_not_called()

    def test_main_imports_only_views_and_modifies_associations_before_publication(self):
        patches = self.main_patches([handoff()])
        events = []
        def grouping(intents):
            events.append(("grouping", intents))
            return {"changed": len(intents), "skipped": 0}
        with mock.patch.object(pv, "apply", side_effect=lambda payload: events.append(("import", payload))), \
                mock.patch.object(pv, "apply_associations", side_effect=grouping), \
                mock.patch.object(pv, "publish_contexts", side_effect=lambda *args: events.append(("publish", args))):
            self.assertEqual(pv.main([]), 0)
        self.assertEqual([e[0] for e in events], ["import", "grouping", "publish"])
        self.assertEqual(len(events[0][1]), 1)
        self.assertEqual(events[0][1][0]["tags"], ["view"])
        self.assertNotEqual(events[0][1][0]["uuid"], handoff()["uuid"])
        self.assertEqual(events[1][1][0]["view_project"], "release-pipeline")
        patches[3].assert_called_once()
        self.assertTrue((self.state / "last-run.json").is_file())

    def test_total_linear_failure_preserves_headers_and_association(self):
        rows, scopes, sources = self.generate()
        headers, _ = pv.plan(rows, scopes, [], NOW)
        tasks = stored(headers) + [handoff(view_project="release-pipeline")]
        self.state.mkdir()
        (self.state / "last-run.json").write_text(json.dumps({"at": NOW.isoformat(), "sources": sources}))
        self.main_patches(tasks)
        with mock.patch.object(pv, "read_linear", side_effect=RuntimeError("offline")), \
                mock.patch.object(pv, "apply") as apply:
            self.assertEqual(pv.main([]), 0)
        payload = apply.call_args.args[0]
        self.assertEqual(len(payload), 1)
        self.assertEqual(payload[0]["uuid"], headers[0]["uuid"])
        self.assertIn("Current release checks", payload[0]["annotations"][-1]["description"])
        self.assertIn("Linear project unavailable", payload[0]["annotations"][-1]["description"])


class LinearRateLimitTests(unittest.TestCase):
    """No API calls: mock HTTP429 and the headers documented by Linear."""
    def setUp(self):
        folder = tempfile.TemporaryDirectory(prefix="project-rate-limit-")
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        patch = mock.patch.object(pv, "STATE_DIR", self.root / "state")
        patch.start()
        self.addCleanup(patch.stop)

    def error(self, headers=None):
        return pv.urllib.error.HTTPError("https://fixture.invalid/?token=secret-url", 429,
                                         "secret-error-body", headers or {}, None)

    def test_429_stops_later_queries_and_keeps_only_safe_diagnostics(self):
        headers = {"Retry-After": "120", "Authorization": "secret-key", "Set-Cookie": "secret-cookie",
                   "X-RateLimit-Complexity-Limit": "3000000", "X-RateLimit-Complexity-Remaining": "0",
                   "X-RateLimit-Requests-Reset": "secret-header-value"}
        client = pv.Linear("secret-api-key", on_rate_limit=pv.write_rate_limit)
        with mock.patch.object(pv, "datetime", wraps=datetime) as clock, \
                mock.patch.object(pv.urllib.request, "urlopen", side_effect=self.error(headers)) as request:
            clock.now.return_value = NOW
            for _ in range(3):
                with self.assertRaises(pv.LinearRateLimited) as error:
                    client.query("fixture")
                self.assertNotIn("secret", str(error.exception))
        request.assert_called_once()
        self.assertEqual(client.request_count, 1)
        stored = json.loads((pv.STATE_DIR / "linear-rate-limit.json").read_text())
        self.assertEqual(stored["retry_at"], (NOW + timedelta(seconds=120)).isoformat())
        self.assertEqual(stored["headers"], {"retry-after": "120", "x-ratelimit-complexity-limit": "3000000",
                                            "x-ratelimit-complexity-remaining": "0"})
        self.assertNotIn("secret", json.dumps(stored))

    def test_reset_milliseconds_retry_date_and_bounded_fallback(self):
        deadline = NOW + timedelta(hours=1)
        for name in ("X-RateLimit-Requests-Reset", "X-RateLimit-Complexity-Reset", "X-RateLimit-Endpoint-Requests-Reset"):
            record = pv.rate_limit_record({name: str(int(deadline.timestamp() * 1000))}, NOW)
            self.assertEqual(record["retry_at"], deadline.isoformat())
        record = pv.rate_limit_record({"Retry-After": deadline.strftime("%a, %d %b %Y %H:%M:%S GMT")}, NOW)
        self.assertEqual(record["retry_at"], deadline.isoformat())
        record = pv.rate_limit_record({"Retry-After": "secret-invalid", "X-RateLimit-Requests-Reset": "invalid"}, NOW)
        self.assertEqual(record["retry_at"], (NOW + timedelta(minutes=15)).isoformat())
        self.assertEqual(record["headers"], {})
        self.assertEqual(pv.rate_limit_record({"Retry-After": "9999999"}, NOW)["retry_at"],
                         (NOW + timedelta(hours=24)).isoformat())

    def test_shared_workers_do_not_start_queued_requests_after_first_429(self):
        client = pv.Linear("fixture")
        barrier, lock, calls = threading.Barrier(4), threading.Lock(), []
        def request(*args, **kwargs):
            with lock:
                calls.append(1)
                index = len(calls)
            barrier.wait(timeout=3)
            if index == 1:
                raise self.error({"Retry-After": "60"})
            self.assertTrue(client._stop.wait(timeout=3))
            return io.BytesIO(b'{"data":{"ok":true}}')
        with mock.patch.object(pv.urllib.request, "urlopen", side_effect=request):
            with pv.ThreadPoolExecutor(max_workers=4) as pool:
                futures = [pool.submit(client.query, "fixture") for _ in range(20)]
            good = 0
            for future in futures:
                try:
                    good += future.result()["ok"]
                except pv.LinearRateLimited:
                    pass
        self.assertEqual(good, 3)
        self.assertEqual(len(calls), 4)
        self.assertEqual(client.request_count, 4)

    def test_atomic_checkpoint_and_malformed_or_expired_state_fail_open(self):
        record = pv.rate_limit_record({}, NOW)
        with mock.patch.object(pv.os, "replace", wraps=os.replace) as replace:
            pv.write_rate_limit(record)
        target = pv.STATE_DIR / "linear-rate-limit.json"
        replace.assert_called_once()
        self.assertEqual(replace.call_args.args[0].parent, target.parent)
        self.assertEqual(list(target.parent.iterdir()), [target])
        self.assertEqual(pv.active_rate_limit({}, NOW), record)
        self.assertIsNone(pv.active_rate_limit({}, NOW + timedelta(minutes=16)))
        for malformed in ("{invalid", json.dumps({"status": 429, "retry_at": "invalid", "observed_at": "secret"})):
            target.write_text(malformed)
            self.assertIsNone(pv.active_rate_limit({}, NOW))
        target.write_text(json.dumps(record))
        with mock.patch.object(pv.os, "replace", side_effect=OSError("disk full")), mock.patch("sys.stderr"):
            pv.write_rate_limit(pv.rate_limit_record({"Retry-After": "1800"}, NOW))
        self.assertEqual(json.loads(target.read_text()), record)
        self.assertEqual(list(target.parent.iterdir()), [target])

    def test_seeded_cooldown_skips_credentials_and_api_until_deadline_then_resumes(self):
        pv.write_rate_limit(pv.rate_limit_record({}, NOW))
        with mock.patch.object(pv, "datetime", wraps=datetime) as clock, \
                mock.patch.object(pv, "task_json", return_value=[]), \
                mock.patch.object(pv, "linear_key", return_value="fixture") as key, \
                mock.patch.object(pv, "read_linear", return_value=snapshot()) as read, \
                mock.patch.object(pv, "discover_buckets"), \
                mock.patch.object(pv, "read_github", return_value=github()) as gh, \
                mock.patch.object(pv, "apply"), mock.patch.object(pv, "publish_contexts"), \
                mock.patch("sys.stdout"), mock.patch("sys.stderr"):
            clock.now.return_value = NOW + timedelta(minutes=1)
            pv.main([])
            key.assert_not_called()
            read.assert_not_called()
            gh.assert_not_called()
            summary = json.loads((pv.STATE_DIR / "last-run.json").read_text())
            self.assertEqual(summary["linear_requests"], 0)
            self.assertEqual(summary["linear_rate_limit"]["status"], 429)
            clock.now.return_value = NOW + timedelta(minutes=16)
            pv.main([])
            key.assert_called_once()
            read.assert_called_once()
            gh.assert_called_once()

    def test_dry_run_429_writes_no_checkpoint_or_other_state(self):
        def read(client, tasks):
            return client.query("fixture")
        with mock.patch.object(pv, "datetime", wraps=datetime) as clock, \
                mock.patch.object(pv, "task_json", return_value=[]), \
                mock.patch.object(pv, "linear_key", return_value="fixture"), \
                mock.patch.object(pv, "read_linear", side_effect=read), \
                mock.patch.object(pv.urllib.request, "urlopen", side_effect=self.error({"Retry-After": "60"})), \
                mock.patch("sys.stdout"), mock.patch("sys.stderr"):
            clock.now.return_value = NOW
            self.assertEqual(pv.main(["--dry-run"]), 0)
        self.assertEqual(list(self.root.iterdir()), [])


class SourcePaginationTests(unittest.TestCase):
    def test_failed_attached_pr_batch_is_bisected_and_healthy_refs_survive(self):
        refs = {f"loft-sh/tool#{n}" for n in range(1, 9)}
        unavailable = "loft-sh/tool#3"
        def reply(query):
            found = re.findall(r'p(\d+): repository\(owner: "([^"]+)", name: "([^"]+)"\) '
                               r'\{ pullRequest\(number: (\d+)\)', query)
            names = {f"{owner}/{repo}#{number}" for _, owner, repo, number in found}
            if unavailable in names:
                raise pv.GitHubUnreadable("HTTP 404")
            return {f"p{alias}": {"pullRequest": pr(f"{owner}/{repo}#{number}")}
                    for alias, owner, repo, number in found}
        with mock.patch.object(pv, "gh_graphql", side_effect=reply) as query:
            prs, missing = pv.read_attached_prs(refs)
        self.assertEqual(set(prs), refs - {unavailable})
        self.assertEqual(missing, {unavailable})
        self.assertEqual(query.call_count, 7)

    def test_failed_attached_pr_queries_have_a_finite_per_chunk_bound(self):
        refs = {f"loft-sh/tool#{n}" for n in range(1, 7)}
        with mock.patch.object(pv, "gh_graphql", side_effect=pv.GitHubUnreadable("HTTP 404")) as query, \
                mock.patch.object(pv, "GH_CHUNK", 4):
            prs, missing = pv.read_attached_prs(refs)
        self.assertEqual(prs, {})
        self.assertEqual(missing, refs)
        self.assertEqual(query.call_count, (2 * 4 - 1) + (2 * 2 - 1))

    def test_null_or_incomplete_attached_pr_reply_remains_unknown(self):
        refs = ["loft-sh/tool#1", "loft-sh/tool#2", "loft-sh/tool#3"]
        incomplete = pr(refs[1], state="MERGED", merged=1)
        incomplete["reviewRequests"]["pageInfo"]["hasNextPage"] = True
        data = {"p0": None, "p1": {"pullRequest": incomplete}, "p2": {"pullRequest": pr(refs[2])}}
        with mock.patch.object(pv, "gh_graphql", return_value=data) as query:
            with self.assertRaisesRegex(RuntimeError, "incomplete GitHub reply"):
                pv.read_attached_prs(set(refs))
        query.assert_called_once()

    def test_graphql_attachment_errors_classify_missing_and_fail_other_errors(self):
        for kind, message, soft in [("NOT_FOUND", "missing", True),
                                    ("FORBIDDEN", "access denied", True),
                                    ("FORBIDDEN", "rate limit exceeded", False),
                                    ("INTERNAL", "server error", False)]:
            error = {"type": kind, "path": ["p0"], "message": message}
            result = subprocess.CompletedProcess([], 1, json.dumps({"errors": [error]}), "gh: error")
            with self.subTest(kind=kind, message=message), mock.patch.object(pv.subprocess, "run", return_value=result):
                if soft:
                    self.assertEqual(pv.read_attached_prs({"loft-sh/tool#1"})[1], {"loft-sh/tool#1"})
                else:
                    with self.assertRaises(RuntimeError) as caught:
                        pv.read_attached_prs({"loft-sh/tool#1"})
                    self.assertNotIsInstance(caught.exception, pv.GitHubUnreadable)

    def test_global_viewer_or_own_pr_failure_still_fails_the_whole_github_source(self):
        for replies in ([RuntimeError("viewer unavailable")],
                        [{"viewer": {"login": "Piotr"}}, RuntimeError("own PRs unavailable")]):
            with mock.patch.object(pv, "gh_graphql", side_effect=replies), \
                    mock.patch.object(pv, "read_attached_prs") as attached:
                with self.assertRaises(RuntimeError):
                    pv.read_github({"loft-sh/tool#1"})
            attached.assert_not_called()

    def test_another_workspace_url_cannot_discover_or_claim_an_own_workspace_project(self):
        client = pv.Linear("fixture")
        own_issue = assigned("DEVOPS-50", "p3", "Own project")
        task = handoff(None, description="https://linear.app/another/issue/DEVOPS-50/title")
        with mock.patch.object(client, "pages", return_value=iter([])), \
                mock.patch.object(client, "query", return_value={"i0": own_issue}), \
                mock.patch.object(pv, "read_project") as read:
            snap = pv.read_linear(client, [task])
        self.assertEqual(snap["referenced"], [])
        self.assertEqual(snap["projects"], {})
        read.assert_not_called()

    def test_older_exact_handoff_reference_brings_its_project_into_the_same_refresh(self):
        client = pv.Linear("fixture")
        old = assigned("DEVOPS-50", "p3", "Historical release")
        old["state"] = {"name": "Done", "type": "completed"}
        linked = project("p3", "Historical release", [], led=False, update_days=500)
        task = handoff("DEVOPS-50")
        with mock.patch.object(client, "pages", return_value=iter([])), \
                mock.patch.object(client, "query", return_value={"i0": old}) as query, \
                mock.patch.object(pv, "read_project", return_value=linked) as read_project:
            snap = pv.read_linear(client, [task])
        self.assertEqual(snap["wanted"], ["p3"])
        self.assertEqual(snap["referenced"], [old])
        read_project.assert_called_once_with(client, "p3")
        self.assertIn('issue(id: "DEVOPS-50")', query.call_args.args[0])
        changes, resolved = pv.association_plan(snap, [task])
        self.assertEqual(changes[0]["view_project"], "historical-release")
        rows, _ = pv.build_rows(snap, resolved, github(), NOW)
        self.assertIn("standing:p3", rows)

    def test_reference_query_failure_preserves_metadata_without_guessing_from_prose(self):
        client = pv.Linear("fixture")
        task = handoff("DEVOPS-50", view_project="release-pipeline")
        with mock.patch.object(client, "pages", return_value=iter([])), \
                mock.patch.object(client, "query", side_effect=RuntimeError("offline")), mock.patch("sys.stderr"):
            snap = pv.read_linear(client, [task])
        self.assertTrue(snap["reference_failure"])
        self.assertEqual(pv.association_plan(snap, [task]), ([], [task]))
        prose = handoff(None, description="DEVOPS-50 relates to this release")
        with mock.patch.object(client, "query") as query:
            self.assertEqual(pv.read_referenced(client, pv.referenced_identifiers([prose])), [])
        query.assert_not_called()

    def test_reference_queries_are_batched_and_bounded(self):
        client = pv.Linear("fixture")
        with mock.patch.object(client, "query", return_value={}) as query:
            self.assertEqual(pv.read_referenced(client, {f"DEVOPS-{n}" for n in range(26)}), [])
        self.assertEqual(query.call_count, 2)
        self.assertEqual(query.call_args_list[0].args[0].count("issue(id:"), 25)
        with self.assertRaisesRegex(RuntimeError, "more than 200"):
            pv.read_referenced(client, {f"DEVOPS-{n}" for n in range(201)})

    def test_completed_history_failure_is_a_project_failure_not_empty_done(self):
        client = pv.Linear("fixture")
        first = {"project": {**project(), "issues": {"nodes": [],
                 "pageInfo": {"hasNextPage": False, "endCursor": None}}}}
        with mock.patch.object(client, "query", side_effect=[first, RuntimeError("history offline")]), \
                mock.patch.object(client, "pages", return_value=iter([])):
            with self.assertRaisesRegex(RuntimeError, "history offline"):
                pv.read_project(client, "p1")

    def test_linear_pages_fail_on_incomplete_read_or_missing_cursor(self):
        client = pv.Linear("fixture")
        page = {"nodes": [{"id": "one"}], "pageInfo": {"hasNextPage": True, "endCursor": "one"}}
        with mock.patch.object(client, "query", return_value={"projects": page}), mock.patch.object(pv, "PAGES", 2):
            with self.assertRaisesRegex(RuntimeError, "more than 2 pages"):
                list(client.pages("query", ["projects"]))

    def test_project_issues_and_milestones_are_both_paginated(self):
        client = pv.Linear("fixture")
        fields = project()
        fields.pop("issues")
        fields.pop("milestones")
        first = {"project": {**fields, "issues": {"nodes": [issue("DEVOPS-1")],
                 "pageInfo": {"hasNextPage": True, "endCursor": "issues-1"}}}}
        second = {"project": {**fields, "issues": {"nodes": [issue("DEVOPS-2")],
                  "pageInfo": {"hasNextPage": False, "endCursor": None}}}}
        milestones = [{"project": {"projectMilestones": {"nodes": [{"id": "m1", "name": "Pilot"}],
                       "pageInfo": {"hasNextPage": True, "endCursor": "milestone-1"}}}},
                      {"project": {"projectMilestones": {"nodes": [{"id": "m2", "name": "Release"}],
                       "pageInfo": {"hasNextPage": False, "endCursor": None}}}}]
        history = {"project": {"issues": {"nodes": [issue("DEVOPS-0", "Done", "completed", completed=60)],
                   "pageInfo": {"hasNextPage": False, "endCursor": None}}}}
        with mock.patch.object(client, "query", side_effect=[first, second, *milestones, history]) as query:
            result = pv.read_project(client, "p1")
        self.assertEqual([i["identifier"] for i in result["issues"]], ["DEVOPS-1", "DEVOPS-2", "DEVOPS-0"])
        self.assertEqual([m["name"] for m in result["milestones"]], ["Pilot", "Release"])
        self.assertEqual(query.call_args_list[1].args[1]["after"], "issues-1")
        self.assertEqual(query.call_args_list[3].args[1]["after"], "milestone-1")
        self.assertFalse(result["history_truncated"])
        self.assertIn('orderBy: updatedAt, includeArchived: true', query.call_args.args[0])
        self.assertEqual(query.call_args.args[1], {"id": "p1", "after": None})

    def test_issue_queries_limit_outer_pages_without_reducing_nested_completeness(self):
        self.assertIn("issues(first: 20, after: $after", pv.Q_PROJECT)
        self.assertIn("issues(first: 20, after: $after", pv.Q_COMPLETED)
        for query in (pv.Q_PROJECT, pv.Q_COMPLETED):
            self.assertIn("attachments(first: 100)", query)
            self.assertIn("pageInfo { hasNextPage endCursor }", query)
        self.assertIn("inverseRelations(first: 100)", pv.Q_PROJECT)
        for unused in ("inverseRelations", "assignee", "projectMilestone", "canceledAt", "state { name"):
            self.assertNotIn(unused, pv.Q_COMPLETED)
        self.assertEqual(pv.PROJECT_ISSUE_PAGES * pv.ISSUE_PAGE_SIZE, 500)
        self.assertEqual(pv.HISTORY_PAGES * pv.ISSUE_PAGE_SIZE, 100)
        self.assertEqual(pv.PAGES, 10)

    def test_completed_history_reads_five_pages_preserves_order_and_marks_limit(self):
        client = pv.Linear("fixture")
        for more_history in (False, True):
            with self.subTest(more_history=more_history):
                replies = []
                for page in range(5):
                    items = [issue(f"DEVOPS-{page * 20 + n}", "Done", "completed", completed=page * 20 + n)
                             for n in range(1, 21)]
                    replies.append({"project": {"issues": {"nodes": items, "pageInfo": {
                        "hasNextPage": page < 4 or more_history, "endCursor": f"history-{page + 1}"}}}})
                with mock.patch.object(client, "query", side_effect=replies) as query:
                    history, truncated = pv.read_completed(client, "p1")
                self.assertEqual(len(history), 100)
                self.assertEqual([i["identifier"] for i in history], [f"DEVOPS-{n}" for n in range(1, 101)])
                self.assertEqual(truncated, more_history)
                self.assertEqual(query.call_count, 5)
                self.assertEqual([c.args[1]["after"] for c in query.call_args_list],
                                 [None, "history-1", "history-2", "history-3", "history-4"])

    def test_current_project_issues_keep_all_500_with_25_small_pages(self):
        client = pv.Linear("fixture")
        replies = []
        for page in range(25):
            items = [issue(f"DEVOPS-{page * 20 + n}") for n in range(1, 21)]
            replies.append({"project": {**project(), "issues": {"nodes": items, "pageInfo": {
                "hasNextPage": page < 24, "endCursor": f"current-{page + 1}"}}}})
        with mock.patch.object(client, "query", side_effect=replies) as query, \
                mock.patch.object(client, "pages", return_value=iter([])), \
                mock.patch.object(pv, "read_completed", return_value=([], False)):
            result = pv.read_project(client, "p1")
        self.assertEqual(len(result["issues"]), 500)
        self.assertEqual(result["issues"][-1]["identifier"], "DEVOPS-500")
        self.assertEqual(query.call_count, 25)
        self.assertEqual(query.call_args.args[1]["after"], "current-24")

    def test_more_than_500_current_issues_fails_without_silently_truncating(self):
        client = pv.Linear("fixture")
        replies = [{"project": {**project(), "issues": {
            "nodes": [issue(f"DEVOPS-{page * 20 + n}") for n in range(1, 21)],
            "pageInfo": {"hasNextPage": True, "endCursor": f"current-{page + 1}"}}}}
            for page in range(25)]
        with mock.patch.object(client, "query", side_effect=replies) as query:
            with self.assertRaisesRegex(RuntimeError, "more than 500 current project issues"):
                pv.read_project(client, "p1")
        self.assertEqual(query.call_count, 25)

    def test_incomplete_issue_pages_need_valid_new_cursors(self):
        client = pv.Linear("fixture")
        for source in ("current", "history"):
            for cursor in (None, "", "repeat"):
                with self.subTest(source=source, cursor=cursor):
                    def reply(value):
                        connection = {"nodes": [issue("DEVOPS-1")],
                                      "pageInfo": {"hasNextPage": True, "endCursor": value}}
                        if value is None:
                            connection["pageInfo"].pop("endCursor")
                        return {"project": {**project(), "issues": connection}}
                    replies = [reply(cursor)] * (2 if cursor == "repeat" else 1)
                    with mock.patch.object(client, "query", side_effect=replies) as query:
                        with self.assertRaisesRegex(RuntimeError, "pagination cursor missing or repeated"):
                            (pv.read_project if source == "current" else pv.read_completed)(client, "p1")
                    self.assertEqual(query.call_count, len(replies))

    def test_interrupted_history_page_does_not_return_a_partial_completion_list(self):
        client = pv.Linear("fixture")
        first = {"project": {"issues": {"nodes": [issue("DEVOPS-1", "Done", "completed", completed=1)],
                 "pageInfo": {"hasNextPage": True, "endCursor": "next"}}}}
        with mock.patch.object(client, "query", side_effect=[first, RuntimeError("history page unavailable")]):
            with self.assertRaisesRegex(RuntimeError, "history page unavailable"):
                pv.read_completed(client, "p1")

    def test_truncated_attachment_or_blocker_connection_fails_closed(self):
        client = pv.Linear("fixture")
        for field in ("attachments", "inverseRelations"):
            item = issue("DEVOPS-1")
            item[field]["pageInfo"] = {"hasNextPage": True}
            value = {"project": {**project(), "issues": {"nodes": [item],
                     "pageInfo": {"hasNextPage": False, "endCursor": None}}}}
            with mock.patch.object(client, "query", return_value=value):
                with self.assertRaisesRegex(RuntimeError, "more than 100 " + field):
                    pv.read_project(client, "p1")

    def test_lean_completed_history_preserves_done_pr_proof_and_ownership(self):
        client = pv.Linear("fixture")
        ref = "loft-sh/tool#12"
        item = issue("DEVOPS-1", "Done", "completed", title="Verified historical delivery",
                     completed=60, prs=[pr(ref)["url"]])
        for field in ("inverseRelations", "assignee", "projectMilestone", "canceledAt"):
            item.pop(field)
        item["state"].pop("name")
        value = {"project": {"issues": {"nodes": [item], "pageInfo": {"hasNextPage": False, "endCursor": None}}}}
        with mock.patch.object(client, "query", return_value=value):
            history, truncated = pv.read_completed(client, "p1")
        self.assertFalse(truncated)
        proj = project(issues=history)
        snap = snapshot([proj])
        gh = github({ref: pr(ref, state="MERGED", merged=60)})
        rows, _ = pv.build_rows(snap, [], gh, NOW)
        brief = rows["standing:p1"]["annotations"][-1]
        self.assertIn("DEVOPS-1 Verified historical delivery", brief)
        self.assertIn("Linear completed 2026-09-12", brief)
        self.assertIn("GitHub merged 2026-09-12", brief)
        changes, _ = pv.association_plan(snap, [handoff(None, description=pr(ref)["url"])])
        self.assertEqual(changes[0]["view_project"], "release-pipeline")
        item["attachments"]["pageInfo"] = {"hasNextPage": True}
        with mock.patch.object(client, "query", return_value=value):
            with self.assertRaisesRegex(RuntimeError, "more than 100 attachments"):
                pv.read_completed(client, "p1")

    def test_github_partial_errors_cannot_establish_ownership(self):
        reply = mock.Mock(returncode=0, stdout=json.dumps({"data": {"p1": None}, "errors": [{"message": "denied"}]}),
                          stderr="")
        with mock.patch.object(pv.subprocess, "run", return_value=reply):
            with self.assertRaises(RuntimeError):
                pv.gh_graphql("query")

    def test_github_own_prs_paginate_and_attachment_reads_stay_batched(self):
        closed_page = {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": []}
        a, b = pr("loft-sh/tool#1"), pr("loft-sh/tool#2")
        own1 = {"viewer": {"pullRequests": {"nodes": [a],
                "pageInfo": {"hasNextPage": True, "endCursor": "next"}}}}
        own2 = {"viewer": {"pullRequests": {"nodes": [b],
                "pageInfo": {"hasNextPage": False, "endCursor": None}}}}
        refs = [f"loft-sh/tool#{n}" for n in range(3, 6)]
        attached = {f"p{i}": {"pullRequest": {**pr(ref), "reviewRequests": closed_page}}
                    for i, ref in enumerate(refs)}
        replies = [{"viewer": {"login": "Piotr"}}, own1, own2,
                   {"o0": {"login": "loft-sh", "teams": closed_page}}, attached]
        with mock.patch.object(pv, "gh_graphql", side_effect=replies) as query:
            result = pv.read_github(set(refs))
        self.assertEqual(set(result["mine"]), {"loft-sh/tool#1", "loft-sh/tool#2"})
        self.assertEqual(set(result["prs"]), set(refs))
        self.assertEqual(query.call_count, 5)
        self.assertIn('after: "next"', query.call_args_list[2].args[0])
        self.assertEqual(query.call_args.args[0].count("pullRequest(number:"), 3)


@unittest.skipUnless(shutil.which("task"), "task is not installed")
class TaskwarriorRoundtripTests(unittest.TestCase):
    def test_multiple_grouping_intents_use_one_final_export_and_exact_uuid_modifies(self):
        tasks = [handoff(uuid=str(uuid.uuid4())), handoff(uuid=str(uuid.uuid4()))]
        pv.apply(tasks)
        snap = snapshot([project(issues=[issue("DEVOPS-1")])])
        intents, _ = pv.association_plan(snap, self.plain_export())
        with mock.patch.object(pv, "task_json", wraps=pv.task_json) as export, \
                mock.patch.object(pv.subprocess, "run", wraps=subprocess.run) as run:
            self.assertEqual(pv.apply_associations(intents), {"changed": 2, "skipped": 0})
        export.assert_called_once()
        for task in tasks:
            self.assertIn("uuid:" + task["uuid"], export.call_args.args)
        commands = [c.args[0] for c in run.call_args_list if "modify" in c.args[0]]
        self.assertEqual(len(commands), 2)
        for command in commands:
            self.assertEqual(sum(arg.startswith("uuid:") for arg in command), 1)
        self.assertTrue(all(t["view_project"] == "release-pipeline" for t in self.plain_export()))

    def test_grouping_modify_preserves_user_notes_priority_and_dates_after_planning(self):
        original = handoff(description="Review 🌱", due="20261201T000000Z", custom="Keep this")
        pv.apply([original])
        snap = snapshot([project(issues=[issue("DEVOPS-1")])])
        intents, _ = pv.association_plan(snap, self.plain_export())
        latest = self.plain_export()[0]
        latest.update(priority="L", due="20261215T000000Z", custom="User's newer value")
        latest["tags"].append("user-added")
        latest["annotations"].append({"entry": "20261111T120000Z", "description": "New user note 🌱"})
        pv.apply([latest])
        before = self.plain_export()[0]
        with mock.patch.object(pv, "task_json", wraps=pv.task_json) as export, \
                mock.patch.object(pv.subprocess, "run", wraps=subprocess.run) as run:
            result = pv.apply_associations(intents)
        self.assertEqual(result, {"changed": 1, "skipped": 0})
        export.assert_called_once()
        modify = next(c.args[0] for c in run.call_args_list if "modify" in c.args[0])
        self.assertIn("uuid:" + original["uuid"], modify)
        self.assertIn("status:pending", modify)
        self.assertIn("rc.hooks=off", modify)
        self.assertIn("rc.confirmation=off", modify)
        self.assertIn("rc.bulk=0", modify)
        self.assertEqual(modify[modify.index("modify") + 1:], ["view_project:release-pipeline"])
        after = self.plain_export()[0]
        ignored = {"id", "urgency", "modified", "view_project"}
        self.assertEqual({k: v for k, v in after.items() if k not in ignored},
                         {k: v for k, v in before.items() if k not in ignored})
        self.assertEqual(after["view_project"], "release-pipeline")
        again, _ = pv.association_plan(snap, [after])
        self.assertEqual(again, [])
        with mock.patch.object(pv, "task_json") as export:
            self.assertEqual(pv.apply_associations(again), {"changed": 0, "skipped": 0})
        export.assert_not_called()

    def test_user_completion_category_or_evidence_edit_after_plan_wins(self):
        snap = snapshot([project(issues=[issue("DEVOPS-1")])])
        edits = [{"status": "completed", "end": "20261111T120000Z"},
                 {"project": "user-category"}, {"linear_issue_id": "DOC-999"},
                 {"description": "Changed source https://linear.app/loft/issue/DOC-999/new-source"},
                 {"view_project": "user-selected-project"}, {"tags": ["work"]},
                 {"annotations": [{"entry": "20261111T120000Z", "description": "https://github.com/loft-sh/tool/pull/999"}]}]
        for edit in edits:
            with self.subTest(edit=next(iter(edit))):
                original = handoff(uuid=str(uuid.uuid4()))
                pv.apply([original])
                before_plan = next(t for t in self.plain_export() if t["uuid"] == original["uuid"])
                intents, _ = pv.association_plan(snap, [before_plan])
                latest = {**before_plan, **edit}
                pv.apply([latest])
                before = next(t for t in self.plain_export() if t["uuid"] == original["uuid"])
                self.assertEqual(pv.apply_associations(intents), {"changed": 0, "skipped": 1})
                after = next(t for t in self.plain_export() if t["uuid"] == original["uuid"])
                self.assertEqual(after, before)

    def test_atomic_status_and_native_project_filters_guard_the_final_read_race(self):
        snap = snapshot([project(issues=[issue("DEVOPS-1")])])
        for edit in ({"status": "completed", "end": "20261111T120000Z"}, {"project": "new-category"}):
            with self.subTest(edit=next(iter(edit))):
                original = handoff(uuid=str(uuid.uuid4()))
                pv.apply([original])
                snapshot_task = next(t for t in self.plain_export() if t["uuid"] == original["uuid"])
                intents, _ = pv.association_plan(snap, [snapshot_task])
                real_export = pv.task_json
                def export_then_user_edit(*args):
                    tasks = real_export(*args)
                    pv.apply([{**tasks[0], **edit}])
                    return tasks
                with mock.patch.object(pv, "task_json", side_effect=export_then_user_edit) as export:
                    self.assertEqual(pv.apply_associations(intents), {"changed": 0, "skipped": 1})
                export.assert_called_once()
                after = next(t for t in self.plain_export() if t["uuid"] == original["uuid"])
                for field, value in edit.items():
                    self.assertEqual(after[field], value)
                self.assertNotIn("view_project", after)
                self.assertEqual(after["annotations"], original["annotations"])

    def test_future_wait_task_is_not_planned_despite_pending_in_export(self):
        future = pv.tw_time(datetime.now(UTC) + timedelta(days=365))
        original = handoff(status="waiting", wait=future)
        pv.apply([original])
        current = self.plain_export()
        snap = snapshot([project(issues=[issue("DEVOPS-1")])])
        intents, resolved = pv.association_plan(snap, current)
        # Taskwarrior 3 exports a future-wait task as pending plus a wait date.
        self.assertEqual(current[0]["status"], "pending")
        self.assertEqual(intents, [])
        self.assertEqual(resolved, current)
        self.assertEqual(pv.apply_associations(intents), {"changed": 0, "skipped": 0})
        after = self.plain_export()[0]
        self.assertEqual(after["status"], current[0]["status"])
        self.assertEqual(after["wait"], current[0]["wait"])
        self.assertEqual(after["annotations"], current[0]["annotations"])

    def test_incremental_structured_metadata_import_preserves_existing_header_fields(self):
        snap = snapshot([project(issues=[issue("DEVOPS-1", title="A clear activity title")])])
        rows, scopes = pv.build_rows(snap, [], github(), NOW)
        pv.source_status(rows, scopes, [], snap, github(), NOW, {})
        payload, _ = pv.plan(rows, scopes, [], NOW)
        legacy = payload[0]
        for field in pv.VIEW_METADATA:
            legacy.pop(field)
        legacy.update(custom="Keep this", due="20261201T000000Z")
        legacy["annotations"].insert(0, {"entry": "20261101T000000Z", "description": "Human context"})
        pv.apply([legacy])
        old = self.plain_export()
        changed, _ = pv.plan(rows, scopes, old, NOW)
        self.assertEqual(len(changed), 1)
        pv.apply(changed)
        exported = self.plain_export()
        for field in ("uuid", "description", "project", "tags", "entry", "annotations", "custom", "due"):
            self.assertEqual(exported[0][field], old[0][field])
        self.assertEqual(tuple(exported[0].get(field, "") for field in pv.VIEW_METADATA),
                         ("project", "Release pipeline", "In Progress", ""))
        self.assertNotIn("linear_issue_id", exported[0])
        self.assertEqual(pv.plan(rows, scopes, exported, NOW)[0], [])

    def test_non_bmp_unicode_brief_roundtrips_and_matches_the_canonical_file(self):
        proj = project(issues=[issue("DEVOPS-1", title="Grow 🌱 and ship 🚀; café")])
        snap = snapshot([proj])
        rows, scopes = pv.build_rows(snap, [], github(), NOW)
        pv.source_status(rows, scopes, [], snap, github(), NOW, {})
        payload, _ = pv.plan(rows, scopes, [], NOW)
        pv.apply(payload)
        exported = self.plain_export()
        header = next(t for t in exported if t["view_key"] == "standing:p1")
        annotation = next(a["description"][7:] for a in reversed(header["annotations"])
                          if a["description"].startswith("brief: "))
        self.assertIn("Grow 🌱 and ship 🚀; café", annotation)
        with mock.patch.object(pv, "BRIEFS_DIR", self.data.parent / "briefs"):
            pv.publish_contexts(rows, exported)
            canonical = pv.BRIEFS_DIR / header["uuid"] / "project-status.md"
            self.assertEqual(canonical.read_text(encoding="utf-8"), annotation)
        self.assertEqual(pv.plan(rows, scopes, exported, NOW)[0], [])

    def test_unresolved_marker_survives_plain_export_with_native_project_intact(self):
        original = handoff("DEVOPS-999", project="release-pipeline")
        pv.apply([original])
        snap = snapshot([project(issues=[issue("DEVOPS-1")])])
        changes, _ = pv.association_plan(snap, self.plain_export())
        self.assertEqual(changes[0]["view_project"], "!unassigned")
        pv.apply_associations(changes)
        exported = self.plain_export()[0]
        self.assertEqual(exported["view_project"], "!unassigned")
        self.assertEqual(exported["project"], "release-pipeline")
        self.assertEqual(exported["uuid"], original["uuid"])

    def setUp(self):
        folder = tempfile.TemporaryDirectory(prefix="project-view-task-")
        self.addCleanup(folder.cleanup)
        root = Path(folder.name)
        self.rc = root / "taskrc"
        self.data = root / "data"
        self.data.mkdir()
        self.rc.write_text(f"data.location={self.data}\nhooks=off\nconfirmation=off\n"
                           "recurrence=off\ncolor=off\nnews.version=3.3.0\n")
        for patch in (mock.patch.dict(os.environ, {"TASKRC": str(self.rc), "TASKDATA": str(self.data)}),
                      mock.patch.object(pv, "TASK_CMD", ["task", f"rc.data.location={self.data}"])):
            patch.start()
            self.addCleanup(patch.stop)

    def plain_export(self):
        reply = subprocess.run(["task", "rc.hooks=off", "rc.confirmation=off", "rc.verbose=nothing", "export"],
                               capture_output=True, text=True, timeout=20, check=False)
        self.assertEqual(reply.returncode, 0, reply.stderr)
        return json.loads(reply.stdout)

    def test_grouping_and_arbitrary_metadata_survive_plain_export_without_uda_config(self):
        original = handoff(due="20261201T000000Z", custom="keep this")
        pv.apply([original])
        snap = snapshot([project(issues=[issue("DEVOPS-1")])])
        changes, _ = pv.association_plan(snap, self.plain_export())
        self.assertEqual(len(changes), 1)
        pv.apply_associations(changes)
        exported = self.plain_export()[0]
        self.assertEqual(exported["view_project"], "release-pipeline")
        for key in ("uuid", "project", "entry", "due", "priority", "tags", "annotations", "custom"):
            self.assertEqual(exported[key], original[key])
        self.assertNotIn("uda.view_project", self.rc.read_text())

    def test_header_brief_uuid_and_source_row_identity_roundtrip_without_churn(self):
        snap = snapshot([project(issues=[issue("DEVOPS-1")])], [assigned()])
        rows, scopes = pv.build_rows(snap, [], github(), NOW)
        pv.source_status(rows, scopes, [], snap, github(), NOW, {})
        first, _ = pv.plan(rows, scopes, [], NOW)
        pv.apply(first)
        exported = self.plain_export()
        self.assertEqual({t["view_key"] for t in exported}, {"standing:p1", "issue:DEVOPS-1"})
        again, _ = pv.plan(rows, scopes, exported, NOW + timedelta(minutes=10))
        self.assertEqual(again, [])
        header = next(t for t in exported if t["view_key"] == "standing:p1")
        self.assertEqual(header["uuid"], pv.row_uuid("standing:p1"))
        self.assertTrue(header["annotations"][-1]["description"].startswith("brief: # Release pipeline"))


if __name__ == "__main__":
    unittest.main()
