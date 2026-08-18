#!/usr/bin/env python3
"""pearOS ISO Builder -- a Cubic-inspired GUI wrapper around ./build-iso.sh.

Structured the way Cubic itself is: a HeaderBar with Back/Next, one concern
per page (GtkStack, SLIDE transition), a big instructional label at the top
of each page. The Terminal page is a real Vte.Terminal: this GUI just
builds the build-iso.sh command line from the wizard's pages and streams
it into Vte. Anything build-iso.sh still asks live (sudo's password) is
answered by the user directly in that real terminal.

build-iso.sh is a generic engine: everything distro-specific (package
list, extra APT repo, branding, boot menu/theme) lives in
profiles/<name>/. This GUI's core feature on top of the old
single-profile editor is a Profiles page: select which profile is
"active" (used by every other page and by Build), duplicate one to start
a new one, rename, or delete.
"""

from __future__ import annotations

import glob
import os
import re
import shlex
import shutil
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("Vte", "2.91")

from gi.repository import Gdk, GLib, Gtk, Vte  # noqa: E402

try:
    gi.require_version("GtkSource", "3.0")
    from gi.repository import GtkSource  # noqa: E402
    HAS_GTKSOURCE = True
except (ValueError, ImportError):
    GtkSource = None
    HAS_GTKSOURCE = False

from packages_editor import parse_packages, render_packages
from profile_conf_editor import (
    SCALAR_FIELDS,
    parse_profile_conf,
    render_profile_conf,
)

REPO_ROOT = str(Path(__file__).resolve().parent.parent)
BUILD_ISO_SH = os.path.join(REPO_ROOT, "build-iso.sh")
PROFILES_DIR = os.path.join(REPO_ROOT, "profiles")

# Same required-files check build-iso.sh itself does before it will source a profile.
REQUIRED_PROFILE_FILES = ["profile.conf", "packages.list", "repo.sh", "packages.sh", "customize.sh"]

_NAME_RE = re.compile(r"^[a-z][a-z0-9_-]*$")


def list_profiles():
    if not os.path.isdir(PROFILES_DIR):
        return []
    names = []
    for entry in sorted(os.listdir(PROFILES_DIR)):
        profile_dir = os.path.join(PROFILES_DIR, entry)
        if not os.path.isdir(profile_dir):
            continue
        if all(os.path.isfile(os.path.join(profile_dir, f)) for f in REQUIRED_PROFILE_FILES):
            names.append(entry)
    return names


def profile_dir(name):
    return os.path.join(PROFILES_DIR, name)


def profile_file(name, filename):
    return os.path.join(PROFILES_DIR, name, filename)


def valid_new_profile_name(name):
    """Returns an error string, or None if the name is usable."""
    if not name:
        return "Name can't be empty."
    if not _NAME_RE.match(name):
        return "Use lowercase letters, digits, '-' or '_', starting with a letter."
    if os.path.isdir(profile_dir(name)):
        return f"A profile named '{name}' already exists."
    return None


def decode_wait_status(status):
    """Vte's "child-exited" signal (and GLib.child_watch_add's callback)
    pass the RAW waitpid() status word, not a plain exit code -- e.g. a
    real exit code of 1 shows up as 256 (1 << 8) unless decoded via
    WIFEXITED/WEXITSTATUS. Mirrors Python's subprocess convention: a
    signal-killed child is reported as the negative signal number.
    """
    if os.WIFEXITED(status):
        return os.WEXITSTATUS(status)
    if os.WIFSIGNALED(status):
        return -os.WTERMSIG(status)
    return status


def find_iso():
    matches = list(Path(REPO_ROOT).glob("*.iso"))
    if not matches:
        return None
    return str(max(matches, key=lambda p: p.stat().st_mtime))


def find_existing_targets():
    """Target rootfses left behind by earlier runs (build-iso.sh never
    deletes one automatically -- see --clean-target). Returns a list of
    (branch, with_nvidia, path) for every build/rootfs-target-* that looks
    real (has /etc), newest first, so the Start page can offer to chroot
    straight back into one instead of walking the whole wizard again.
    """
    build_dir = os.path.join(REPO_ROOT, "build")
    found = []
    for path in glob.glob(os.path.join(build_dir, "rootfs-target-*")):
        if not os.path.isdir(os.path.join(path, "etc")):
            continue
        name = os.path.basename(path)[len("rootfs-target-"):]
        with_nvidia = name.endswith("-nvidia")
        branch = name[: -len("-nvidia")] if with_nvidia else name
        found.append((branch, with_nvidia, path))
    found.sort(key=lambda t: os.path.getmtime(t[2]), reverse=True)
    return found


def instruction_label(text):
    """Cubic's big top-of-page instructional text: scale 1.25, wraps, fills."""
    label = Gtk.Label(label=text, xalign=0.0)
    label.set_line_wrap(True)
    label.set_justify(Gtk.Justification.FILL)
    label.set_margin_start(24)
    label.set_margin_end(24)
    label.set_margin_top(18)
    label.set_margin_bottom(18)
    label.get_style_context().add_class("instruction-label")
    return label


PAGE_START = "start"
PAGE_PROFILES = "profiles"
PAGE_PROFILE_CONF = "profile_conf"
PAGE_PACKAGES = "packages"
PAGE_REPO_SH = "repo_sh"
PAGE_CUSTOMIZE_SH = "customize_sh"
PAGE_BUILD = "build"
PAGE_TERMINAL = "terminal"
PAGE_FINISH = "finish"

PAGE_ORDER = [
    PAGE_START, PAGE_PROFILES, PAGE_PROFILE_CONF, PAGE_PACKAGES,
    PAGE_REPO_SH, PAGE_CUSTOMIZE_SH, PAGE_BUILD, PAGE_TERMINAL, PAGE_FINISH,
]

PAGE_TITLES = {
    PAGE_START: "Welcome",
    PAGE_PROFILES: "Profiles",
    PAGE_PROFILE_CONF: "Profile settings",
    PAGE_PACKAGES: "Packages",
    PAGE_REPO_SH: "Repository script",
    PAGE_CUSTOMIZE_SH: "Customize script",
    PAGE_BUILD: "Build",
    PAGE_TERMINAL: "Terminal",
    PAGE_FINISH: "Finish",
}


class ISOBuilderWindow(Gtk.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="pearOS ISO Builder")
        self.set_default_size(980, 740)

        self.child_pid = None
        self.session_active = False
        self._existing_targets = []
        self._chroot_shortcut_origin = None
        profiles = list_profiles()
        self.active_profile = "pear" if "pear" in profiles else (profiles[0] if profiles else None)

        css = Gtk.CssProvider()
        css.load_from_data(
            b".instruction-label { font-size: 130%; }"
            b".welcome-title { font-size: 220%; font-weight: bold; color: #7cb342; }"
        )
        Gtk.StyleContext.add_provider_for_screen(
            self.get_screen(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        self.header = Gtk.HeaderBar()
        self.header.set_show_close_button(True)
        self.header.set_title("pearOS ISO Builder")
        self.set_titlebar(self.header)
        header = self.header

        self.active_profile_label = Gtk.Label()
        self.active_profile_label.get_style_context().add_class("dim-label")
        header.pack_start(self.active_profile_label)

        self.back_button = Gtk.Button(label="Back")
        self.back_button.connect("clicked", self.on_back)
        header.pack_start(self.back_button)

        self.next_button = Gtk.Button(label="Next")
        self.next_button.get_style_context().add_class("suggested-action")
        self.next_button.connect("clicked", self.on_next)
        header.pack_end(self.next_button)

        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        self.add(self.stack)

        self.stack.add_named(self._build_start_page(), PAGE_START)
        self.stack.add_named(self._build_profiles_page(), PAGE_PROFILES)
        self.stack.add_named(self._build_profile_conf_page(), PAGE_PROFILE_CONF)
        self.stack.add_named(self._build_packages_page(), PAGE_PACKAGES)
        self.stack.add_named(
            self._build_script_page(
                "repo_sh", "repo.sh",
                "Edit the profile's repo.sh -- defines profile_setup_repo() / "
                "profile_teardown_repo(), which configure the profile's APT repo and "
                "keyring inside the chroot during every build.",
            ),
            PAGE_REPO_SH,
        )
        self.stack.add_named(
            self._build_script_page(
                "customize_sh", "customize.sh",
                "Edit the profile's customize.sh -- defines profile_customize(), which "
                "runs after packages are installed for branding and extra apps.",
            ),
            PAGE_CUSTOMIZE_SH,
        )
        self.stack.add_named(self._build_build_page(), PAGE_BUILD)
        self.stack.add_named(self._build_terminal_page(), PAGE_TERMINAL)
        self.stack.add_named(self._build_finish_page(), PAGE_FINISH)

        self._goto(PAGE_START)
        self.update_nav()

        self.connect("delete-event", self.on_close)

    # ---------------------------------------------------------------- #
    # Terminal keyboard shortcuts (copy/paste)
    # ---------------------------------------------------------------- #
    def _install_terminal_shortcuts(self, vte_widget):
        vte_widget.connect("key-press-event", self._on_terminal_key_press)

    def _on_terminal_key_press(self, vte_widget, event):
        ctrl = bool(event.state & Gdk.ModifierType.CONTROL_MASK)
        shift = bool(event.state & Gdk.ModifierType.SHIFT_MASK)
        if ctrl and shift and event.keyval in (Gdk.KEY_C, Gdk.KEY_c):
            if vte_widget.get_has_selection():
                vte_widget.copy_clipboard()
            return True
        if ctrl and shift and event.keyval in (Gdk.KEY_V, Gdk.KEY_v):
            vte_widget.paste_clipboard()
            return True
        return False

    def on_close(self, *_args):
        if self.child_pid:
            try:
                os.kill(self.child_pid, 15)
            except ProcessLookupError:
                pass
        return False

    # ---------------------------------------------------------------- #
    # Page: Start
    # ---------------------------------------------------------------- #
    def _build_start_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        title = Gtk.Label(label="pearOS ISO Builder")
        title.get_style_context().add_class("welcome-title")
        title.set_margin_top(32)
        title.set_margin_bottom(8)
        box.pack_start(title, False, False, 0)

        box.pack_start(instruction_label(
            "Build a Debian live ISO from a profile in profiles/<name>/. Pick or create a "
            "profile on the next page, review/edit its settings, then build. If a target "
            "rootfs already exists from an earlier run, Next (or the button below) jumps "
            "straight into a chroot shell in it instead."
        ), False, False, 0)

        content = Gtk.Grid(row_spacing=8, column_spacing=12)
        content.set_border_width(32)
        box.pack_start(content, False, False, 0)

        content.attach(Gtk.Label(label="Repository:", xalign=0.0), 0, 0, 1, 1)
        content.attach(Gtk.Label(label=REPO_ROOT, xalign=0.0), 1, 0, 1, 1)

        content.attach(Gtk.Label(label="Active profile:", xalign=0.0), 0, 1, 1, 1)
        self.start_active_profile_label = Gtk.Label(xalign=0.0)
        content.attach(self.start_active_profile_label, 1, 1, 1, 1)

        content.attach(Gtk.Label(label="Last built ISO:", xalign=0.0), 0, 2, 1, 1)
        self.iso_label = Gtk.Label(xalign=0.0)
        content.attach(self.iso_label, 1, 2, 1, 1)

        content.attach(Gtk.Label(label="Existing target rootfs:", xalign=0.0), 0, 3, 1, 1)
        self.start_target_label = Gtk.Label(xalign=0.0)
        content.attach(self.start_target_label, 1, 3, 1, 1)

        self.start_chroot_button = Gtk.Button(label="Continue in chroot")
        self.start_chroot_button.get_style_context().add_class("suggested-action")
        self.start_chroot_button.connect("clicked", self.on_start_chroot_shortcut)
        content.attach(self.start_chroot_button, 1, 4, 1, 1)

        return box

    def _reload_start_page(self):
        self.start_active_profile_label.set_text(self.active_profile or "(none -- create one)")
        iso_path = find_iso()
        self.iso_label.set_text(os.path.basename(iso_path) if iso_path else "none found")

        self._existing_targets = find_existing_targets()
        if self._existing_targets:
            branch, with_nvidia, _path = self._existing_targets[0]
            suffix = "-nvidia" if with_nvidia else ""
            extra = f" (+{len(self._existing_targets) - 1} more)" if len(self._existing_targets) > 1 else ""
            self.start_target_label.set_text(f"{branch}{suffix}{extra} -- not deleted automatically")
            self.start_chroot_button.set_sensitive(True)
        else:
            self.start_target_label.set_text("none found")
            self.start_chroot_button.set_sensitive(False)

    def on_start_chroot_shortcut(self, _button):
        # Jumps straight past Profiles/Profile settings/Packages/Repo/
        # Customize/Build into the chroot shell for the most recently
        # touched existing target, same idea as ../iso/iso-builder's
        # "Start Airootfs Console" button -- no point walking the whole
        # wizard again just to tick --chroot on the Build page when
        # build-iso.sh is going to skip repo/package install anyway.
        if not self._existing_targets:
            return
        branch, with_nvidia, _path = self._existing_targets[0]
        model = self.branch_combo.get_model()
        for i, row in enumerate(model):
            if row[0] == branch:
                self.branch_combo.set_active(i)
                break
        self.nvidia_check.set_active(with_nvidia)
        self.chroot_check.set_active(True)
        self.launch_session()
        self._chroot_shortcut_origin = PAGE_START
        self.update_nav()

    # ---------------------------------------------------------------- #
    # Page: Profiles -- select, create, duplicate, rename, delete
    # ---------------------------------------------------------------- #
    def _build_profiles_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.pack_start(instruction_label(
            "Every profile under profiles/<name>/ carries its own package list, APT "
            "repo and branding. Pick the one to edit/build below, or "
            "create a new one (starting as a copy of an existing profile, since its "
            "scripts need real content)."
        ), False, False, 0)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        content.set_border_width(20)
        box.pack_start(content, True, True, 0)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        content.pack_start(scroller, True, True, 0)

        self.profiles_grid = Gtk.Grid(row_spacing=6, column_spacing=8)
        scroller.add(self.profiles_grid)

        button_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        new_button = Gtk.Button(label="New profile...")
        new_button.get_style_context().add_class("suggested-action")
        new_button.connect("clicked", lambda *_: self._prompt_new_profile(self.active_profile))
        button_row.pack_start(new_button, False, False, 0)
        content.pack_start(button_row, False, False, 0)

        self.profiles_status_label = Gtk.Label(xalign=0.0)
        self.profiles_status_label.get_style_context().add_class("dim-label")
        content.pack_start(self.profiles_status_label, False, False, 0)

        self._reload_profiles_page()
        return box

    def _reload_profiles_page(self):
        for child in list(self.profiles_grid.get_children()):
            self.profiles_grid.remove(child)

        profiles = list_profiles()
        if self.active_profile not in profiles:
            self.active_profile = profiles[0] if profiles else None

        radio_group_head = None
        for row, name in enumerate(profiles):
            is_active = name == self.active_profile
            radio = Gtk.RadioButton.new_with_label_from_widget(radio_group_head, name)
            if radio_group_head is None:
                radio_group_head = radio
            radio.set_active(is_active)
            radio.connect("toggled", lambda r, n=name: r.get_active() and self._set_active_profile(n))
            self.profiles_grid.attach(radio, 0, row, 1, 1)

            dup_button = Gtk.Button(label="Duplicate")
            dup_button.connect("clicked", lambda _b, n=name: self._prompt_new_profile(n))
            self.profiles_grid.attach(dup_button, 1, row, 1, 1)

            rename_button = Gtk.Button(label="Rename")
            rename_button.connect("clicked", lambda _b, n=name: self._prompt_rename_profile(n))
            self.profiles_grid.attach(rename_button, 2, row, 1, 1)

            delete_button = Gtk.Button(label="Delete")
            delete_button.get_style_context().add_class("destructive-action")
            delete_button.connect("clicked", lambda _b, n=name: self._confirm_delete_profile(n))
            delete_button.set_sensitive(len(profiles) > 1)
            self.profiles_grid.attach(delete_button, 3, row, 1, 1)

        self.profiles_grid.show_all()
        if not profiles:
            self.profiles_status_label.set_text("No profiles found -- create one to get started.")
        else:
            self.profiles_status_label.set_text("")
        self._refresh_active_profile_label()

    def _set_active_profile(self, name):
        self.active_profile = name
        self._refresh_active_profile_label()

    def _refresh_active_profile_label(self):
        self.active_profile_label.set_text(f"Profile: {self.active_profile}" if self.active_profile else "No profile")

    def _prompt_new_profile(self, source_default):
        profiles = list_profiles()
        if not profiles:
            self.profiles_status_label.set_text("Can't duplicate -- no existing profile to start from.")
            return

        dialog = Gtk.Dialog(title="New profile", transient_for=self, modal=True)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, "Create", Gtk.ResponseType.OK)
        content = dialog.get_content_area()
        content.set_border_width(16)
        content.set_spacing(8)

        grid = Gtk.Grid(row_spacing=8, column_spacing=12)
        content.add(grid)

        grid.attach(Gtk.Label(label="New profile name:", xalign=0.0), 0, 0, 1, 1)
        name_entry = Gtk.Entry()
        name_entry.set_hexpand(True)
        grid.attach(name_entry, 1, 0, 1, 1)

        grid.attach(Gtk.Label(label="Start as a copy of:", xalign=0.0), 0, 1, 1, 1)
        source_combo = Gtk.ComboBoxText()
        for i, name in enumerate(profiles):
            source_combo.append_text(name)
            if name == source_default:
                source_combo.set_active(i)
        if source_combo.get_active() < 0 and profiles:
            source_combo.set_active(0)
        grid.attach(source_combo, 1, 1, 1, 1)

        error_label = Gtk.Label(xalign=0.0)
        error_label.get_style_context().add_class("error")
        grid.attach(error_label, 0, 2, 2, 1)

        dialog.show_all()
        while True:
            response = dialog.run()
            if response != Gtk.ResponseType.OK:
                dialog.destroy()
                return
            new_name = name_entry.get_text().strip()
            error = valid_new_profile_name(new_name)
            if error:
                error_label.set_text(error)
                continue
            source = source_combo.get_active_text()
            dialog.destroy()
            break

        try:
            shutil.copytree(profile_dir(source), profile_dir(new_name))
        except OSError as exc:
            self.profiles_status_label.set_text(f"Failed to create '{new_name}': {exc}")
            return
        self.active_profile = new_name
        self._reload_profiles_page()
        self.profiles_status_label.set_text(f"Created '{new_name}' from '{source}'.")

    def _prompt_rename_profile(self, name):
        dialog = Gtk.Dialog(title=f"Rename '{name}'", transient_for=self, modal=True)
        dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL, "Rename", Gtk.ResponseType.OK)
        content = dialog.get_content_area()
        content.set_border_width(16)
        entry = Gtk.Entry(text=name)
        entry.set_activates_default(True)
        content.add(entry)
        error_label = Gtk.Label(xalign=0.0)
        content.add(error_label)
        dialog.set_default_response(Gtk.ResponseType.OK)
        dialog.show_all()

        while True:
            response = dialog.run()
            if response != Gtk.ResponseType.OK:
                dialog.destroy()
                return
            new_name = entry.get_text().strip()
            if new_name == name:
                dialog.destroy()
                return
            error = valid_new_profile_name(new_name)
            if error:
                error_label.set_text(error)
                continue
            dialog.destroy()
            break

        try:
            os.rename(profile_dir(name), profile_dir(new_name))
        except OSError as exc:
            self.profiles_status_label.set_text(f"Failed to rename: {exc}")
            return
        if self.active_profile == name:
            self.active_profile = new_name
        self._reload_profiles_page()
        self.profiles_status_label.set_text(f"Renamed '{name}' to '{new_name}'.")

    def _confirm_delete_profile(self, name):
        if len(list_profiles()) <= 1:
            self.profiles_status_label.set_text("Can't delete the only remaining profile.")
            return
        dialog = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            message_type=Gtk.MessageType.WARNING,
            buttons=Gtk.ButtonsType.YES_NO,
            text=f"Delete profile '{name}'?",
        )
        dialog.format_secondary_text("This permanently removes profiles/%s/ from disk." % name)
        response = dialog.run()
        dialog.destroy()
        if response != Gtk.ResponseType.YES:
            return
        try:
            shutil.rmtree(profile_dir(name))
        except OSError as exc:
            self.profiles_status_label.set_text(f"Failed to delete: {exc}")
            return
        if self.active_profile == name:
            self.active_profile = None
        self._reload_profiles_page()
        self.profiles_status_label.set_text(f"Deleted '{name}'.")

    # ---------------------------------------------------------------- #
    # Page: Profile settings (profile.conf)
    # ---------------------------------------------------------------- #
    def _build_profile_conf_page(self):
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        outer.pack_start(instruction_label(
            "Edit the active profile's profile.conf -- display name, package-name "
            "slug, ISO label/prefix, and Plymouth theme name."
        ), False, False, 0)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        outer.pack_start(scroller, True, True, 0)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        box.set_border_width(24)
        scroller.add(box)

        grid = Gtk.Grid(row_spacing=8, column_spacing=12)
        box.pack_start(grid, False, False, 0)

        captions = {
            "PROFILE_DISPLAY_NAME": "Display name",
            "PROFILE_SLUG": "Slug",
            "PROFILE_ISO_LABEL": "ISO volume label",
            "PROFILE_ISO_PREFIX": "ISO filename prefix",
            "PROFILE_PLYMOUTH_THEME": "Plymouth theme name",
            "PROFILE_BOOT_ICONS_PKG_DIR_NAME": "Boot-icons package dir name (unused)",
            "PROFILE_BOOT_ICONS_REMOTE_REPO": "Boot-icons remote repo URL (unused)",
        }
        self.profile_conf_entries = {}
        row = 0
        for key in SCALAR_FIELDS:
            grid.attach(Gtk.Label(label=captions.get(key, key) + ":", xalign=0.0), 0, row, 1, 1)
            entry = Gtk.Entry()
            entry.set_hexpand(True)
            grid.attach(entry, 1, row, 1, 1)
            self.profile_conf_entries[key] = entry
            row += 1

        save_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.profile_conf_status_label = Gtk.Label(xalign=0.0)
        self.profile_conf_status_label.get_style_context().add_class("dim-label")
        save_row.pack_start(self.profile_conf_status_label, True, True, 0)
        reload_button = Gtk.Button(label="Reload")
        reload_button.connect("clicked", lambda *_: self._reload_profile_conf_page())
        save_row.pack_start(reload_button, False, False, 0)
        save_button = Gtk.Button(label="Save profile.conf")
        save_button.get_style_context().add_class("suggested-action")
        save_button.connect("clicked", lambda *_: self._save_profile_conf())
        save_row.pack_start(save_button, False, False, 0)
        box.pack_start(save_row, False, False, 0)

        self._reload_profile_conf_page()
        return outer

    def _reload_profile_conf_page(self):
        if not self.active_profile:
            self.profile_conf_status_label.set_text("No active profile.")
            return
        path = profile_file(self.active_profile, "profile.conf")
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except OSError as exc:
            self.profile_conf_status_label.set_text(f"Could not read {path}: {exc}")
            return
        self._profile_conf_path = path
        self._profile_conf_data = parse_profile_conf(text)

        for key, entry in self.profile_conf_entries.items():
            entry.set_text(self._profile_conf_data["scalars"].get(key, ""))

        self.profile_conf_status_label.set_text("")

    def _save_profile_conf(self):
        if not hasattr(self, "_profile_conf_data") or not self.active_profile:
            return
        for key, entry in self.profile_conf_entries.items():
            self._profile_conf_data["scalars"][key] = entry.get_text()

        try:
            with open(self._profile_conf_path, "w", encoding="utf-8") as fh:
                fh.write(render_profile_conf(self._profile_conf_data))
        except OSError as exc:
            self.profile_conf_status_label.set_text(f"Failed to save: {exc}")
            return
        self._reload_profile_conf_page()
        self.profile_conf_status_label.set_text("Saved.")

    # ---------------------------------------------------------------- #
    # Page: Packages (profiles/<name>/packages.list)
    # ---------------------------------------------------------------- #
    def _build_packages_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.packages_instruction = instruction_label("Select packages to install.")
        box.pack_start(self.packages_instruction, False, False, 0)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        content.set_border_width(16)
        box.pack_start(content, True, True, 0)

        top_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.package_search = Gtk.SearchEntry()
        self.package_search.set_placeholder_text("Filter packages...")
        self.package_search.connect("search-changed", lambda *_: self.package_listbox.invalidate_filter())
        top_row.pack_start(self.package_search, True, True, 0)

        self.package_count_label = Gtk.Label()
        self.package_count_label.get_style_context().add_class("dim-label")
        top_row.pack_start(self.package_count_label, False, False, 0)
        content.pack_start(top_row, False, False, 0)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        content.pack_start(scroller, True, True, 0)

        self.package_listbox = Gtk.ListBox()
        self.package_listbox.set_filter_func(self._filter_package_row)
        scroller.add(self.package_listbox)

        add_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.new_package_entry = Gtk.Entry()
        self.new_package_entry.set_placeholder_text("package-name")
        self.new_package_entry.connect("activate", lambda *_: self._add_package())
        add_row.pack_start(self.new_package_entry, True, True, 0)
        add_button = Gtk.Button(label="Add package")
        add_button.connect("clicked", lambda *_: self._add_package())
        add_row.pack_start(add_button, False, False, 0)
        content.pack_start(add_row, False, False, 0)

        save_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.packages_status_label = Gtk.Label(xalign=0.0)
        self.packages_status_label.get_style_context().add_class("dim-label")
        save_row.pack_start(self.packages_status_label, True, True, 0)
        reload_button = Gtk.Button(label="Reload")
        reload_button.connect("clicked", lambda *_: self._reload_packages_page())
        save_row.pack_start(reload_button, False, False, 0)
        save_button = Gtk.Button(label="Save packages.list")
        save_button.get_style_context().add_class("suggested-action")
        save_button.connect("clicked", lambda *_: self._save_packages())
        save_row.pack_start(save_button, False, False, 0)
        content.pack_start(save_row, False, False, 0)

        self._reload_packages_page()
        return box

    def _reload_packages_page(self):
        self.package_entries = []
        for child in list(self.package_listbox.get_children()):
            self.package_listbox.remove(child)
        if not self.active_profile:
            self.packages_status_label.set_text("No active profile.")
            return
        path = profile_file(self.active_profile, "packages.list")
        self.packages_instruction.set_text(
            f"Select packages to install.\nEditing profiles/{self.active_profile}/packages.list "
            "-- this is the mmdebstrap bootstrap list."
        )
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except OSError as exc:
            self.packages_status_label.set_text(f"Could not read {path}: {exc}")
            return
        self._packages_path = path
        self.package_entries = parse_packages(text)
        for entry in self.package_entries:
            if entry["kind"] != "package":
                continue
            row = Gtk.ListBoxRow()
            check = Gtk.CheckButton(label=entry["name"])
            check.set_active(entry["enabled"])
            check.connect("toggled", lambda c, e=entry: e.__setitem__("enabled", c.get_active()))
            row.add(check)
            row.package_name = entry["name"]
            self.package_listbox.add(row)
        self.package_listbox.show_all()
        self._update_package_count()
        self.packages_status_label.set_text("")

    def _filter_package_row(self, row):
        query = self.package_search.get_text().strip().lower()
        return not query or query in getattr(row, "package_name", "").lower()

    def _update_package_count(self):
        total = sum(1 for e in self.package_entries if e["kind"] == "package")
        enabled = sum(1 for e in self.package_entries if e["kind"] == "package" and e["enabled"])
        self.package_count_label.set_text(f"{enabled} / {total} enabled")

    def _add_package(self):
        name = self.new_package_entry.get_text().strip()
        if not name:
            return
        if any(e["kind"] == "package" and e["name"] == name for e in self.package_entries):
            self.packages_status_label.set_text(f"\"{name}\" is already in the list.")
            return
        entry = {"kind": "package", "name": name, "enabled": True}
        self.package_entries.append(entry)
        row = Gtk.ListBoxRow()
        check = Gtk.CheckButton(label=name)
        check.set_active(True)
        check.connect("toggled", lambda c, e=entry: e.__setitem__("enabled", c.get_active()))
        row.add(check)
        row.package_name = name
        row.show_all()
        self.package_listbox.add(row)
        self.new_package_entry.set_text("")
        self._update_package_count()

    def _save_packages(self):
        if not getattr(self, "_packages_path", None):
            return
        try:
            with open(self._packages_path, "w", encoding="utf-8") as fh:
                fh.write(render_packages(self.package_entries))
        except OSError as exc:
            self.packages_status_label.set_text(f"Failed to save: {exc}")
            return
        self._update_package_count()
        self.packages_status_label.set_text("Saved.")

    # ---------------------------------------------------------------- #
    # Pages: raw script editors (repo.sh, customize.sh)
    # ---------------------------------------------------------------- #
    def _build_script_page(self, key, filename, instructions):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.pack_start(instruction_label(instructions), False, False, 0)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        content.set_border_width(16)
        box.pack_start(content, True, True, 0)

        path_label = Gtk.Label(xalign=0.0)
        path_label.get_style_context().add_class("dim-label")
        content.pack_start(path_label, False, False, 0)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        content.pack_start(scroller, True, True, 0)

        if HAS_GTKSOURCE:
            buffer_ = GtkSource.Buffer()
            lang_manager = GtkSource.LanguageManager.get_default()
            language = lang_manager.get_language("sh")
            if language:
                buffer_.set_language(language)
            buffer_.set_highlight_syntax(True)
            view = GtkSource.View.new_with_buffer(buffer_)
            view.set_show_line_numbers(True)
            view.set_tab_width(4)
        else:
            buffer_ = Gtk.TextBuffer()
            view = Gtk.TextView.new_with_buffer(buffer_)
        view.set_monospace(True)
        scroller.add(view)

        save_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        status_label = Gtk.Label(xalign=0.0)
        status_label.get_style_context().add_class("dim-label")
        save_row.pack_start(status_label, True, True, 0)
        reload_button = Gtk.Button(label="Reload")
        save_row.pack_start(reload_button, False, False, 0)
        save_button = Gtk.Button(label=f"Save {filename}")
        save_button.get_style_context().add_class("suggested-action")
        save_row.pack_start(save_button, False, False, 0)
        content.pack_start(save_row, False, False, 0)

        setattr(self, f"_{key}_buffer", buffer_)
        setattr(self, f"_{key}_path_label", path_label)
        setattr(self, f"_{key}_status_label", status_label)
        setattr(self, f"_{key}_filename", filename)

        reload_button.connect("clicked", lambda *_: self._reload_script_page(key))
        save_button.connect("clicked", lambda *_: self._save_script_page(key))

        self._reload_script_page(key)
        return box

    def _reload_script_page(self, key):
        buffer_ = getattr(self, f"_{key}_buffer")
        path_label = getattr(self, f"_{key}_path_label")
        status_label = getattr(self, f"_{key}_status_label")
        filename = getattr(self, f"_{key}_filename")
        if not self.active_profile:
            buffer_.set_text("")
            path_label.set_text("(no active profile)")
            status_label.set_text("")
            return
        path = profile_file(self.active_profile, filename)
        setattr(self, f"_{key}_path", path)
        path_label.set_text(os.path.relpath(path, REPO_ROOT))
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except OSError as exc:
            buffer_.set_text("")
            status_label.set_text(f"Could not read: {exc}")
            return
        buffer_.set_text(text)
        status_label.set_text("")

    def _save_script_page(self, key):
        path = getattr(self, f"_{key}_path", None)
        status_label = getattr(self, f"_{key}_status_label")
        if not path:
            return
        buffer_ = getattr(self, f"_{key}_buffer")
        start, end = buffer_.get_bounds()
        text = buffer_.get_text(start, end, True)
        try:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
        except OSError as exc:
            status_label.set_text(f"Failed to save: {exc}")
            return
        status_label.set_text("Saved.")

    # ---------------------------------------------------------------- #
    # Page: Build
    # ---------------------------------------------------------------- #
    def _build_build_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.pack_start(instruction_label(
            "Build the active profile's ISO with build-iso.sh."
        ), False, False, 0)

        content = Gtk.Grid(row_spacing=10, column_spacing=12)
        content.set_border_width(32)
        box.pack_start(content, False, False, 0)

        content.attach(Gtk.Label(label="Profile:", xalign=0.0), 0, 0, 1, 1)
        self.build_profile_label = Gtk.Label(xalign=0.0)
        content.attach(self.build_profile_label, 1, 0, 1, 1)

        content.attach(Gtk.Label(label="Branch:", xalign=0.0), 0, 1, 1, 1)
        self.branch_combo = Gtk.ComboBoxText()
        for branch in ("stable", "forky", "rolling"):
            self.branch_combo.append_text(branch)
        self.branch_combo.set_active(0)
        content.attach(self.branch_combo, 1, 1, 1, 1)

        content.attach(Gtk.Label(label="Version (optional):", xalign=0.0), 0, 2, 1, 1)
        self.version_entry = Gtk.Entry()
        self.version_entry.set_placeholder_text("e.g. 0.1-beta")
        content.attach(self.version_entry, 1, 2, 1, 1)

        self.local_check = Gtk.CheckButton(label="--local (install from locally built .deb packages instead of the repo)")
        content.attach(self.local_check, 0, 3, 2, 1)

        self.nvidia_check = Gtk.CheckButton(label="--nvidia (include proprietary NVIDIA/Broadcom drivers)")
        content.attach(self.nvidia_check, 0, 4, 2, 1)

        self.clean_base_check = Gtk.CheckButton(label="--clean-base (delete the cached base chroot and rebuild from scratch)")
        content.attach(self.clean_base_check, 0, 5, 2, 1)

        self.clean_target_check = Gtk.CheckButton(
            label="--clean-target (delete the working target rootfs and re-clone it, even "
            "if one already exists from a previous run)"
        )
        content.attach(self.clean_target_check, 0, 6, 2, 1)

        self.chroot_check = Gtk.CheckButton(
            label="--chroot (drop into a shell in the rootfs right before compression, in "
            "this same Terminal, then stop -- the target rootfs is never deleted "
            "automatically, so any run afterward, --chroot or plain, reuses it as-is)"
        )
        content.attach(self.chroot_check, 0, 7, 2, 1)

        return box

    def _reload_build_page(self):
        self.build_profile_label.set_text(self.active_profile or "(none -- go to Profiles)")

    def build_args(self):
        if not self.active_profile:
            return None
        args = ["--profile", self.active_profile, "--branch", self.branch_combo.get_active_text() or "stable"]
        version = self.version_entry.get_text().strip()
        if version:
            args += ["--version", version]
        if self.local_check.get_active():
            args.append("--local")
        if self.nvidia_check.get_active():
            args.append("--nvidia")
        if self.clean_base_check.get_active():
            args.append("--clean-base")
        if self.clean_target_check.get_active():
            args.append("--clean-target")
        if self.chroot_check.get_active():
            args.append("--chroot")
        return args

    # ---------------------------------------------------------------- #
    # Page: Terminal (Vte owns the pty, no scripting of prompts)
    # ---------------------------------------------------------------- #
    def _build_terminal_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.pack_start(instruction_label(
            "Running. Answer any prompts here, same as a real terminal."
        ), False, False, 0)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        content.set_border_width(10)
        box.pack_start(content, True, True, 0)

        header_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.terminal_status = Gtk.Label(label="Idle", xalign=0.0)
        header_row.pack_start(self.terminal_status, True, True, 0)
        self.stop_button = Gtk.Button(label="Stop")
        self.stop_button.connect("clicked", self.on_stop)
        self.stop_button.set_sensitive(False)
        header_row.pack_end(self.stop_button, False, False, 0)
        content.pack_start(header_row, False, False, 0)

        term_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.vte = Vte.Terminal()
        self.vte.set_scrollback_lines(20000)
        self._install_terminal_shortcuts(self.vte)
        self.vte.connect("child-exited", self.on_child_exited)
        term_row.pack_start(self.vte, True, True, 0)

        scrollbar = Gtk.Scrollbar(orientation=Gtk.Orientation.VERTICAL)
        scrollbar.set_adjustment(self.vte.get_vadjustment())
        term_row.pack_start(scrollbar, False, False, 0)

        content.pack_start(term_row, True, True, 0)
        return box

    def launch_session(self):
        args = self.build_args()
        if not args:
            self.terminal_status.set_text("No active profile -- create one first.")
            return
        # Reset here, not just after a shortcut call: a normal launch must
        # not inherit a stale origin from an earlier chroot shortcut. The
        # shortcut callers (on_start_chroot_shortcut, on_next) re-set this
        # right after calling launch_session().
        self._chroot_shortcut_origin = None
        argv = ["sudo", "--", BUILD_ISO_SH] + args
        cmd_text = " ".join(shlex.quote(a) for a in argv)

        self.vte.reset(True, True)
        self.terminal_status.set_text("Running: " + cmd_text)
        self.command_summary_label.set_text(cmd_text)
        self.stop_button.set_sensitive(True)
        self.session_active = True

        self.vte.spawn_async(
            Vte.PtyFlags.DEFAULT,
            REPO_ROOT,
            argv,
            [],
            GLib.SpawnFlags.DEFAULT,
            None,
            None,
            -1,
            None,
            self._on_spawn_complete,
        )

        self._goto(PAGE_TERMINAL)
        self.vte.grab_focus()
        self.update_nav()

    def _on_spawn_complete(self, terminal, pid, error):
        if error:
            self.terminal_status.set_text(f"Failed to launch: {error}")
            self.session_active = False
            self.stop_button.set_sensitive(False)
            self.update_nav()
            return
        self.child_pid = pid

    def on_stop(self, _button):
        if self.child_pid:
            try:
                os.kill(self.child_pid, 15)
            except ProcessLookupError:
                pass

    def on_child_exited(self, _terminal, exit_code):
        exit_code = decode_wait_status(exit_code)
        self.session_active = False
        self.child_pid = None
        self.stop_button.set_sensitive(False)
        self.terminal_status.set_text(f"Finished (exit code {exit_code})")

        if exit_code == 0:
            self.finish_label.set_text("build-iso.sh exited normally (code 0).")
            self._goto(PAGE_FINISH)
        else:
            self.finish_label.set_text(
                f"build-iso.sh exited with code {exit_code}. Check the terminal output "
                "on the previous page for details."
            )
        self.update_nav()

    # ---------------------------------------------------------------- #
    # Page: Finish
    # ---------------------------------------------------------------- #
    def _build_finish_page(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        box.pack_start(instruction_label("Finished."), False, False, 0)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        content.set_border_width(32)
        box.pack_start(content, False, False, 0)
        self.finish_label = Gtk.Label(xalign=0.0)
        self.finish_label.set_line_wrap(True)
        content.pack_start(self.finish_label, False, False, 0)
        self.command_summary_label = Gtk.Label(xalign=0.0)
        self.command_summary_label.set_line_wrap(True)
        self.command_summary_label.set_selectable(True)
        self.command_summary_label.get_style_context().add_class("monospace")
        content.pack_start(self.command_summary_label, False, False, 0)
        return box

    # ---------------------------------------------------------------- #
    # Navigation
    #
    # Gtk.Stack.get_visible_child_name() returns None until the stack is
    # realized (first show_all()), so page state is tracked in Python
    # instead of queried back from the widget.
    # ---------------------------------------------------------------- #
    _RELOAD_ON_SHOW = {
        PAGE_START: "_reload_start_page",
        PAGE_PROFILES: "_reload_profiles_page",
        PAGE_PROFILE_CONF: "_reload_profile_conf_page",
        PAGE_PACKAGES: "_reload_packages_page",
        PAGE_BUILD: "_reload_build_page",
    }

    def _goto(self, name):
        self._current_page = name
        self.stack.set_visible_child_name(name)
        self.header.set_title(PAGE_TITLES.get(name, "pearOS ISO Builder"))
        self._refresh_active_profile_label()
        if name == PAGE_REPO_SH:
            self._reload_script_page("repo_sh")
        elif name == PAGE_CUSTOMIZE_SH:
            self._reload_script_page("customize_sh")
        elif name in self._RELOAD_ON_SHOW:
            getattr(self, self._RELOAD_ON_SHOW[name])()

    def _current_index(self):
        return PAGE_ORDER.index(self._current_page)

    def update_nav(self):
        page = self._current_page
        idx = self._current_index()
        self.back_button.set_sensitive(idx > 0 and not (page == PAGE_TERMINAL and self.session_active))
        if page == PAGE_BUILD:
            self.next_button.set_label("Build")
            self.next_button.set_sensitive(self.active_profile is not None)
        elif page == PAGE_TERMINAL:
            self.next_button.set_label("Next")
            self.next_button.set_sensitive(not self.session_active)
        elif page == PAGE_FINISH:
            self.next_button.set_label("Start Over")
            self.next_button.set_sensitive(True)
        else:
            self.next_button.set_label("Next")
            self.next_button.set_sensitive(True)

    def on_back(self, _button):
        if self._current_page == PAGE_TERMINAL and self._chroot_shortcut_origin:
            # Landed here via the Start page's chroot shortcut, not by
            # walking the wizard forward -- PAGE_ORDER's predecessor
            # (Build) was never actually visited, so Back needs to return
            # to where the shortcut was launched from instead.
            self._goto(self._chroot_shortcut_origin)
            self.update_nav()
            return
        idx = self._current_index()
        if idx == 0:
            return
        self._goto(PAGE_ORDER[idx - 1])
        self.update_nav()

    def on_next(self, _button):
        page = self._current_page
        if page == PAGE_START and self._existing_targets:
            # build-iso.sh never deletes an existing target rootfs and
            # skips repo/package install for one straight to chroot/
            # packaging -- so there's no point making Next walk through
            # Profiles/Packages/Repo/Customize/Build first. Same shortcut
            # as the dedicated "Continue in chroot" button.
            self.on_start_chroot_shortcut(None)
            return
        if page == PAGE_BUILD:
            self.launch_session()
            return
        if page == PAGE_FINISH:
            self._goto(PAGE_START)
            self.update_nav()
            return
        idx = self._current_index()
        if idx + 1 < len(PAGE_ORDER):
            self._goto(PAGE_ORDER[idx + 1])
        self.update_nav()


class ISOBuilderApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="xyz.pearos.isobuilder")

    def do_activate(self):
        win = ISOBuilderWindow(self)
        win.show_all()


def main():
    if os.geteuid() == 0:
        dialog = Gtk.MessageDialog(
            flags=0,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text="Do not run as root",
        )
        dialog.format_secondary_text(
            "Run this GUI as your normal user. It will ask for your sudo "
            "password (directly in the terminal page) only when "
            "build-iso.sh itself needs it."
        )
        dialog.run()
        raise SystemExit(1)
    app = ISOBuilderApp()
    app.run()


if __name__ == "__main__":
    main()
