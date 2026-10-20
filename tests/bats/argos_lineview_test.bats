#!/usr/bin/env bats
# Tests for the label-reuse patch in
# .local/share/gnome-shell/extensions/argos@pew.worldwidemann.com/lineview.js:
# a text-only line rewrites the existing label instead of replacing it.

EXT="$(cd "$BATS_TEST_DIRNAME/../../.local/share/gnome-shell/extensions/argos@pew.worldwidemann.com" && pwd)"

setup() {
    command -v gjs >/dev/null || skip "gjs not installed"
    WORK="$(mktemp -d)"
    # The real lineview.js with St, Clutter and GdkPixbuf pointed at stubs:
    # plain gjs cannot load the shell's St or mutter's Clutter.
    sed -e "s|'gi://St'|'./stub-st.js'|" \
        -e "s|'gi://Clutter'|'./stub-clutter.js'|" \
        -e "s|'gi://GdkPixbuf'|'./stub-gdkpixbuf.js'|" \
        "$EXT/lineview.js" >"$WORK/lineview.js"

    # The label's text mirrors mutter 46 clutter-text.c, read there because
    # mutter's Clutter will not start outside the shell: the text property
    # parses at once when markup is on (set_property, PROP_TEXT), and turning
    # markup on parses whatever the buffer holds (clutter_text_set_use_markup).
    # A parse keeps the opening tags as the attributes and the rest as text.
    cat >"$WORK/stub-st.js" <<'EOF'
import GObject from 'gi://GObject';
export const made = {labels: 0};
class StubText {
    constructor() { this.buffer = ''; this.markup = false; this.attrs = []; }
    parse(s) {
        this.attrs = (s.match(/<[^/>][^>]*>/g) ?? []);
        this.buffer = s.replace(/<[^>]+>/g, '');
    }
    set text(s) { if (this.markup) this.parse(s); else this.buffer = s; }
    get text() { return this.buffer; }
    set use_markup(on) {
        const s = this.buffer;
        if (on !== this.markup) { this.markup = on; this.attrs = []; }
        if (on)
            this.parse(s);
    }
    get use_markup() { return this.markup; }
}
class Label {
    constructor() { made.labels++; this._text = new StubText(); }
    get_clutter_text() { return this._text; }
}
class Icon { constructor(props) { this.icon_name = props.icon_name; } }
const BoxLayout = GObject.registerClass(class StubBox extends GObject.Object {
    _init() { super._init(); this.kids = []; }
    add_child(child) { this.kids.push(child); }
    remove_all_children() { this.kids = []; }
});
export default {BoxLayout, Label, Icon};
EOF
    cat >"$WORK/stub-clutter.js" <<'EOF'
export default {ActorAlign: {CENTER: 0}};
EOF
    cat >"$WORK/stub-gdkpixbuf.js" <<'EOF'
export default {};
EOF
    # Each argument is a line: text, or icon:<name>:<text>. Prints labels
    # made, then the children after the last line, a label as its text and
    # attributes.
    cat >"$WORK/run.js" <<'EOF'
import ArgosLineView from './lineview.js';
import {made} from './stub-st.js';
const view = new ArgosLineView();
for (const arg of ARGV) {
    const [, icon, text] = arg.match(/^(?:icon:([^:]+):)?(.*)$/);
    const line = {markup: text};
    if (icon)
        line.iconName = icon;
    view.setLine(line);
}
print(made.labels);
print(view.kids.map(k => k.icon_name ? `icon:${k.icon_name}`
    : `label:${k.get_clutter_text().text}${k.get_clutter_text().attrs.join('')}`).join(','));
EOF
}

teardown() {
    rm -rf "$WORK"
}

@test "text-only lines reuse one label and keep their markup" {
    run timeout 20 gjs -m "$WORK/run.js" "<span color='#f00'>A</span>" "<span color='#0f0'>B</span>" "<span color='#00f'>C</span>"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "1" ]
    [ "${lines[1]}" = "label:C<span color='#00f'>" ]
}

@test "a line with an icon rebuilds, and so does the text line after it" {
    run timeout 20 gjs -m "$WORK/run.js" 'A' 'icon:x:B' 'C' 'D'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "3" ]
    [ "${lines[1]}" = "label:D" ]
}

@test "an icon line keeps its icon beside the label" {
    run timeout 20 gjs -m "$WORK/run.js" 'A' 'icon:x:B'
    [ "$status" -eq 0 ]
    [ "${lines[1]}" = "icon:x,label:B" ]
}

@test "an empty line drops the label, and the next text line makes a new one" {
    run timeout 20 gjs -m "$WORK/run.js" 'A' '' 'B'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "2" ]
    [ "${lines[1]}" = "label:B" ]
}
