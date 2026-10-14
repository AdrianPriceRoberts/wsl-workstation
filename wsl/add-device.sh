#!/usr/bin/env bash
# Run on a computer that already has your files to let a new one in.
#
#   add-device.sh DEVICE-ID [NAME]
#
# DEVICE-ID is what join.sh printed on the new computer.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 1 ]] || die "Usage: add-device.sh DEVICE-ID [NAME]"
id=$(tr -d '[:space:]' <<<"$1" | tr '[:lower:]' '[:upper:]')
valid_device_id "$id" || die "That doesn't look like a Syncthing device ID: $id"
name="${2:-}"
[[ -n $name ]] || read -rp "A name for the new computer (e.g. Laptop): " name

wait_for_syncthing
folder_known || die "This computer has no \"$SYNC_FOLDER_LABEL\" folder (id $SYNC_FOLDER_ID)."

step "Letting ${id:0:7} (${name:-new computer}) in"
share_folder_with "$id" "${name:-${id:0:7}}"
note "Done.  It may take a minute to connect; check with ~/wsl-workstation/wsl/check.sh"
