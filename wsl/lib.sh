# Shared helpers for the scripts in this directory.  Source it, don't run it.

here="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
# shellcheck source=../config.env
source "$here/../config.env"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die()  { printf '\n\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# Wait until the local Syncthing answers on its API (up to a minute).
wait_for_syncthing() {
  for _ in $(seq 60); do
    syncthing cli show system >/dev/null 2>&1 && return 0
    sleep 1
  done
  die "Syncthing is not answering.  Check: systemctl --user status syncthing"
}

my_device_id() {
  syncthing cli show system | grep -o '"myID": *"[^"]*"' | cut -d'"' -f4
}

valid_device_id() {
  [[ "$1" =~ ^[A-Z2-7]{7}(-[A-Z2-7]{7}){7}$ ]]
}

device_known() {
  syncthing cli config devices list | grep -qx "$1"
}

folder_known() {
  syncthing cli config folders list | grep -qx "$SYNC_FOLDER_ID"
}

# Make DEVICE-ID a known device (named NAME) that shares the sync folder.
share_folder_with() {
  local id="$1" name="$2"; shift 2
  if device_known "$id"; then
    note "Already knows device ${id:0:7}"
  else
    syncthing cli config devices add --device-id "$id" --name "$name" "$@"
    note "Added device ${id:0:7} ($name)"
  fi
  if syncthing cli config folders "$SYNC_FOLDER_ID" devices list | grep -qx "$id"; then
    note "\"$SYNC_FOLDER_LABEL\" is already shared with it"
  else
    syncthing cli config folders "$SYNC_FOLDER_ID" devices add --device-id "$id"
    note "Shared \"$SYNC_FOLDER_LABEL\" with it"
  fi
}
