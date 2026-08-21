#!/usr/bin/env python3
"""Vimium C's omnibox ranking, ported from the extension's own source.

Read out of Vimium C 2.12.2 as installed, background/completion_utils.js for
RankingUtils (minified to `t.cr`, `t.nr`, `ComputeRecency`, `ComputeRelevancy`)
and background/completion.js for the two globals it depends on, set per query
as `o.vr(3 * terms.length || .01)` and `o.Jr(Date.now() - 18144e5)`.

Why port it rather than let fzf match. fzf scores a scattered subsequence, so
"triage" matches "Ginkgo E2E: conTaineR snapshot And restore" and a two word
query pulls back a hundred rows containing neither word. Vimium C requires
every term as a whole substring, then ranks by how much of the string the query
covers, with a word boundary bonus and a recency term. That is the difference
the picker was missing.

The algorithm in the extension's own terms:

  matches()          every query term must be a substring of the shortened url
                     or of the title. Smart case: an all lowercase term matches
                     case insensitively, a term carrying a capital does not.
  word_relevancy()   per term and per string, boost starts at 1, +1 when the
                     term starts on a word boundary, +1 more when it is a whole
                     word. Boosts are summed, divided by 3 * term count, then
                     scaled by the share of the string the matches cover. Url
                     and title score separately; the title wins outright when it
                     scores higher, otherwise the two are averaged.
  recency()          quadratic over a 21 day window: 0.667 for a page seen just
                     now, 0 for anything older than the window.
  relevancy()        word relevancy alone once it already beats recency, the
                     average of the two otherwise.

History is scored with relevancy(), bookmarks with word_relevancy() alone,
which is what the extension does: a bookmark has no visit time to be recent
about.
"""

import re

# Three is the largest boost a single term can earn, so 3 * term count
# normalises the summed boosts into 0..1. The 0.01 floor is the extension's
# guard against an empty query.
MAX_TERM_BOOST = 3
EMPTY_QUERY_BOOST = 0.01

# 18144e5 milliseconds, the window ComputeRecency scores within.
RECENCY_WINDOW_MS = 1814400000

# The two constants ComputeRecency multiplies and clamps by.
RECENCY_PEAK = 0.666667
RECENCY_CLAMP = 0.666446

# The clock skew slack ComputeRecency allows before it gives up and returns 0.
RECENCY_SLACK = 1.000165


# `t.qr` returns how many characters of scheme to drop, `t.shortenUrl` slices
# them off and takes one trailing slash with it. Ranking runs against this, not
# the raw url, so "https://" cannot inflate the coverage of every row equally.
def shorten_url(url):
    head = url[:8].lower()
    if head.startswith("http://"):
        cut = 7
    elif head == "https://":
        cut = 8
    else:
        return url
    if cut >= len(url):
        return url
    end = len(url)
    if url.endswith("/") and not url.endswith("://"):
        end -= 1
    return url[cut:end]


# `x = (e, t) => e < t ? e / t : t / e`: the share of the string the query
# covers, so a term buried in a long title scores below the same term in a
# short one.
def coverage(matched, length):
    if not length or not matched:
        return 0.0
    return matched / length if matched < length else length / matched


class Ranker:
    """One query's compiled terms. Reused across every row being scored."""

    def __init__(self, terms, now_ms):
        self.terms = [term for term in terms if term]
        self._plain = []
        self._prefix = []
        self._whole = []
        for term in self.terms:
            # `term !== term.toUpperCase() && term.toLowerCase() === term`:
            # a term carrying a capital is matched case sensitively, which is
            # how "DEVOPS" narrows without also hitting devops in a url.
            smart_case = term != term.upper() and term.lower() == term
            flags = re.IGNORECASE if smart_case else 0
            escaped = re.escape(term)
            self._plain.append(re.compile(escaped, flags))
            self._prefix.append(re.compile(r"\b" + escaped, flags))
            self._whole.append(re.compile(r"\b" + escaped + r"\b", flags))
        self._max_boost = MAX_TERM_BOOST * len(self.terms) or EMPTY_QUERY_BOOST
        self._recency_base = now_ms - RECENCY_WINDOW_MS

    # Every term has to land somewhere, in the url or in the title. This is the
    # filter; nothing that fails it is scored at all.
    def matches(self, text, title):
        for pattern in self._plain:
            if not pattern.search(text) and not pattern.search(title):
                return False
        return True

    # The same test against one string instead of two, for callers holding a
    # corpus large enough that halving the searches is worth a separate entry
    # point. Passing a raw url where matches() would see the shortened one only
    # ever widens the result, so this is safe as a prefilter ahead of it.
    def matches_in(self, haystack):
        for pattern in self._plain:
            if not pattern.search(haystack):
                return False
        return True

    # Returns the term's boost and how many characters of the string it covers.
    # The boost floor of 1 is the extension's: a term that never appears still
    # contributes, which keeps a two term query from collapsing to the score of
    # whichever term happened to hit.
    def _term_stats(self, index, text):
        occurrences = len(self._plain[index].split(text)) - 1
        boost = 1
        if self._prefix[index].search(text):
            boost = 2
            if self._whole[index].search(text):
                boost = 3
        return boost, occurrences * len(self.terms[index])

    def word_relevancy(self, text, title):
        url_boost = url_chars = title_boost = title_chars = 0
        for index in range(len(self.terms)):
            boost, chars = self._term_stats(index, text)
            url_boost += boost
            url_chars += chars
            if title:
                boost, chars = self._term_stats(index, title)
                title_boost += boost
                title_chars += chars
        url_score = url_boost / self._max_boost * coverage(url_chars, len(text))
        if title_chars == 0:
            return url_score / 2 if title else url_score
        title_score = title_boost / self._max_boost * coverage(title_chars, len(title))
        if url_score < title_score:
            return title_score
        return (url_score + title_score) / 2

    def recency(self, when_ms):
        age = (when_ms - self._recency_base) / RECENCY_WINDOW_MS
        if age < 0:
            return 0.0
        if age < 1:
            return age * age * RECENCY_PEAK
        if age < RECENCY_SLACK:
            return RECENCY_CLAMP
        return 0.0

    def relevancy(self, text, title, when_ms):
        recent = self.recency(when_ms)
        relevant = self.word_relevancy(text, title)
        return relevant if recent <= relevant else (relevant + recent) / 2
