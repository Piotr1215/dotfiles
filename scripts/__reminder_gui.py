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

        self.add(content, self.label("Reminder"))
        message = Gtk.Entry()
        message.set_width_chars(44)
        message.set_hexpand(True)
        message.set_text(str(self.request.get("message", "")))
        message.set_placeholder_text("What should I remind you about?")
        self.add(content, message, True)

        self.add(content, self.label("When"))
        when = Gtk.Entry()
        when.set_width_chars(44)
        when.set_hexpand(True)
        when.set_text(str(self.request.get("when", "")))
        when.set_placeholder_text("10m, 2h, eod, or 14:40 tomorrow")
        self.add(content, when, True)

        self.add(content, self.label("Notes (urls, paths, context)"))
        notes = Gtk.TextView()
        notes.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        notes.set_accepts_tab(False)
        notes_buffer = notes.get_buffer()
        notes_buffer.set_text(str(self.request.get("notes", "")))
        notes_scroll = Gtk.ScrolledWindow()
        notes_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        notes_scroll.set_shadow_type(Gtk.ShadowType.IN)
        notes_scroll.set_min_content_height(110)
        notes_scroll.add(notes)
        self.add(content, notes_scroll, True)

        error = self.label("")
        error.get_style_context().add_class("error")
        self.add(content, error)

        def save(*_args):
            reminder_text = message.get_text().strip()
            schedule = when.get_text().strip()
            if not reminder_text or not schedule:
                error.set_text("Enter both reminder text and a time.")
                return
            start, end = notes_buffer.get_bounds()
            notes_text = notes_buffer.get_text(start, end, False).strip()
            self.finish(
                {"message": reminder_text, "when": schedule, "notes": notes_text}
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
        GLib.idle_add(message.grab_focus)

    def name(self):
        window, content = self.window("Name reminder")
        self.add(content, self.label("Add text for this existing at job."))
        message = Gtk.Entry()
        message.set_width_chars(44)
        message.set_hexpand(True)
        message.set_placeholder_text("Reminder text")
        self.add(content, message, True)

        def save(*_args):
            value = message.get_text().strip()
            if value:
                self.finish({"message": value})

        actions = self.actions(content)
        self.add_cancel(actions)
        save_button = Gtk.Button(label="Save")
        save_button.get_style_context().add_class("suggested-action")
        save_button.connect("clicked", save)
        self.add(actions, save_button)
        self.default_button(save_button)
        message.connect("activate", save)
        window.show_all()
        window.present()
        GLib.idle_add(message.grab_focus)

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

    def alert(self):
        window, content = self.window("Reminder", 420)
        self.add(content, self.label(str(self.request.get("message", "Reminder"))))

        notes = str(self.request.get("notes", "")).strip()
        if notes:
            view = Gtk.TextView()
            view.set_editable(False)
            view.set_cursor_visible(False)
            view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
            view.get_buffer().set_text(notes)
            scroll = Gtk.ScrolledWindow()
            scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
            scroll.set_shadow_type(Gtk.ShadowType.IN)
            scroll.set_min_content_height(90)
            scroll.add(view)
            self.add(content, scroll, True)

        snooze_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.add(snooze_row, self.label("Snooze for"))
        minutes = Gtk.SpinButton.new_with_range(1, 1440, 1)
        minutes.set_value(10)
        self.add(snooze_row, minutes)
        self.add(snooze_row, self.label("minutes"))
        self.add(content, snooze_row)

        actions = self.actions(content)
        # The helper owns opening: it holds the url and calls the shared
        # taskopen opener, so this button only names the action.
        if str(self.request.get("url", "")).strip():
            open_link = Gtk.Button(label="Open link")
            open_link.connect("clicked", lambda *_args: self.finish({"action": "open"}))
            self.add(actions, open_link)
        snooze = Gtk.Button(label="Snooze")
        snooze.connect(
            "clicked",
            lambda *_args: self.finish(
                {"action": "snooze", "minutes": minutes.get_value_as_int()}
            ),
        )
        self.add(actions, snooze)
        acknowledge = Gtk.Button(label="Acknowledge")
        acknowledge.get_style_context().add_class("suggested-action")
        acknowledge.connect(
            "clicked", lambda *_args: self.finish({"action": "acknowledge"})
        )
        self.add(actions, acknowledge)
        self.default_button(acknowledge)
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
    parser.add_argument("mode", nargs="?", choices=("form", "name", "confirm", "alert", "error"))
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
