"""Link extraction behind the tmux M-u pane link picker."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("pane_urls", ROOT / "scripts" / "__tmux_pane_urls.py")
pane_urls = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pane_urls)
extract = pane_urls.extract_urls


def test_newest_first_and_deduped():
    text = "old https://a.io/1\nmid https://b.io/2\nnew https://a.io/1\n"
    assert extract(text) == ["https://a.io/1", "https://b.io/2"]


def test_trailing_prose_punctuation_is_dropped():
    text = 'see https://a.io/x. or (https://b.io/y?q=1&r=2), "https://c.io/z"!\n'
    assert sorted(extract(text)) == ["https://a.io/x", "https://b.io/y?q=1&r=2", "https://c.io/z"]


def test_balanced_parens_inside_url_are_kept():
    assert extract("https://en.wikipedia.org/wiki/Foo_(bar)\n") == ["https://en.wikipedia.org/wiki/Foo_(bar)"]


def test_markdown_and_angle_links():
    text = "[docs](https://a.io/docs) <https://b.io/c>\n"
    assert sorted(extract(text)) == ["https://a.io/docs", "https://b.io/c"]


def test_colour_codes_do_not_leak_into_urls():
    assert extract("\x1b[34mhttps://a.io/blue\x1b[0m tail\n") == ["https://a.io/blue"]


def test_osc8_hidden_hyperlink_target_is_found():
    text = "\x1b]8;;https://hidden.io/pr/7\x1b\\PR #7\x1b]8;;\x1b\\ done\n"
    assert extract(text) == ["https://hidden.io/pr/7"]


def test_osc8_with_bel_terminator_and_id_param():
    text = "\x1b]8;id=1;https://bel.io/x\x07label\x1b]8;;\x07\n"
    assert extract(text) == ["https://bel.io/x"]


def test_no_links_gives_empty_list():
    assert extract("nothing here, not even http:/broken\n") == []


def test_backslash_ends_a_url():
    text = r"printf 'https://a.io/x\e\\label https://b.io/y).\n'" + "\n"
    assert sorted(extract(text)) == ["https://a.io/x", "https://b.io/y"]


def test_display_truncated_links_are_dropped():
    text = "plain https://githu…) and https://example.com/os... cut, https://ok.io/x...\n"
    assert extract(text) == []


def test_osc8_targets_get_the_same_cleanup():
    text = ("\x1b]8;id=1;https://githu…,\x1b\\https://githu…,\x1b]8;;\x1b\\ "
            "\x1b]8;id=2;https://ok.io/a).\x1b\\https://ok.io/a).\x1b]8;;\x1b\\\n")
    assert extract(text) == ["https://ok.io/a"]
