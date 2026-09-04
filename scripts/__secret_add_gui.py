#!/usr/bin/env python3

import argparse
import sys

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, Gtk


SEPARATOR = "\x1f"
WINDOW_POSITION = Gtk.WindowPosition.CENTER_ALWAYS


def default_subtree(subtrees):
    if "work" in subtrees:
        return "work"
    return subtrees[0] if subtrees else ""


def value_entry():
    entry = Gtk.Entry()
    entry.set_visibility(False)
    entry.set_input_purpose(Gtk.InputPurpose.PASSWORD)
    return entry


class SecretAddDialog:
    def __init__(self, subtrees):
        self.subtrees = subtrees
        self.exit_code = 1
        self.app = Gtk.Application(
            application_id="dev.piotr.SecretAddDialog",
            flags=Gio.ApplicationFlags.NON_UNIQUE,
        )
        self.app.connect("activate", self.on_activate)

    def finish(self, fields=None, exit_code=0):
        if fields is not None:
            print(SEPARATOR.join(fields), flush=True)
        self.exit_code = exit_code
        self.app.quit()

    def close(self, *_args):
        self.finish(exit_code=1)
        return True

    @staticmethod
    def label(text):
        label = Gtk.Label(label=text)
        label.set_xalign(0)
        return label

    def on_activate(self, _app):
        window = Gtk.ApplicationWindow(application=self.app)
        window.set_title("Add secret")
        window.set_default_size(560, -1)
        window.set_resizable(False)
        window.set_position(WINDOW_POSITION)
        window.connect("delete-event", self.close)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        content.set_margin_top(18)
        content.set_margin_bottom(18)
        content.set_margin_start(18)
        content.set_margin_end(18)
        window.add(content)

        explanation = self.label(
            "Choose where the secret lives. YubiKey means one tap is required to read it."
        )
        explanation.set_line_wrap(True)
        content.pack_start(explanation, False, False, 0)

        grid = Gtk.Grid(column_spacing=14, row_spacing=10)
        content.pack_start(grid, False, False, 0)

        store = Gtk.ComboBoxText()
        store.append_text("pass")
        store.append_text("YubiKey")
        store.set_active(0)

        subtree = Gtk.ComboBoxText()
        choices = self.subtrees or ["no pass subtree"]
        for choice in choices:
            subtree.append_text(choice)
        subtree.set_active(choices.index(default_subtree(choices)))

        name = Gtk.Entry()
        value = value_entry()
        description = Gtk.Entry()
        for entry in (name, value, description):
            entry.set_hexpand(True)

        fields = (
            ("Store", store),
            ("Pass subtree", subtree),
            ("Name", name),
            ("Value", value),
            ("Description", description),
        )
        for row, (text, widget) in enumerate(fields):
            grid.attach(self.label(text), 0, row, 1, 1)
            grid.attach(widget, 1, row, 1, 1)

        def update_store(*_args):
            subtree.set_sensitive(store.get_active_text() == "pass")

        store.connect("changed", update_store)
        update_store()

        error = self.label("")
        error.get_style_context().add_class("error")
        content.pack_start(error, False, False, 0)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        actions.set_halign(Gtk.Align.END)
        content.pack_start(actions, False, False, 0)

        cancel = Gtk.Button(label="Cancel")
        cancel.connect("clicked", self.close)
        actions.pack_start(cancel, False, False, 0)

        def save(*_args):
            secret_name = name.get_text().strip()
            secret_value = value.get_text()
            if not secret_name:
                error.set_text("Name is required.")
                return
            if not secret_value:
                error.set_text("Value is required.")
                return
            self.finish(
                [
                    store.get_active_text(),
                    subtree.get_active_text(),
                    secret_name,
                    secret_value,
                    description.get_text(),
                ]
            )

        add = Gtk.Button(label="Add")
        add.connect("clicked", save)
        add.set_can_default(True)
        add.grab_default()
        actions.pack_start(add, False, False, 0)
        for entry in (name, value, description):
            entry.connect("activate", save)

        window.show_all()
        window.present()
        name.grab_focus()

    def run(self):
        self.app.run([])
        return self.exit_code


def check(subtrees):
    entry = value_entry()
    position = "center-always" if WINDOW_POSITION == Gtk.WindowPosition.CENTER_ALWAYS else "other"
    hidden = str(not entry.get_visibility()).lower()
    selected = default_subtree(subtrees) or "none"
    print(
        f"GTK 3 ready; position={position}; value-hidden={hidden}; "
        f"default-subtree={selected}"
    )
    return 0


def main():
    parser = argparse.ArgumentParser(description="Centered GTK form for adding a secret")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--subtree", action="append", default=[])
    args = parser.parse_args()
    if args.check:
        return check(args.subtree)
    return SecretAddDialog(args.subtree).run()


if __name__ == "__main__":
    raise SystemExit(main())
