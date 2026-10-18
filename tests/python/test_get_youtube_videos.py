import json
import os
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

SCRIPT = Path(__file__).parents[2] / "scripts" / "__get_youtube_videos.py"
KEY = "SECRETKEY123"

# A stand-in for the API client. The script does its work at import time, so it
# runs as a subprocess with this package first on its path. Every call is
# logged, and a video with no canned comments fails the way the real API does:
# an HttpError whose message carries the request url, key included.
ERRORS = '''
class HttpError(Exception):
    def __init__(self, status, reason, uri):
        self.resp = type("Resp", (), {"status": status, "reason": "Forbidden"})()
        self.error_details = [{"reason": reason}]
        super().__init__(f"<HttpError {status} when requesting {uri} returned {reason!r}>")
'''

DISCOVERY = '''
import json, os
from googleapiclient.errors import HttpError

FIXTURE = json.load(open(os.environ["FAKE_YT_FIXTURE"]))

class Request:
    def __init__(self, resource, kwargs, key):
        self.resource, self.kwargs, self.key = resource, kwargs, key

    def execute(self):
        with open(os.environ["FAKE_YT_LOG"], "a") as log:
            log.write(json.dumps({"resource": self.resource, **self.kwargs}) + "\\n")
        if self.resource == "commentThreads":
            vid = self.kwargs["videoId"]
            if vid not in FIXTURE["comments"]:
                raise HttpError(403, "commentsDisabled",
                    f"https://youtube.googleapis.com/youtube/v3/commentThreads?videoId={vid}&key={self.key}")
            return FIXTURE["comments"][vid]
        return FIXTURE[self.resource]

class Resource:
    def __init__(self, name, key):
        self.name, self.key = name, key

    def list(self, **kwargs):
        return Request(self.name, kwargs, self.key)

class Client:
    def __init__(self, key):
        self.key = key

    def __getattr__(self, name):
        return lambda: Resource(name, self.key)

def build(service, version, developerKey=None):
    return Client(developerKey)
'''


def video(vid, duration, published):
    return {
        "id": vid,
        "snippet": {"title": f"title {vid}", "publishedAt": f"{published}T10:00:00Z", "description": "d"},
        "contentDetails": {"duration": duration},
        "statistics": {"viewCount": "1234", "likeCount": "5", "commentCount": "2"},
    }


FIXTURE = {
    "playlistItems": {"items": [{"contentDetails": {"videoId": "v1"}}, {"contentDetails": {"videoId": "s1"}}]},
    "videos": {"items": [video("v1", "PT1H2M3S", "2026-01-01"), video("s1", "PT45S", "2026-02-01")]},
    "comments": {
        "s1": {"items": [{
            "snippet": {
                "topLevelComment": {"snippet": {"textDisplay": "nice &amp; short", "authorDisplayName": "@a", "likeCount": 3}},
                "totalReplyCount": 0,
            },
        }]},
    },
}


class JsonListingTest(unittest.TestCase):
    """ddgx's alt-v reads --json from stdout and keeps stderr shut."""

    def setUp(self):
        tmp = TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        pkg = root / "fake" / "googleapiclient"
        pkg.mkdir(parents=True)
        (pkg / "__init__.py").write_text("")
        (pkg / "errors.py").write_text(ERRORS)
        (pkg / "discovery.py").write_text(DISCOVERY)
        (root / "fake" / "prettytable.py").write_text("class PrettyTable:\n    pass\n")
        fixture = root / "fixture.json"
        fixture.write_text(json.dumps(FIXTURE))
        self.log = root / "calls.jsonl"
        env = dict(os.environ, PYTHONPATH=str(root / "fake"), FAKE_YT_FIXTURE=str(fixture),
                   FAKE_YT_LOG=str(self.log), YOUTUBE_API_KEY=KEY, YOUTUBE_CHANNEL_ID="UCabcdef")
        self.run_ = subprocess.run([sys.executable, str(SCRIPT), "--json", "--comments"],
                                   env=env, capture_output=True, text=True, timeout=30)

    def calls(self, resource):
        lines = self.log.read_text().splitlines()
        return [c for c in map(json.loads, lines) if c["resource"] == resource]

    def test_stdout_is_one_list_newest_first(self):
        self.assertEqual(self.run_.returncode, 0, self.run_.stderr)
        out = json.loads(self.run_.stdout)
        self.assertEqual([v["id"] for v in out], ["s1", "v1"])
        self.assertEqual([v["short"] for v in out], [True, False])
        self.assertEqual([v["duration"] for v in out], [45, 3723])
        self.assertEqual(out[1]["url"], "https://www.youtube.com/watch?v=v1")
        self.assertEqual(out[0]["comments"][0]["text"], "nice & short")

    def test_lists_the_uploads_playlist_not_search(self):
        # search.list drops videos between calls and costs 100 units a page.
        self.assertEqual([c["playlistId"] for c in self.calls("playlistItems")], ["UUabcdef"])
        self.assertEqual(self.calls("search"), [])

    def test_a_comment_error_names_the_reason_and_never_the_key(self):
        self.assertIn("No comments for v1: HTTP 403 commentsDisabled", self.run_.stderr)
        self.assertNotIn(KEY, self.run_.stderr)
        self.assertNotIn(KEY, self.run_.stdout)
        self.assertEqual(json.loads(self.run_.stdout)[1]["comments"], [])


if __name__ == "__main__":
    unittest.main()
