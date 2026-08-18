"""Structured parser/writer for a profiles/<name>/profile.conf.

profile.conf has a small, fixed set of fields (unlike pacman.conf, which is
a heavily-commented reference file worth preserving byte-for-byte). This
does a full, canonical rewrite instead of minimal-diff patching -- much
simpler, and safe here since these files don't carry hand-written
commentary beyond the header (mirrors profiledef_editor.py's approach).
"""

from __future__ import annotations

import re

SCALAR_FIELDS = [
    "PROFILE_DISPLAY_NAME",
    "PROFILE_SLUG",
    "PROFILE_ISO_LABEL",
    "PROFILE_ISO_PREFIX",
    "PROFILE_PLYMOUTH_THEME",
    "PROFILE_BOOT_ICONS_PKG_DIR_NAME",
    "PROFILE_BOOT_ICONS_REMOTE_REPO",
]

_SCALAR_RE = re.compile(r'^(\w+)="(.*)"$')

# (field, inline comment) -- regenerated every save, same wording each time.
_FIELD_COMMENTS = {
    "PROFILE_DISPLAY_NAME": "Shown in the Ploader/syslinux menu entries and the final build banner",
    "PROFILE_SLUG": "Short identifier: Ploader default_selection tag, boot-icon filename\n"
    "# (theme/icons/os_<slug>.png in profiles/<name>/ploader/), sudoers cleanup\n"
    "# glob, local-dev apt pin filename, Calamares try_remove package name suffix",
    "PROFILE_ISO_LABEL": "ISO9660 volume label (must match what the boot chain searches for)",
    "PROFILE_ISO_PREFIX": "Output filename prefix: $PROFILE_ISO_PREFIX-$BRANCH[...].iso",
    "PROFILE_PLYMOUTH_THEME": "Plymouth theme name installed by the profile's plymouth package",
    "PROFILE_BOOT_ICONS_PKG_DIR_NAME": "NOTE: currently unused (see profile.conf's own comment on this field)",
}


def parse_profile_conf(text):
    """Returns {"header": [lines], "scalars": {name: value}}."""
    lines = text.splitlines()

    header = []
    for line in lines:
        if line.startswith("#"):
            header.append(line)
        elif not line.strip():
            # A blank line ends the header block. Without this, the loop
            # would also swallow the *first* field's own comment (blank
            # line, then "# ..." right before it) into "header", which
            # render_profile_conf then duplicates since it re-emits that
            # same comment from _FIELD_COMMENTS.
            break
        else:
            break

    scalars = {}
    for line in lines:
        m = _SCALAR_RE.match(line)
        if m and m.group(1) in SCALAR_FIELDS:
            scalars[m.group(1)] = m.group(2)

    return {
        "header": header
        or [
            "# ==============================================================================",
            "# Profile metadata",
            "# Sourced by build-iso.sh -- plain KEY=VALUE, no logic here.",
            "# ==============================================================================",
        ],
        "scalars": scalars,
    }


def render_profile_conf(data):
    lines = list(data["header"])

    for name in SCALAR_FIELDS:
        value = data["scalars"].get(name, "")
        comment = _FIELD_COMMENTS.get(name)
        if comment is not None:
            lines.append("")
            lines.append(f"# {comment}")
        lines.append(f'{name}="{value}"')

    return "\n".join(lines) + "\n"
