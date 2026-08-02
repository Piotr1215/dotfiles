#!/usr/bin/env bash
set -euo pipefail

config="${1:-$HOME/dev/dotfiles/.config/tmuxinator/rag-eval.yml}"

ruby -ryaml -e '
  cfg = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
  abort "wrong session name" unless cfg["name"] == "rag-eval"
  abort "wrong root" unless cfg["root"] == "~/.claude"
  window = cfg.fetch("windows").fetch(0).fetch("evaluation")
  abort "wrong layout" unless window["layout"] == "main-vertical"
  panes = window.fetch("panes")
  abort "expected three panes" unless panes.length == 3
  abort "missing cockpit pane" unless panes[0].include?("__rag_eval_dashboard.sh cockpit")
  abort "missing resilient corpus tail" unless panes[1].include?("tail -F") && panes[1].include?("fromjson?")
  abort "missing active-run pane" unless panes[2].include?("__rag_eval_dashboard.sh active")
' "$config"

filter=$(ruby -ryaml -e '
  pane = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
    .fetch("windows").fetch(0).fetch("evaluation").fetch("panes").fetch(1)
  print pane.split(%q{--unbuffered \'}, 2).fetch(1).rpartition(%q{\'})[0]
' "$config")
sample='{"ts":"2026-08-02T10:20:30Z","comparison_type":"ab","winner":"treatment","margin":3,"attributed_to_context":true,"knob_id":"memory_enrich.query_shape","episode_id":"session:42","parse_ok":true}'
rendered=$(printf '%s\n' "$sample" | jq -Rrc "$filter")
[[ "$rendered" == *"TREATMENT"*"margin=3"*"memory_enrich.query_shape"*"ep=42"* ]]

echo "rag-eval tmuxinator contract: ok"
