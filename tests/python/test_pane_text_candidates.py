import importlib.util
import subprocess
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[2] / "scripts" / "__pane_text_candidates.py"
WIDGET = Path(__file__).parents[2] / ".zsh" / "pane-text-completion.zsh"


def load_module():
    spec = importlib.util.spec_from_file_location("pane_text_candidates", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PaneTextCandidatesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_module()

    def candidates(self, text):
        return self.module.generate_candidates(text)

    def texts(self, text, kind):
        return [item.text for item in self.candidates(text) if item.kind == kind]

    def test_adjacent_words_surface_as_searchable_phrases(self):
        phrases = self.texts("which: shell built-in command", "phrase")
        self.assertIn("shell built-in command", phrases)
        self.assertIn("built-in command", phrases)

    def test_phrases_never_cross_terminal_lines(self):
        phrases = self.texts("alpha beta\ngamma delta", "phrase")
        self.assertNotIn("beta gamma", phrases)
        self.assertEqual(phrases, ["gamma delta", "alpha beta"])

    def test_nearest_duplicate_word_wins(self):
        words = self.texts("alpha repeat\nrepeat omega", "word")
        self.assertEqual(words, ["repeat", "omega", "alpha"])

    def test_phrase_length_is_bounded(self):
        phrases = self.texts("one two three four five six seven", "phrase")
        self.assertIn("one two three four five six", phrases)
        self.assertNotIn("one two three four five six seven", phrases)

    def test_balanced_delimiters_surface_as_structured_spans(self):
        structured = self.texts('run "shell built-in command" (alpha beta)', "structured")
        self.assertIn('"shell built-in command"', structured)
        self.assertIn("(alpha beta)", structured)

    def test_full_lines_are_available_nearest_first(self):
        lines = self.texts("older line\n\nnewer\tline", "line")
        self.assertEqual(lines, ["newer line", "older line"])

    def test_cli_emits_hidden_kind_and_visible_text_columns(self):
        result = subprocess.run(
            ["python3", str(SCRIPT)],
            input="which: shell built-in command\n",
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertIn("phrase\tshell built-in command\n", result.stdout)

    def test_zsh_widget_replaces_prefix_with_selected_phrase(self):
        program = r'''
zle() { return 0 }
bindkey() { return 0 }
tmux() {
  [[ "$*" == "capture-pane -p -J -S -10000" ]] || return 1
  print -r -- "which: shell built-in command"
}
fc() { return 0 }
fzf() {
  local row
  while IFS= read -r row; do
    [[ "$row" == $'phrase\tshell built-in command' ]] && print -r -- "$row"
  done
  return 0
}
source "$WIDGET"
TMUX=1
LBUFFER="explain she"
fzf-pane-word
print -r -- "$LBUFFER"
'''
        result = subprocess.run(
            ["zsh", "-f", "-c", program],
            text=True,
            capture_output=True,
            env={"PATH": "/usr/bin:/bin", "WIDGET": str(WIDGET),
                 "PANE_TEXT_CANDIDATES": str(SCRIPT)},
            check=True,
        )
        self.assertEqual(result.stdout, "explain shell built-in command\n")

    def test_zsh_widget_also_completes_from_shell_history(self):
        program = r'''
zle() { return 0 }
bindkey() { return 0 }
tmux() { print -r -- "current pane words" }
fc() { print -r -- "historical cluster command" }
fzf() {
  local row
  while IFS= read -r row; do
    [[ "$row" == $'phrase\thistorical cluster command' ]] && print -r -- "$row"
  done
  return 0
}
source "$WIDGET"
TMUX=1
LBUFFER="explain hist"
fzf-pane-word
print -r -- "$LBUFFER"
'''
        result = subprocess.run(
            ["zsh", "-f", "-c", program],
            text=True,
            capture_output=True,
            env={"PATH": "/usr/bin:/bin", "WIDGET": str(WIDGET),
                 "PANE_TEXT_CANDIDATES": str(SCRIPT)},
            check=True,
        )
        self.assertEqual(result.stdout, "explain historical cluster command\n")

    def test_real_fzf_searches_the_visible_text_field(self):
        program = r'''
zle() { return 0 }
bindkey() { return 0 }
tmux() { print -r -- "unique-target" }
fc() { return 0 }
source "$WIDGET"
TMUX=1
LBUFFER="explain uni"
fzf-pane-word
print -r -- "$LBUFFER"
'''
        result = subprocess.run(
            ["zsh", "-f", "-c", program],
            text=True,
            capture_output=True,
            env={"PATH": "/usr/local/bin:/usr/bin:/bin",
                 "FZF_DEFAULT_OPTS": "--filter=^unique-target$",
                 "WIDGET": str(WIDGET), "PANE_TEXT_CANDIDATES": str(SCRIPT)},
            check=True,
        )
        self.assertEqual(result.stdout, "explain unique-target\n")


if __name__ == "__main__":
    unittest.main()
