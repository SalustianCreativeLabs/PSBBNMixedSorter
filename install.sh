#!/usr/bin/env bash
#
# PSBBN Mixed Sorter — install / reapply
#
# Patches the PSBBN Definitive Project's Game-Installer.sh so the Game Collection
# is listed in a single alphabetical order across consoles (PS1 and PS2 interleaved)
# instead of one block per console.
#
# Copyright (C) 2026 SalustianCreativeLabs
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# Derived from the PSBBN Definitive Project by CosmicScale (GPL-3.0-or-later):
#   https://github.com/CosmicScale/PSBBN-Definitive-Project
#
# Usage:
#   ./install.sh                  # auto-detect the toolkit
#   ./install.sh --toolkit PATH   # explicit toolkit path
#   ./install.sh --revert         # restore the pristine Game-Installer.sh
#   ./install.sh --status         # report whether the patch is applied
#
set -uo pipefail

MARKER_OPEN="# >>> psbbn-mixed-sorter >>>"
MARKER_CLOSE="# <<< psbbn-mixed-sorter <<<"
ANCHOR='python3 "${HELPER_DIR}/game-selector.py" "$ALL_TITLES"'

TOOLKIT=""
ACTION="install"

ok()   { printf '[OK] %s\n'    "$1"; }
info() { printf '[..] %s\n'    "$1"; }
warn() { printf '[!!] %s\n'    "$1"; }
err()  { printf '[XX] %s\n'    "$1" >&2; }

usage() {
    sed -n '3,28p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --toolkit) TOOLKIT="${2:-}"; shift 2 || usage 1 ;;
        --revert)  ACTION="revert";  shift ;;
        --status)  ACTION="status";  shift ;;
        -h|--help) usage 0 ;;
        *) err "unknown option: $1"; usage 1 ;;
    esac
done

# ---------------------------------------------------------------- toolkit path

if [ -z "$TOOLKIT" ]; then
    for candidate in \
        "$HOME/PSBBN-Definitive-Project" \
        "/home/admin/PSBBN-Definitive-Project" \
        "$PWD/PSBBN-Definitive-Project" \
        "$PWD/../PSBBN-Definitive-Project"
    do
        if [ -f "$candidate/scripts/Game-Installer.sh" ]; then
            TOOLKIT="$candidate"
            break
        fi
    done
fi

if [ -z "$TOOLKIT" ] || [ ! -f "$TOOLKIT/scripts/Game-Installer.sh" ]; then
    err "PSBBN Definitive Project not found."
    err "Pass it explicitly:  ./install.sh --toolkit /path/to/PSBBN-Definitive-Project"
    exit 1
fi

TARGET="$TOOLKIT/scripts/Game-Installer.sh"
BACKUP="$TARGET.pristine"

# ---------------------------------------------------------------------- status

is_applied() { grep -qF "$MARKER_OPEN" "$TARGET"; }

if [ "$ACTION" = "status" ]; then
    info "toolkit: $TOOLKIT"
    if is_applied; then
        ok "patch is applied."
    else
        warn "patch is NOT applied (the collection groups by console)."
    fi
    [ -f "$BACKUP" ] && info "backup present: $BACKUP"
    exit 0
fi

# ---------------------------------------------------------------------- revert

if [ "$ACTION" = "revert" ]; then
    if [ ! -f "$BACKUP" ]; then
        err "no backup found at $BACKUP"
        err "restore with: cd '$TOOLKIT' && git checkout -- scripts/Game-Installer.sh"
        exit 1
    fi
    cp "$BACKUP" "$TARGET"
    chmod +x "$TARGET"
    ok "pristine Game-Installer.sh restored."
    exit 0
fi

# --------------------------------------------------------------------- install

info "toolkit: $TOOLKIT"

# Idempotent: nothing to do when already patched.
if is_applied; then
    ok "patch already applied, nothing to do."
    exit 0
fi

# Locate the anchor: the game-selector.py invocation.
anchor_line=$(grep -nF "$ANCHOR" "$TARGET" | cut -d: -f1 | head -1)
if [ -z "$anchor_line" ]; then
    warn "anchor not found — upstream changed the game-selector.py call."
    warn "patch NOT applied; the collection will keep grouping by console."
    warn "Please review this tool against the new upstream code."
    exit 2
fi

# The block must land after the `fi` that closes the selector's if.
fi_line=$((anchor_line + 1))
if [ "$(sed -n "${fi_line}p" "$TARGET" | tr -d '[:space:]')" != "fi" ]; then
    warn "unexpected structure: expected 'fi' on line ${fi_line}."
    warn "patch NOT applied (failing safe)."
    exit 2
fi

# Keep a pristine copy the first time around.
[ -f "$BACKUP" ] || cp "$TARGET" "$BACKUP"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

{
    sed -n "1,${fi_line}p" "$TARGET"
    cat <<'PATCH'

# >>> psbbn-mixed-sorter >>>
# Reorders selected.list into a single alphabetical run spanning PS1 and PS2,
# instead of one block per console. Games come first, then launchers (INC) and
# apps (APP) grouped at the end, so the collection opens straight on a game.
# Reuses the toolkit's own list-sorter.py, so series grouping, roman numerals
# and title normalisation behave exactly as upstream intends.
if [ -s "${SELECTED_LIST}" ]; then
    _pms_games="${SCRIPTS_DIR}/tmp/_pms_games.list"
    _pms_inc="${SCRIPTS_DIR}/tmp/_pms_inc.list"
    _pms_apps="${SCRIPTS_DIR}/tmp/_pms_apps.list"

    awk -F'|' '$4=="DVD"||$4=="CD"||$4=="POPS"||$4=="__.POPS"||$4=="SMB"' "${SELECTED_LIST}" > "$_pms_games"
    awk -F'|' '$4=="INC"' "${SELECTED_LIST}" > "$_pms_inc"
    awk -F'|' '$4=="APP"' "${SELECTED_LIST}" > "$_pms_apps"

    if python3 "${HELPER_DIR}/list-sorter.py" "$_pms_games" 2>>"${LOG_FILE}"; then
        cat "$_pms_games" "$_pms_inc" "$_pms_apps" > "${SELECTED_LIST}"
        echo "PSBBN Mixed Sorter: global alphabetical order applied." >> "${LOG_FILE}"
    else
        echo "[!] PSBBN Mixed Sorter: sort failed, keeping original order." >> "${LOG_FILE}"
    fi

    rm -f "$_pms_games" "$_pms_inc" "$_pms_apps"
fi
# <<< psbbn-mixed-sorter <<<
PATCH
    sed -n "$((fi_line + 1)),\$p" "$TARGET"
} > "$TMP"

# Never install a file that does not parse.
if ! bash -n "$TMP"; then
    err "the patched file has a syntax error. Nothing was changed."
    err "original left intact: $TARGET"
    exit 1
fi

cp "$TMP" "$TARGET"
chmod +x "$TARGET"

ok "patch applied after line ${fi_line}."
ok "pristine backup: $BACKUP"
ok "now run the PSBBN menu: 4 (Install Games and Apps) -> 2 (Add)."
