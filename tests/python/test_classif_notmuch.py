"""__classif_notmuch.py against the real classif library (found on PATH, as the
script finds it), a fake Ollama and a temp notmuch database. No model and no
network."""
import email.utils
import importlib.machinery
import importlib.util
import io
import json
import os
import shutil
import subprocess
import tempfile
import threading
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "__classif_notmuch.py"
DEAD = "127.0.0.1:1"
SURE_NO = [("No", -0.01), ("Yes", -5.0)]
YES = [("Yes", -0.05), ("No", -3.0)]


def load():
    loader = importlib.machinery.SourceFileLoader("classif_notmuch", str(SCRIPT))
    spec = importlib.util.spec_from_loader("classif_notmuch", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class GateOllama:
    """Answers /api/ps with the loaded models and /api/chat by the chunk it
    is asked about."""

    def __init__(self, replies, loaded=({"name": "llama3.2:3b", "model": "llama3.2:3b", "context_length": 2048},)):
        self.replies, self.loaded, self.requests = replies, list(loaded), []
        fake = self

        class H(BaseHTTPRequestHandler):
            def reply(self, body):
                data = json.dumps(body).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self):
                self.reply({"models": fake.loaded})

            def do_POST(self):
                req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                if self.path == "/api/generate":
                    return self.reply({"done": True})
                fake.requests.append(req)
                user = req["messages"][1]["content"]
                top = fake.replies(user)
                self.reply({"done": True, "logprobs": [{"top_logprobs": [
                    {"token": t, "logprob": lp} for t, lp in top]}]})

            def log_message(self, *a):
                pass

        self.srv = HTTPServer(("127.0.0.1", 0), H)
        self.srv.daemon_threads = True
        self.host = f"127.0.0.1:{self.srv.server_port}"
        threading.Thread(target=self.srv.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True).start()

    def close(self):
        self.srv.shutdown()


def _mail(root, name, frm, subject, body, age, html=False, reply_to=None):
    ctype = "text/html" if html else "text/plain"
    (root / "cur" / f"{name}:2,").write_text(
        f"From: {frm}\nTo: test@example.com\nSubject: {subject}\nMessage-ID: <{name}@example.com>\n"
        + (f"In-Reply-To: <{reply_to}@example.com>\nReferences: <{reply_to}@example.com>\n" if reply_to else "") +
        f"Date: {email.utils.formatdate(time.time() - age)}\nContent-Type: {ctype}; charset=utf-8\n\n{body}\n")


@unittest.skipUnless(shutil.which("notmuch"), "notmuch not installed")
@unittest.skipUnless(shutil.which("classif"), "classif not on PATH")
class NotmuchTests(unittest.TestCase):
    """__classif_notmuch.py inside notmuch's post-new hook: every spec's yes
    becomes a classif/<tag>, a mail every spec answered gets classif/scored, and
    nothing a host could not score is tagged."""

    def setUp(self):
        self.sf = load()
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        (self.tmp / "specs").mkdir()
        self.log = self.tmp / "log.jsonl"
        env = mock.patch.dict(os.environ, {
            "CLASSIF_DIR": str(self.tmp / "specs"), "CLASSIF_LOG": str(self.log),
            "CLASSIF_CALIBRATION": "/nonexistent", "CLASSIF": "1"})
        env.start()
        self.addCleanup(env.stop)
        for name, q in (("email-bulk", "newsletter?"), ("email-action", "action from me?")):
            (self.tmp / "specs" / f"{name}.json").write_text(json.dumps(
                {"question": f"Is it {q}", "text": "From: {from}\nSubject: {subject}\n\n{body}",
                 "fields": {"from": 200, "subject": 200, "body": 1500}, "collapse": ["from", "subject"],
                 "labels": ["yes", "no"], "model": "llama3.2:3b", "num_ctx": 2048, "threshold": {}}))
        self.maildir = self.tmp / "mail"
        for d in ("cur", "new", "tmp"):
            (self.maildir / d).mkdir(parents=True)
        _mail(self.maildir, "digest", "Stack <d@stack.io>", "Issue 212", "This week in the stack. Unsubscribe.", 300)
        _mail(self.maildir, "ask", "Anna <a@example.org>", "Review my PR?", "Could you review the chart PR by Thursday?", 200)
        _mail(self.maildir, "odd", "Bot <b@x.io>", "odd", "<p>garbled <b>html</b> only</p>", 100, html=True)
        cfg = self.tmp / "notmuch-config"
        cfg.write_text(f"[database]\npath={self.maildir}\n[new]\ntags=unread;inbox\n"
                       "[user]\nname=T\nprimary_email=test@example.com\n")
        os.environ["NOTMUCH_CONFIG"] = str(cfg)
        self.addCleanup(os.environ.pop, "NOTMUCH_CONFIG", None)
        subprocess.run(["notmuch", "new", "--quiet"], check=True, capture_output=True)

    def serve(self, replies):
        fake = GateOllama(replies)
        self.addCleanup(fake.close)
        os.environ["CLASSIF_HOSTS"] = fake.host
        return fake

    def answer(self, user):
        if "garbled html only" in user:
            return [("Maybe", -0.05), ("No", -3.0)]
        bulk = "Unsubscribe" in user
        if "newsletter?" in user:
            return YES if bulk else SURE_NO
        return SURE_NO if bulk else YES

    def rows(self):
        return [json.loads(l) for l in self.log.read_text().splitlines()] if self.log.exists() else []

    def tags(self, name):
        out = subprocess.run(["notmuch", "search", "--output=tags", f"id:{name}@example.com"],
                             capture_output=True, text=True, check=True).stdout
        return sorted(t for t in out.split() if t.startswith("classif/"))

    def run_mail(self, *extra):
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            return self.sf.mail("email-bulk=bulk", "email-action=action", *extra)

    def test_each_yes_becomes_a_tag_and_answered_mail_is_marked_scored(self):
        self.serve(self.answer)
        self.assertEqual(self.run_mail(), 0)
        self.assertEqual(self.tags("digest"), ["classif/bulk", "classif/scored"])
        self.assertEqual(self.tags("ask"), ["classif/action", "classif/scored"])
        self.assertEqual(self.tags("odd"), ["classif/scored"])
        rows = self.rows()
        self.assertEqual((len(rows), {(r["hook"], r["channel"]) for r in rows}), (6, {("notmuch", "mail")}))
        self.assertEqual({r["key"] for r in rows if r["decision"] == "unscored"}, {"odd"})

    def test_a_reply_inside_a_thread_is_scored_on_its_own_text(self):
        _mail(self.maildir, "re", "Anna <a@example.org>", "Re: Review my PR?", "Unsubscribe me from this thread.", 50,
              reply_to="ask")
        subprocess.run(["notmuch", "new", "--quiet"], check=True, capture_output=True)
        self.serve(self.answer)
        self.assertEqual(self.run_mail(), 0)
        self.assertEqual(self.tags("re"), ["classif/bulk", "classif/scored"])
        self.assertEqual(self.tags("ask"), ["classif/action", "classif/scored"])

    def test_a_mail_notmuch_cannot_show_is_skipped_and_the_rest_are_scored(self):
        real = self.sf._notmuch
        self.sf._notmuch = lambda *a: "[]" if a[0] == "show" and "odd@" in a[-1] else real(*a)
        self.addCleanup(setattr, self.sf, "_notmuch", real)
        self.serve(self.answer)
        self.assertEqual(self.run_mail(), 0)
        self.assertEqual((self.tags("odd"), self.tags("ask")), ([], ["classif/action", "classif/scored"]))

    def test_an_unsure_answer_gets_its_own_tag_instead_of_the_yes_tag(self):
        spec = self.tmp / "specs" / "email-action.json"
        spec.write_text(json.dumps({**json.loads(spec.read_text()), "min_p": 0.8}))
        self.serve(lambda user: [("Yes", -0.36), ("No", -1.2)] if "action from me?" in user and "chart PR" in user
                   else self.answer(user))
        self.run_mail()
        self.assertEqual(self.tags("ask"), ["classif/action-unsure", "classif/scored"])
        self.assertEqual(self.tags("digest"), ["classif/bulk", "classif/scored"])

    def test_an_html_only_mail_is_scored_on_its_text(self):
        fake = self.serve(self.answer)
        self.run_mail()
        odd = [q["messages"][1]["content"] for q in fake.requests if "garbled" in q["messages"][1]["content"]]
        self.assertTrue(odd and all("<b>" not in u for u in odd))

    def test_a_second_run_scores_nothing_new(self):
        fake = self.serve(self.answer)
        self.run_mail()
        n = len(fake.requests)
        self.run_mail()
        self.assertEqual(len(fake.requests), n)

    def test_limit_takes_the_newest_mail_first(self):
        self.serve(self.answer)
        self.run_mail("--limit", "1")
        self.assertEqual([self.tags(m) != [] for m in ("digest", "ask", "odd")], [False, False, True])

    def test_a_mail_the_host_failed_on_stays_for_the_next_run(self):
        def flaky(user):
            if "review the chart PR" in user:
                raise ConnectionError("model crashed")
            return self.answer(user)
        self.serve(flaky)
        self.run_mail()
        self.assertEqual((self.tags("ask"), self.tags("digest")), ([], ["classif/bulk", "classif/scored"]))

    def test_no_host_tags_nothing_and_still_exits_0(self):
        os.environ["CLASSIF_HOSTS"] = DEAD
        self.assertEqual(self.run_mail(), 0)
        self.assertEqual([self.tags(m) for m in ("digest", "ask", "odd")], [[], [], []])

    def test_a_pause_asks_nothing(self):
        fake = self.serve(self.answer)
        with redirect_stdout(io.StringIO()):
            self.sf._load_classif().pause()
        self.assertEqual(self.run_mail(), 0)
        self.assertEqual((fake.requests, self.tags("digest")), ([], []))

    def test_classif_0_asks_nothing(self):
        fake = self.serve(self.answer)
        os.environ["CLASSIF"] = "0"
        self.assertEqual(self.run_mail(), 0)
        self.assertEqual((fake.requests, self.tags("digest")), ([], []))

    def test_classif_missing_from_path_is_a_one_line_error_and_exit_0(self):
        err = io.StringIO()
        with mock.patch.dict(os.environ, {"PATH": "/nonexistent"}), redirect_stderr(err):
            self.assertEqual(self.sf.mail("email-bulk=bulk"), 0)
        self.assertEqual(err.getvalue(), "classif-notmuch: classif not on PATH\n")


if __name__ == "__main__":
    unittest.main()
