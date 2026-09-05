#!/usr/bin/env python3
"""Build fuzzy-completion candidates from terminal scrollback."""

import argparse
import re
import sys
from dataclasses import dataclass


WORD_RE = re.compile(r"[A-Za-z0-9_./:@%+-]+")
OPEN_TO_CLOSE = {"(": ")", "[": "]", "{": "}"}
CLOSE_TO_OPEN = {value: key for key, value in OPEN_TO_CLOSE.items()}
QUOTE_CHARS = {'"', "'", "`"}

MAX_SOURCE_LINES = 20_000
MAX_WORDS = 15_000
MAX_PHRASES = 30_000
MAX_STRUCTURED = 5_000
MAX_LINES = 10_000
MAX_PHRASE_CHARS = 240


@dataclass(frozen=True)
class Candidate:
    kind: str
    text: str


def _append_unique(items, seen, value, limit):
    if not value or value in seen or len(items) >= limit:
        return
    seen.add(value)
    items.append(value)


def _quote_spans(line):
    spans = []
    for quote in QUOTE_CHARS:
        start = None
        escaped = False
        for index, char in enumerate(line):
            if char == quote and not escaped:
                if start is None:
                    start = index
                else:
                    spans.append((start, index + 1))
                    start = None
            escaped = char == "\\" and not escaped
            if char != "\\":
                escaped = False
    return spans


def _bracket_spans(line):
    spans = []
    stack = []
    for index, char in enumerate(line):
        if char in OPEN_TO_CLOSE:
            stack.append((char, index))
        elif char in CLOSE_TO_OPEN:
            if stack and stack[-1][0] == CLOSE_TO_OPEN[char]:
                _, start = stack.pop()
                spans.append((start, index + 1))
            else:
                stack.clear()
    return spans


def structured_spans(line):
    positions = sorted(set(_quote_spans(line) + _bracket_spans(line)))
    return [line[start:end] for start, end in positions]


def generate_candidates(text, max_phrase_words=6):
    source_lines = [line.replace("\t", " ").strip() for line in text.splitlines()]
    source_lines = [line for line in source_lines if line][-MAX_SOURCE_LINES:]
    source_lines.reverse()

    by_kind = {kind: [] for kind in ("word", "phrase", "structured", "line")}
    seen = {kind: set() for kind in by_kind}

    for line in source_lines:
        matches = list(WORD_RE.finditer(line))
        for match in matches:
            _append_unique(by_kind["word"], seen["word"], match.group(), MAX_WORDS)

        for start in range(len(matches)):
            stop = min(len(matches), start + max_phrase_words)
            for end in range(start + 2, stop + 1):
                phrase = line[matches[start].start() : matches[end - 1].end()]
                if len(phrase) <= MAX_PHRASE_CHARS:
                    _append_unique(
                        by_kind["phrase"], seen["phrase"], phrase, MAX_PHRASES
                    )

        for span in structured_spans(line):
            _append_unique(
                by_kind["structured"], seen["structured"], span, MAX_STRUCTURED
            )

        _append_unique(by_kind["line"], seen["line"], line, MAX_LINES)

    return [
        Candidate(kind, value)
        for kind in ("word", "phrase", "structured", "line")
        for value in by_kind[kind]
    ]


def main():
    parser = argparse.ArgumentParser(
        description="emit kind<TAB>text candidates from terminal scrollback"
    )
    parser.add_argument("--max-phrase-words", type=int, default=6)
    args = parser.parse_args()
    if args.max_phrase_words < 2:
        parser.error("--max-phrase-words must be at least 2")

    for candidate in generate_candidates(sys.stdin.read(), args.max_phrase_words):
        print(f"{candidate.kind}\t{candidate.text}")


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        sys.exit(0)
