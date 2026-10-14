#!/usr/bin/env bash
# Connect this (new) computer to one that already has your synced files.
#
#   join.sh [DEVICE-ID]
#
# DEVICE-ID is the other computer's Syncthing ID; it's asked for if not
# given.  That computer is made an "introducer", so this one also learns
# about every other computer it shares the folder with.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

wait_for_syncthing
folder_known || die "No \"$SYNC_FOLDER_LABEL\" folder yet; run install.sh first."
me=$(my_device_id)

id="${1:-}"
if [[ -z $id ]]; then
  cat <<EOF

On a computer that already has your files, open http://localhost:8384 and
choose Actions > Show ID (or run: syncthing cli show system | grep myID).
EOF
  read -rp "Paste its device ID here: " id
fi
id=$(tr -d '[:space:]' <<<"$id" | tr '[:lower:]' '[:upper:]')
valid_device_id "$id" || die "That doesn't look like a Syncthing device ID: $id"
[[ $id != "$me" ]] || die "That's this computer's own ID; use the other computer's."
read -rp "A name for that computer (e.g. Desktop): " name

step "Connecting to ${id:0:7} ($name)"
share_folder_with "$id" "${name:-${id:0:7}}" --introducer

step "Last step: on $name"
cat <<EOF
    Approve this computer there, either:
      - run:  ~/wsl-workstation/wsl/add-device.sh $me
      - or open http://localhost:8384 on $name, click "Add Device" on the
        prompt about this computer, and tick "$SYNC_FOLDER_LABEL" under Sharing.

    Files then start arriving in $SYNC_DIR.  Check progress any time with
    ~/wsl-workstation/wsl/check.sh
EOF
