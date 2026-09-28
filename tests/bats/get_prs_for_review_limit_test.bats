#!/usr/bin/env bats
# The review-requested search returned 128 open PRs against --limit 100 on
# 2026-09-28. Search order is unstable, so a different slice fell off every run
# and the sync marked those tasks done, then recreated them 15 minutes later.

SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/__get_prs_for_review.sh"

@test "every gh search prs call uses the 1000 result ceiling" {
	run bash -c "grep -A1 'gh search prs' '$SCRIPT' | grep -o -- '--limit [0-9]*' | sort -u"
	[ "$status" -eq 0 ]
	[ "$output" = "--limit 1000" ]
}
