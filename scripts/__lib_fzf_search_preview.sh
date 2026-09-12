#!/usr/bin/env bash

# __lib_fzf_search_preview.sh
# Backend-agnostic half of the fzf full-text pickers: turn a query into the
# literal strings worth marking, then mark them in a rendered preview and jump
# to the first one when it sits below the fold.
#
# Nothing here knows where the records came from. __linear_issue_viewer.sh
# feeds it glow-rendered markdown; a notmuch picker feeds it `notmuch show`
# output. Source it and pipe the rendered text through highlight_and_jump.
#
#   source ~/dev/dotfiles/scripts/__lib_fzf_search_preview.sh
#   mapfile -t terms < <(query_terms "$fzf_query")
#   render_the_thing | highlight_and_jump "${terms[@]}"
#
# The fold is taken from FZF_PREVIEW_LINES, which fzf sets for preview commands.

# Split an fzf or backend query into the literal strings worth marking up.
# Quoted phrases stay whole, fzf operators are stripped, negated terms are
# dropped because nothing in the preview should be marked for them.
query_terms() {
    local query="$1" token
    local -a terms=()

    while [[ "$query" =~ \"([^\"]+)\" ]]; do
        terms+=("${BASH_REMATCH[1]}")
        query="${query/\"${BASH_REMATCH[1]}\"/ }"
    done

    for token in $query; do
        [[ "$token" == !* ]] && continue
        token="${token#\'}"
        token="${token#^}"
        token="${token%\$}"
        (( ${#token} < 2 )) && continue
        terms+=("$token")
    done

    (( ${#terms[@]} > 0 )) && printf '%s\n' "${terms[@]}"
}

# Mark every search term in rendered preview text and, when the first one sits
# below the fold, drop the reader straight onto it. Reverse video (SGR 7/27)
# rather than a colour, because it toggles without resetting the styling the
# renderer has already emitted around it.
#
# Matching happens on an ANSI-stripped copy so a term is found even when the
# renderer wrapped codes around it; the substitution runs on the original so
# the renderer's colours survive.
highlight_and_jump() {
    perl -e '
        my @terms = @ARGV; @ARGV = ();
        my @out = <STDIN>;
        exit(print(@out) ? 0 : 0) unless @terms;

        my $re = join "|", map { quotemeta } @terms;
        $re = qr/$re/i;

        my $first;
        for my $i (0 .. $#out) {
            my $plain = $out[$i];
            $plain =~ s/\e\[[0-9;]*[a-zA-Z]//g;
            $first = $i if !defined $first && $plain =~ $re;
            $out[$i] =~ s/($re)/\e[7m$1\e[27m/g;
        }

        my $height = $ENV{FZF_PREVIEW_LINES} || 40;
        # Keep the heading (a renderer wraps a long subject or title over
        # several lines) so the jump never costs the reader the item they are
        # looking at.
        if (defined $first && $first > $height - 4 && @out > 3) {
            my $start = $first - 2 < 3 ? 3 : $first - 2;
            @out = (@out[0 .. 2], "  \e[2m . . .\e[22m\n", @out[$start .. $#out]);
        }
        print @out;
    ' -- "$@"
}
