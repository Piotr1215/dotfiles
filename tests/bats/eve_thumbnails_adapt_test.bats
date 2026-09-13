#!/usr/bin/env bats

# eve-preview-manager keeps one absolute rectangle per character and rewrites
# them itself, so the row of previews placed on the single 4k desk (99 percent
# of the time) lands off-screen on the laptop desk. __eve_thumbnails_adapt.sh
# gives each character a slot and recomputes the slot's rectangle for the
# screens present. The home row must come back byte for byte, and the file
# must not be touched when nothing changes.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$ROOT/scripts/__eve_thumbnails_adapt.sh"
  export EVE_PREVIEW_CONFIG="$BATS_TEST_TMPDIR/config.json"
  export EVE_PREVIEW_SLOTS="$BATS_TEST_TMPDIR/slots.tsv"
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/pgrep"; chmod +x "$STUB/pgrep"
  export PATH="$STUB:$PATH"
  write_config
}

# The home layout as EPM saved it: four slots along the top right of 3840,
# alts stacked on the same slot, plus Zeeez never placed (default size).
write_config() {
  cat > "$EVE_PREVIEW_CONFIG" <<'JSON'
{
  "global": { "selected_profile": "default", "window_width": 798 },
  "profiles": [
    {
      "profile_name": "default",
      "thumbnail_default_width": 750,
      "thumbnail_default_height": 422,
      "thumbnail_opacity": 100,
      "character_thumbnails": {
        "Tide Mende":  { "x": 1991, "y": 9, "width": 450, "height": 253, "alias": null, "preview_mode": "live" },
        "Killed Bill": { "x": 1991, "y": 9, "width": 450, "height": 253, "alias": null, "preview_mode": "live" },
        "Cube Trap":   { "x": 2441, "y": 9, "width": 450, "height": 253, "alias": null, "preview_mode": "live" },
        "Devel666":    { "x": 2891, "y": 9, "width": 450, "height": 253, "alias": null, "preview_mode": "live" },
        "Nifty Swifter": { "x": 3341, "y": 9, "width": 450, "height": 253, "alias": null, "preview_mode": "live" },
        "Zeeez":       { "x": 220, "y": 452, "width": 750, "height": 422, "alias": null, "preview_mode": "live" }
      }
    }
  ]
}
JSON
}

stub_screens() {
  cat > "$STUB/xrandr" <<EOS
#!/usr/bin/env bash
printf '%b\n' '$1'
EOS
  cat > "$STUB/wmctrl" <<EOS
#!/usr/bin/env bash
printf '%b\n' '$2'
EOS
  chmod +x "$STUB/xrandr" "$STUB/wmctrl"
}

XR_4K='DP-2 connected primary 3840x2160+0+0 (normal left inverted right x axis y axis) 600mm x 340mm'
WM_4K='0  * DG: 3840x2160  VP: 0,0  WA: 0,64 3840x2096  Workspace 1'
XR_LAPTOP='HDMI-0 connected primary 1920x1080+2560+0 (normal left inverted right x axis y axis) 476mm x 267mm\neDP-1-1 connected 2560x1600+0+0 (normal left inverted right x axis y axis) 345mm x 215mm'
WM_LAPTOP='0  * DG: 4480x1600  VP: 0,0  WA: 0,32 4480x1568  Workspace 1'

rect() { jq -r --arg n "$1" '.profiles[0].character_thumbnails[$n] | "\(.x) \(.y) \(.width) \(.height)"' "$EVE_PREVIEW_CONFIG"; }

@test "single 4k screen reproduces the home row exactly" {
  stub_screens "$XR_4K" "$WM_4K"
  run "$SCRIPT" --print
  [ "$status" -eq 0 ]
  [[ "$output" == *$'Tide Mende\t1991\t9\t450\t253'* ]]
  [[ "$output" == *$'Killed Bill\t1991\t9\t450\t253'* ]]
  [[ "$output" == *$'Cube Trap\t2441\t9\t450\t253'* ]]
  [[ "$output" == *$'Devel666\t2891\t9\t450\t253'* ]]
  [[ "$output" == *$'Nifty Swifter\t3341\t9\t450\t253'* ]]
  [[ "$output" != *Zeeez* ]]
}

@test "single 4k screen leaves the config file untouched" {
  stub_screens "$XR_4K" "$WM_4K"
  touch -d '@1000000000' "$EVE_PREVIEW_CONFIG"
  local before; before=$(md5sum < "$EVE_PREVIEW_CONFIG")
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(md5sum < "$EVE_PREVIEW_CONFIG")" = "$before" ]
  [ "$(stat -c %Y "$EVE_PREVIEW_CONFIG")" -eq 1000000000 ]
}

@test "laptop beside the main screen puts a 2x2 grid on the laptop panel" {
  stub_screens "$XR_LAPTOP" "$WM_LAPTOP"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  # 2560 wide panel, two columns of 1280, 16:9-ish cells below the 32px panel.
  [ "$(rect 'Tide Mende')" = "0 32 1280 719" ]
  [ "$(rect 'Killed Bill')" = "0 32 1280 719" ]
  [ "$(rect 'Cube Trap')" = "1280 32 1280 719" ]
  [ "$(rect 'Devel666')" = "0 751 1280 719" ]
  [ "$(rect 'Nifty Swifter')" = "1280 751 1280 719" ]
  # Never placed by hand, so not ours to move.
  [ "$(rect 'Zeeez')" = "220 452 750 422" ]
  # Only the rectangles change.
  [ "$(jq -r '.profiles[0].character_thumbnails["Cube Trap"].preview_mode' "$EVE_PREVIEW_CONFIG")" = "live" ]
  [ "$(jq -r '.global.window_width' "$EVE_PREVIEW_CONFIG")" = "798" ]
}

@test "slots survive the round trip back to the single screen" {
  stub_screens "$XR_LAPTOP" "$WM_LAPTOP"
  run "$SCRIPT"
  stub_screens "$XR_4K" "$WM_4K"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(rect 'Tide Mende')" = "1991 9 450 253" ]
  [ "$(rect 'Cube Trap')" = "2441 9 450 253" ]
  [ "$(rect 'Devel666')" = "2891 9 450 253" ]
  [ "$(rect 'Nifty Swifter')" = "3341 9 450 253" ]
}

@test "a newly placed character gets the next slot" {
  stub_screens "$XR_4K" "$WM_4K"
  run "$SCRIPT"
  jq '.profiles[0].character_thumbnails["Newbie"] = {x: 100, y: 900, width: 450, height: 253}' "$EVE_PREVIEW_CONFIG" > "$EVE_PREVIEW_CONFIG.t" && mv "$EVE_PREVIEW_CONFIG.t" "$EVE_PREVIEW_CONFIG"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q $'^Newbie\t4$' "$EVE_PREVIEW_SLOTS"
  # Five across on 3840 still fits at full size: 3840-49-5*450 = 1541.
  [ "$(rect 'Tide Mende')" = "1541 9 450 253" ]
  [ "$(rect 'Newbie')" = "3341 9 450 253" ]
}

@test "refuses to write while eve-preview-manager runs" {
  stub_screens "$XR_LAPTOP" "$WM_LAPTOP"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/pgrep"
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [ "$(rect 'Tide Mende')" = "1991 9 450 253" ]
  run "$SCRIPT" --force
  [ "$status" -eq 0 ]
  [ "$(rect 'Tide Mende')" = "0 32 1280 719" ]
}

@test "a narrow single screen shrinks the row to fit" {
  stub_screens 'HDMI-0 connected primary 1600x900+0+0 (normal) 476mm x 267mm' '0  * DG: 1600x900  VP: 0,0  WA: 0,32 1600x868  Workspace 1'
  run "$SCRIPT" --print
  [ "$status" -eq 0 ]
  # 4*450+49 > 1600, so (1600-49)/4 = 387 wide, height keeps the 450:253 ratio.
  [[ "$output" == *$'Tide Mende\t3\t9\t387\t217'* ]]
  [[ "$output" == *$'Nifty Swifter\t1164\t9\t387\t217'* ]]
}

@test "1920 alone still holds the row at full size" {
  stub_screens 'HDMI-0 connected primary 1920x1080+0+0 (normal) 476mm x 267mm' '0  * DG: 1920x1080  VP: 0,0  WA: 0,32 1920x1048  Workspace 1'
  run "$SCRIPT" --print
  [[ "$output" == *$'Tide Mende\t71\t9\t450\t253'* ]]
  [[ "$output" == *$'Nifty Swifter\t1421\t9\t450\t253'* ]]
}
