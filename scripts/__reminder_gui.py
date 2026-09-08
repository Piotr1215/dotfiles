#!/usr/bin/env python3

import argparse
import json
import sys

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk


def read_request():
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise ValueError("request must be a JSON object")
    return value


class ReminderDialog:
    def __init__(self, mode, request):
        self.mode = mode
        self.request = request
        self.exit_code = 1
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

    def window(self, title, width=440):
        window = Gtk.ApplicationWindow(application=self.app)
        window.set_title(title)
        window.set_default_size(width, -1)
        window.set_resizable(False)
        window.set_position(Gtk.WindowPosition.CENTER_ALWAYS)
        window.connect("delete-event", self.close)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content.set_margin_top(18)
        content.set_margin_bottom(18)
        content.set_margin_start(18)
        content.set_margin_end(18)
        window.add(content)
        return window, content

    @staticmethod
    def label(text):
        label = Gtk.Label(label=text)
        label.set_xalign(0)
        label.set_line_wrap(True)
        return label

    @staticmethod
    def actions(content):
        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        actions.set_halign(Gtk.Align.END)
        content.pack_start(actions, False, False, 0)
        return actions

    @staticmethod
    def add(content, widget, expand=False):
        content.pack_start(widget, expand, expand, 0)

    @staticmethod
    def default_button(button):
        button.set_can_default(True)
        button.grab_default()

    def add_cancel(self, actions):
        cancel = Gtk.Button(label="Cancel")
        cancel.connect("clicked", self.close)
        self.add(actions, cancel)

    def form(self):
        title = self.request.get("title", "Reminder")
        window, content = self.window(title)

        self.add(content, self.label("Label"))
        label = Gtk.Entry()
        label.set_width_chars(44)
        label.set_hexpand(True)
        label.set_text(str(self.request.get("label", "")))
        label.set_placeholder_text("What should I remind you about?")
        self.add(content, label, True)

        self.add(content, self.label("When"))
        when = Gtk.Entry()
        when.set_width_chars(44)
        when.set_hexpand(True)
        when.set_text(str(self.request.get("when", "")))
        when.set_placeholder_text("10m, 2h, eod, tomorrow, Tuesday 16:20, 2026-09-10 09:30")
        self.add(content, when, True)

        self.add(content, self.label("Repeat (optional: '0 9 * * 1' or 'every 7d')"))
        repeat = Gtk.Entry()
        repeat.set_width_chars(44)
        repeat.set_hexpand(True)
        repeat.set_text(str(self.request.get("repeat", "")))
        self.add(content, repeat, True)

        self.add(content, self.label("Subject (task:<uuid>, url:<url>, or notes)"))
        subject = Gtk.TextView()
        subject.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        subject.set_accepts_tab(False)
        subject_buffer = subject.get_buffer()
        subject_buffer.set_text(str(self.request.get("subject", "")))
        subject_scroll = Gtk.ScrolledWindow()
        subject_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        subject_scroll.set_shadow_type(Gtk.ShadowType.IN)
        subject_scroll.set_min_content_height(110)
        subject_scroll.add(subject)
        self.add(content, subject_scroll, True)

        error = self.label("")
        error.get_style_context().add_class("error")
        self.add(content, error)

        def save(*_args):
            label_text = label.get_text().strip()
            when_text = when.get_text().strip()
            repeat_text = repeat.get_text().strip()
            start, end = subject_buffer.get_bounds()
            subject_text = subject_buffer.get_text(start, end, False).strip()
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

        actions = self.actions(content)
        self.add_cancel(actions)
        save_button = Gtk.Button(label="Save reminder")
        save_button.get_style_context().add_class("suggested-action")
        save_button.connect("clicked", save)
        self.add(actions, save_button)
        self.default_button(save_button)
        when.connect("activate", save)
        window.show_all()
        window.present()
        GLib.idle_add(label.grab_focus)

    def confirm(self):
        window, content = self.window(self.request.get("title", "Confirm"), 380)
        self.add(content, self.label(str(self.request.get("message", "Are you sure?"))))
        actions = self.actions(content)
        self.add_cancel(actions)
        confirm = Gtk.Button(label=str(self.request.get("confirm_label", "Confirm")))
        confirm.get_style_context().add_class("destructive-action")
        confirm.connect("clicked", lambda *_args: self.finish({"confirmed": True}))
        self.add(actions, confirm)
        self.default_button(confirm)
        window.show_all()
        window.present()

    # The helper owns every consequence: it opens the url, edits the record
    # and syncs the clocks. This dialog only names the choice. Closing it
    # without choosing exits 1, which the helper reads as the default snooze.
    SNOOZES = (
        ("15m", "15 minutes"),
        ("1h", "1 hour"),
        ("Tomorrow 9:00", "tomorrow 9:00"),
        ("Next Monday", "next monday 9:00"),
    )

    def alert(self):
        window, content = self.window("Reminder", 460)
        title = self.label("")
        title.set_markup(
            "<b>%s</b>" % GLib.markup_escape_text(str(self.request.get("title", "Reminder")))
        )
        self.add(content, title)

        due = str(self.request.get("due", "")).strip()
        late = str(self.request.get("late", "")).strip()
        repeat = str(self.request.get("repeat", "")).strip()
        parts = []
        if due:
            parts.append("Due %s" % due)
        if late:
            parts.append("%s late" % late)
        if repeat:
            parts.append("repeats %s" % repeat)
        if parts:
            when = self.label(", ".join(parts))
            when.get_style_context().add_class("dim-label")
            self.add(content, when)

        body = str(self.request.get("body", "")).strip()
        if body:
            view = Gtk.TextView()
            view.set_editable(False)
            view.set_cursor_visible(False)
            view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
            view.get_buffer().set_text(body)
            scroll = Gtk.ScrolledWindow()
            scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
            scroll.set_shadow_type(Gtk.ShadowType.IN)
            scroll.set_min_content_height(90)
            scroll.add(view)
            self.add(content, scroll, True)

        snooze_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.add(snooze_row, self.label("Snooze"))
        for caption, spec in self.SNOOZES:
            button = Gtk.Button(label=caption)
            button.connect(
                "clicked",
                lambda _b, s=spec: self.finish({"action": "snooze", "when": s}),
            )
            self.add(snooze_row, button)
        self.add(content, snooze_row)

        actions = self.actions(content)
        if str(self.request.get("url", "")).strip():
            open_link = Gtk.Button(label="Open link")
            open_link.connect("clicked", lambda *_args: self.finish({"action": "open"}))
            self.add(actions, open_link)
        done_label = "Done"
        if str(self.request.get("subject_type", "")) == "task":
            done_label = "Task done"
        done = Gtk.Button(label=done_label)
        done.get_style_context().add_class("suggested-action")
        done.connect("clicked", lambda *_args: self.finish({"action": "done"}))
        self.add(actions, done)
        self.default_button(done)
        window.show_all()
        window.present()

    def error(self):
        window, content = self.window("Reminder error", 420)
        self.add(content, self.label(str(self.request.get("message", "Reminder failed."))))
        actions = self.actions(content)
        close = Gtk.Button(label="Close")
        close.connect("clicked", lambda *_args: self.finish({"closed": True}))
        self.add(actions, close)
        self.default_button(close)
        window.show_all()
        window.present()

    def on_activate(self, _app):
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
