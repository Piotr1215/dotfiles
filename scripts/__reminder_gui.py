#!/usr/bin/env python3
# GTK dialogs for __reminder.sh: the add and edit form, a confirm, the alert
# behind a fired reminder or a passed deadline, and an error. Each reads one
# JSON request on stdin, prints one JSON choice on stdout and exits 0. Closing
# the window (Esc or the title bar) exits 1, which the helper reads as "back
# later". The helper owns every consequence; a dialog only names the choice.
#
# The look follows the taskwarrior-tui key 4 spawn dialog
# (~/.claude/scripts/__spawn_directive_dialog.py): Dracula colours, a card for
# the title, small captions, monospace text boxes that take the spare height,
# and buttons that print their key. Windows open big (fit_size caps them at 90%
# of the monitor under the pointer) and stay resizable.
#
# Alert keys: Ctrl+Enter sends to AI with the instruction box, Alt+I focuses
# that box, Esc closes for now. Form keys: Enter or Ctrl+Enter saves, Esc
# cancels.

import argparse
import json
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gio, GLib, Gtk

# Default (width, height) per mode; a height of 0 means the natural height.
SIZES = {
    "alert": (1100, 820),
    "form": (760, 620),
    "confirm": (520, 0),
    "error": (560, 0),
}
SCREEN_RATIO = 0.9


def fit_size(area_w, area_h, base, ratio=SCREEN_RATIO):
    """Window size: `base`, capped at `ratio` of the work area. A base height
    of 0 stays -1 so GTK uses the natural height."""
    width = min(base[0], int(area_w * ratio))
    height = min(base[1], int(area_h * ratio)) if base[1] > 0 else -1
    return width, height


def alert_meta(request, deadline):
    """The line under the alert title: due or deadline, lateness, repeat."""
    due = str(request.get("due", "")).strip()
    late = str(request.get("late", "")).strip()
    repeat = str(request.get("repeat", "")).strip()
    parts = []
    if due:
        parts.append(("Deadline %s" if deadline else "Due %s") % due)
    if late:
        parts.append("%s late" % late)
    if repeat:
        parts.append(("checks %s" if deadline else "repeats %s") % repeat)
    return " · ".join(parts)


def instruction_status(text):
    """Footer line that says what Send to AI will carry."""
    body = text.strip()
    if not body:
        return "No instruction: Send to AI hands over the report alone"
    lines = body.count("\n") + 1
    noun = "line" if lines == 1 else "lines"
    return f"Instruction: {lines} {noun}, {len(body)} chars, goes with Send to AI"


# Dracula palette (https://draculatheme.com), shared with the key 4 dialog so
# both match the terminal. A CSS parse error drops the whole theme silently
# (apply_theme), so the test suite loads this string and fails on any property
# GTK 3 rejects.
DRACULA_CSS = b"""
window, dialog, .background { background-color: #282a36; color: #f8f8f2; }
label { color: #f8f8f2; }
tooltip, tooltip.background { background-color: #21222c; color: #f8f8f2; }

.caption { color: #bd93f9; font-size: 9pt; font-weight: bold; }
.caption-key { color: #8a90b8; font-size: 8.5pt; }
.muted { color: #9ea3c4; }
.error { color: #ff5555; }

.task-card {
    background-color: #21222c;
    border: 1px solid #44475a;
    border-left: 3px solid #bd93f9;
    border-radius: 6px;
    padding: 10px 14px;
}
.task-card.deadline { border-left-color: #ffb86c; }
.task-card.deadline .caption { color: #ffb86c; }
.task-title { font-size: 13pt; font-weight: bold; }
.message { font-size: 11pt; }

.text-box { border: 1px solid #44475a; border-radius: 6px; }
textview, textview text { background-color: #21222c; color: #f8f8f2; }
textview { font-family: monospace; font-size: 11pt; caret-color: #f8f8f2; }
textview text selection { background-color: #44475a; color: #f8f8f2; }
textview.report, textview.report text { background-color: #1e1f29; color: #e2e2dc; }
.placeholder { color: #6272a4; font-family: monospace; font-size: 11pt; }

entry {
    background-image: none; background-color: #21222c; color: #f8f8f2;
    border: 1px solid #44475a; border-radius: 4px;
    min-height: 30px; padding: 4px 10px; caret-color: #f8f8f2;
}
entry:focus { border-color: #bd93f9; }
entry selection { background-color: #44475a; color: #f8f8f2; }

spinbutton {
    background-color: #21222c; color: #f8f8f2;
    border: 1px solid #44475a; border-radius: 4px;
}
spinbutton entry { border: none; min-height: 28px; }
spinbutton button {
    border: none; border-left: 1px solid #44475a; border-radius: 0;
    min-height: 28px; padding: 0 8px;
}

calendar {
    background-color: #21222c; color: #f8f8f2;
    border: 1px solid #44475a; border-radius: 4px; padding: 4px;
}
calendar.header { background-color: #282a36; border: none; }
calendar.button { color: #bd93f9; }
calendar:selected { background-color: #bd93f9; color: #282a36; }
calendar:indeterminate { color: #6272a4; }

button {
    background-image: none; background-color: #44475a; color: #f8f8f2;
    border: 1px solid #6272a4; border-radius: 4px;
    min-height: 30px; padding: 4px 18px;
}
button label { color: #f8f8f2; text-shadow: none; }
button:hover { background-color: #6272a4; }
button:checked { background-color: #6272a4; border-color: #bd93f9; }
button.extend { padding: 4px 14px; }
button.suggested-action {
    background-color: #bd93f9; color: #282a36; border: 1px solid #bd93f9;
    font-weight: bold;
}
button.suggested-action label { color: #282a36; }
button.suggested-action:hover { background-color: #caa9fa; }
button.destructive-action {
    background-color: #ff5555; color: #282a36; border: 1px solid #ff5555;
    font-weight: bold;
}
button.destructive-action label { color: #282a36; }
button.destructive-action:hover { background-color: #ff6e6e; }
button label.key-hint { color: #9ea3c4; font-size: 8.5pt; font-weight: normal; }
button.suggested-action label.key-hint { color: #4f3f7a; }
button.destructive-action label.key-hint { color: #7a2a2a; }
"""


def apply_theme():
    provider = Gtk.CssProvider()
    try:
        provider.load_from_data(DRACULA_CSS)
    except GLib.Error:
        return
    screen = Gdk.Screen.get_default()
    if screen is None:
        return
    Gtk.StyleContext.add_provider_for_screen(
        screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )


def pointer_workarea():
    """Work area (w, h) of the monitor under the pointer, where the window opens."""
    display = Gdk.Display.get_default()
    if display is None:
        return None
    monitor = None
    seat = display.get_default_seat()
    pointer = seat.get_pointer() if seat else None
    if pointer is not None:
        _screen, x, y = pointer.get_position()
        monitor = display.get_monitor_at_point(x, y)
    monitor = monitor or display.get_primary_monitor() or display.get_monitor(0)
    if monitor is None:
        return None
    area = monitor.get_workarea()
    return area.width, area.height


def read_request():
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError("request must be a JSON object")
    return value


def styled(widget, *classes):
    for cls in classes:
        widget.get_style_context().add_class(cls)
    return widget


def caption(text, target=None):
    """Small uppercase heading. With a target, an underscore in `text` marks
    the Alt mnemonic that moves focus to it ("_Instruction" is Alt+I)."""
    lbl = Gtk.Label(xalign=0)
    if target is None:
        lbl.set_text(text.upper())
    else:
        lbl.set_text_with_mnemonic(text.upper())
        lbl.set_mnemonic_widget(target)
    return styled(lbl, "caption")


def caption_row(text, target=None, hint=""):
    """A caption, its Alt key in tmux notation ("M-I") when it has a target,
    and an optional muted hint on the right. Returns the row."""
    row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    lbl = caption(text, target)
    row.pack_start(lbl, False, False, 0)
    if target is not None:
        key = Gdk.keyval_name(Gdk.keyval_to_upper(lbl.get_mnemonic_keyval()))
        row.pack_start(styled(Gtk.Label(label=f"M-{key}"), "caption-key"), False, False, 0)
    if hint:
        row.pack_end(styled(Gtk.Label(label=hint, xalign=1), "muted"), False, False, 0)
    return row


def button_with_key(text, key="", *classes):
    """A button whose label names its keyboard shortcut in a dimmer hint. The
    hint is its own label coloured by CSS (.key-hint), as in the key 4 dialog."""
    btn = Gtk.Button()
    row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
    row.set_halign(Gtk.Align.CENTER)
    row.pack_start(Gtk.Label(label=text), False, False, 0)
    if key:
        row.pack_start(styled(Gtk.Label(label=key), "key-hint"), False, False, 0)
    btn.add(row)
    return styled(btn, *classes)


def text_box(text="", editable=True, min_height=110, placeholder=""):
    """A monospace text view in a bordered scroller. Returns (outer widget,
    view). GTK 3 views have no placeholder, so one is overlaid and lets clicks
    through; it hides while the buffer holds text."""
    view = Gtk.TextView()
    view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
    view.set_accepts_tab(False)  # Tab moves focus, as in a form
    view.set_left_margin(12)
    view.set_right_margin(12)
    view.set_top_margin(10)
    view.set_bottom_margin(10)
    if not editable:
        view.set_editable(False)
        view.set_cursor_visible(False)
        styled(view, "report")
    buf = view.get_buffer()
    buf.set_text(text)
    scroller = styled(Gtk.ScrolledWindow(), "text-box")
    scroller.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
    scroller.set_min_content_height(min_height)
    scroller.add(view)
    if not placeholder:
        return scroller, view
    hint = styled(Gtk.Label(label=placeholder, xalign=0), "placeholder")
    hint.set_halign(Gtk.Align.START)
    hint.set_valign(Gtk.Align.START)
    hint.set_margin_start(13)  # view left margin + box border
    hint.set_margin_top(11)
    overlay = Gtk.Overlay()
    overlay.add(scroller)
    overlay.add_overlay(hint)
    overlay.set_overlay_pass_through(hint, True)
    hint.set_no_show_all(True)
    hint.set_visible(not text)
    buf.connect("changed", lambda b: hint.set_visible(b.get_char_count() == 0))
    return overlay, view


def buffer_text(view):
    buf = view.get_buffer()
    return buf.get_text(buf.get_start_iter(), buf.get_end_iter(), False)


class ReminderDialog:
    def __init__(self, mode, request):
        self.mode = mode
        self.request = request
        self.exit_code = 1
        self.on_ctrl_enter = None
        self.app = Gtk.Application(
            application_id="dev.piotr.ReminderDialog",
            flags=Gio.ApplicationFlags.NON_UNIQUE,
        )
        self.app.connect("activate", self.on_activate)

    def finish(self, result=None, exit_code=0):
        if result is not None:
            print(json.dumps(result, ensure_ascii=False), flush=True)
        self.exit_code = exit_code
        self.app.quit()

    def close(self, *_args):
        self.finish(exit_code=1)
        return True

    def on_key(self, _window, event):
        """Esc closes for now; Ctrl+Enter runs the mode's main action. The
        window sees the key before a focused text view does."""
        if event.keyval == Gdk.KEY_Escape:
            return self.close()
        ctrl = event.state & Gdk.ModifierType.CONTROL_MASK
        if ctrl and event.keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter) and self.on_ctrl_enter:
            self.on_ctrl_enter()
            return True
        return False

    def window(self, title, mode):
        window = Gtk.ApplicationWindow(application=self.app)
        window.set_title(title)
        width, height = fit_size(10**5, 10**5, SIZES[mode])
        area = pointer_workarea()
        if area:
            width, height = fit_size(*area, SIZES[mode])
        window.set_default_size(width, height)
        window.set_resizable(True)
        window.set_position(Gtk.WindowPosition.CENTER_ALWAYS)
        window.connect("delete-event", self.close)
        window.connect("key-press-event", self.on_key)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        for side in ("top", "bottom", "start", "end"):
            getattr(content, f"set_margin_{side}")(20)
        window.add(content)
        return window, content

    @staticmethod
    def label(text, *classes):
        label = Gtk.Label(label=text)
        label.set_xalign(0)
        label.set_line_wrap(True)
        return styled(label, *classes)

    @staticmethod
    def footer(content, status=None):
        """Status on the left, an actions box on the right. Returns the box."""
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        if status is not None:
            row.pack_start(status, True, True, 0)
        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        row.pack_end(actions, False, False, 0)
        content.pack_start(row, False, False, 0)
        return actions

    @staticmethod
    def default_button(button):
        button.set_can_default(True)
        button.grab_default()

    def add_cancel(self, actions):
        cancel = button_with_key("Cancel", "Esc")
        cancel.connect("clicked", self.close)
        actions.pack_start(cancel, False, False, 0)

    def form(self):
        window, content = self.window(self.request.get("title", "Reminder"), "form")

        def entry(text, placeholder=""):
            widget = Gtk.Entry()
            widget.set_hexpand(True)
            widget.set_text(str(self.request.get(text, "")))
            widget.set_placeholder_text(placeholder)
            widget.set_activates_default(True)
            return widget

        label = entry("label", "What should I remind you about?")
        when = entry("when", "10m, 2h, eod, tomorrow, Tue 16:20")
        repeat = entry("repeat", "0 9 * * 1, or every 7d")
        subject_box, subject = text_box(
            str(self.request.get("subject", "")),
            placeholder="task:<uuid>, url:<url>, or notes",
        )

        grid = Gtk.Grid(column_spacing=20, row_spacing=6)
        grid.attach(caption_row("_Label", label), 0, 0, 2, 1)
        grid.attach(label, 0, 1, 2, 1)
        grid.attach(caption_row("_When", when), 0, 2, 1, 1)
        grid.attach(when, 0, 3, 1, 1)
        grid.attach(caption_row("_Repeat", repeat, "optional"), 1, 2, 1, 1)
        grid.attach(repeat, 1, 3, 1, 1)
        grid.set_column_homogeneous(True)
        content.pack_start(grid, False, False, 0)

        subject_col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        subject_col.pack_start(caption_row("_Subject", subject, "optional"), False, False, 0)
        subject_col.pack_start(subject_box, True, True, 0)
        content.pack_start(subject_col, True, True, 0)

        error = self.label("", "error")

        def save(*_args):
            label_text = label.get_text().strip()
            when_text = when.get_text().strip()
            repeat_text = repeat.get_text().strip()
            subject_text = buffer_text(subject).strip()
            if not label_text and not subject_text:
                error.set_text("Enter a label or a subject.")
                return
            if not when_text and not repeat_text:
                error.set_text("Enter a time or a repeat.")
                return
            self.finish(
                {
                    "label": label_text,
                    "when": when_text,
                    "repeat": repeat_text,
                    "subject": subject_text,
                }
            )

        actions = self.footer(content, error)
        self.add_cancel(actions)
        save_button = button_with_key("Save reminder", "Enter", "suggested-action")
        save_button.connect("clicked", save)
        actions.pack_start(save_button, False, False, 0)
        self.default_button(save_button)
        self.on_ctrl_enter = save
        window.show_all()
        window.present()
        GLib.idle_add(label.grab_focus)

    def confirm(self):
        window, content = self.window(self.request.get("title", "Confirm"), "confirm")
        message = str(self.request.get("message", "Are you sure?"))
        content.pack_start(self.label(message, "message"), True, True, 0)
        actions = self.footer(content)
        # Cancel holds the focus, so Enter cancels: a delete takes a click or Tab.
        self.add_cancel(actions)
        confirm = button_with_key(
            str(self.request.get("confirm_label", "Confirm")), "", "destructive-action"
        )
        confirm.connect("clicked", lambda *_args: self.finish({"confirmed": True}))
        actions.pack_start(confirm, False, False, 0)
        self.default_button(confirm)
        window.show_all()
        window.present()

    # The helper owns every consequence: it opens the url, edits the record
    # and syncs the clocks. This dialog only names the choice. Closing it
    # without choosing exits 1, which the helper reads as "back later".
    EXTENDS = (
        ("15m", "15 minutes"),
        ("1h", "1 hour"),
        ("Tomorrow 9:00", "tomorrow 9:00"),
        ("Next Monday", "next monday 9:00"),
    )

    def picker(self):
        """A calendar and an hour and minute, hidden until the toggle shows
        them. Returns (toggle, revealer); the revealer's button extends to the
        choice as 'YYYY-MM-DD HH:MM'."""
        pick = str(self.request.get("pick", "")).strip()
        try:
            start = GLib.DateTime.new_local(
                int(pick[0:4]), int(pick[5:7]), int(pick[8:10]), int(pick[11:13]), int(pick[14:16]), 0
            )
        except (ValueError, TypeError):
            start = None
        if start is None:
            start = GLib.DateTime.new_now_local().add_days(1)

        calendar = Gtk.Calendar()
        calendar.select_month(start.get_month() - 1, start.get_year())
        calendar.select_day(start.get_day_of_month())
        hour = Gtk.SpinButton.new_with_range(0, 23, 1)
        hour.set_value(start.get_hour())
        minute = Gtk.SpinButton.new_with_range(0, 55, 5)
        minute.set_value(start.get_minute() - start.get_minute() % 5)

        def padded(spin):
            spin.set_text("%02d" % spin.get_value_as_int())
            return True

        for spin in (hour, minute):
            spin.set_numeric(True)
            spin.set_wrap(True)
            spin.set_width_chars(2)
            spin.connect("output", padded)

        def chosen():
            year, month, day = calendar.get_date()
            return "%04d-%02d-%02d %02d:%02d" % (
                year, month + 1, day, hour.get_value_as_int(), minute.get_value_as_int()
            )

        time_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        time_row.pack_start(hour, False, False, 0)
        time_row.pack_start(Gtk.Label(label=":"), False, False, 0)
        time_row.pack_start(minute, False, False, 0)
        set_button = button_with_key("Extend to this", "", "extend")
        set_button.connect(
            "clicked", lambda *_args: self.finish({"action": "extend", "when": chosen()})
        )
        side = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        side.pack_start(caption("Time"), False, False, 0)
        side.pack_start(time_row, False, False, 0)
        side.pack_start(set_button, False, False, 0)

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        box.pack_start(calendar, False, False, 0)
        box.pack_start(side, False, False, 0)
        revealer = Gtk.Revealer()
        revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN)
        revealer.add(box)
        toggle = styled(Gtk.ToggleButton(label="Pick a date and time"), "extend")
        toggle.connect("toggled", lambda t: revealer.set_reveal_child(t.get_active()))
        return toggle, revealer

    def alert(self):
        deadline = str(self.request.get("kind", "show")) == "deadline"
        window, content = self.window("Deadline passed" if deadline else "Reminder", "alert")

        card = styled(Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4), "task-card")
        if deadline:
            styled(card, "deadline")
        card.pack_start(caption("Deadline passed" if deadline else "Reminder"), False, False, 0)
        title = self.label(str(self.request.get("title", "Reminder")), "task-title")
        title.set_selectable(True)
        title.set_can_focus(False)
        card.pack_start(title, False, False, 0)
        meta = alert_meta(self.request, deadline)
        if meta:
            card.pack_start(self.label(meta, "muted"), False, False, 0)
        content.pack_start(card, False, False, 0)

        body = str(self.request.get("body", "")).strip()
        if body:
            report_box, _report = text_box(body, editable=False, min_height=140)
            report_col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
            report_col.pack_start(caption("Status report" if deadline else "Details"), False, False, 0)
            report_col.pack_start(report_box, True, True, 0)
            content.pack_start(report_col, True, True, 0)

        # The instruction rides with Send to AI, so Piotr can say what happens
        # next. It also comes back prefilled after Open, which loops here.
        note_box, note = text_box(
            str(self.request.get("note", "")),
            min_height=110,
            placeholder="Tell the AI what to do next with this reminder.\n"
            "Leave empty to hand over the report alone.",
        )
        note_col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        note_col.pack_start(
            caption_row("_Instruction for AI", note, "optional, goes with Send to AI"),
            False, False, 0,
        )
        note_col.pack_start(note_box, True, True, 0)
        content.pack_start(note_col, not body, not body, 0)

        extend_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        extend_label = caption("Extend")
        extend_label.set_valign(Gtk.Align.CENTER)
        extend_label.set_margin_end(4)
        extend_row.pack_start(extend_label, False, False, 0)
        for text, spec in self.EXTENDS:
            button = styled(Gtk.Button(label=text), "extend")
            button.connect(
                "clicked",
                lambda _b, s=spec: self.finish({"action": "extend", "when": s}),
            )
            extend_row.pack_start(button, False, False, 0)
        toggle, revealer = self.picker()
        extend_row.pack_end(toggle, False, False, 0)
        extend_col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        extend_col.pack_start(extend_row, False, False, 0)
        extend_col.pack_start(revealer, False, False, 0)
        content.pack_start(extend_col, False, False, 0)

        status = self.label(instruction_status(buffer_text(note)), "muted")
        note.get_buffer().connect(
            "changed", lambda _b: status.set_text(instruction_status(buffer_text(note)))
        )
        actions = self.footer(content, status)

        def choose(action):
            text = buffer_text(note).strip()
            self.finish({"action": action, "note": text} if text else {"action": action})

        subject_type = str(self.request.get("subject_type", ""))
        if subject_type == "task" or str(self.request.get("url", "")).strip():
            opener = button_with_key("Open task" if subject_type == "task" else "Open link")
            opener.connect("clicked", lambda *_args: choose("open"))
            actions.pack_start(opener, False, False, 0)
        delete = button_with_key("Delete", "", "destructive-action")
        delete.connect("clicked", lambda *_args: self.finish({"action": "delete"}))
        actions.pack_start(delete, False, False, 0)
        send = button_with_key("Send to AI", "Ctrl+Enter")
        send.set_tooltip_text("Gordon when he is running, otherwise a new Claude window")
        send.connect("clicked", lambda *_args: choose("ai"))
        actions.pack_start(send, False, False, 0)
        self.on_ctrl_enter = lambda: choose("ai")
        primary = send
        if not deadline:
            done = button_with_key("Task done" if subject_type == "task" else "Done")
            done.connect("clicked", lambda *_args: self.finish({"action": "done"}))
            actions.pack_start(done, False, False, 0)
            primary = done
        styled(primary, "suggested-action")
        window.show_all()
        window.present()
        # Focus the instruction box: typing goes there, and a stray Enter is a
        # newline instead of a choice.
        GLib.idle_add(note.grab_focus)

    def error(self):
        window, content = self.window("Reminder error", "error")
        message = str(self.request.get("message", "Reminder failed."))
        content.pack_start(self.label(message, "message"), True, True, 0)
        actions = self.footer(content)
        close = button_with_key("Close", "Enter", "suggested-action")
        close.connect("clicked", lambda *_args: self.finish({"closed": True}))
        actions.pack_start(close, False, False, 0)
        self.default_button(close)
        window.show_all()
        window.present()

    def on_activate(self, _app):
        apply_theme()
        getattr(self, self.mode)()

    def run(self):
        self.app.run([])
        return self.exit_code


def main():
    parser = argparse.ArgumentParser(description="GTK dialogs for the reminder helper")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("mode", nargs="?", choices=("form", "confirm", "alert", "error"))
    args = parser.parse_args()

    if args.check:
        window = Gtk.Window()
        window.set_position(Gtk.WindowPosition.CENTER_ALWAYS)
        window.add(ReminderDialog.label("check"))
        window.destroy()
        print("GTK 3 ready; position=center-always")
        return 0
    if args.mode is None:
        parser.error("mode is required")

    try:
        request = read_request()
    except (json.JSONDecodeError, ValueError) as exc:
        print(f"Invalid reminder GUI request: {exc}", file=sys.stderr)
        return 2
    return ReminderDialog(args.mode, request).run()


if __name__ == "__main__":
    raise SystemExit(main())
