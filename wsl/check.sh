#!/usr/bin/env bash
# Show whether syncing is healthy on this computer.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ok()  { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
bad() { printf '  \033[31mFIX\033[0m   %s\n' "$*"; }

echo
if [[ -d /run/systemd/system ]]; then ok "systemd is running"
else bad "systemd is off: run install.sh, then wsl --shutdown from Windows"; fi

if systemctl --user is-active -q syncthing; then ok "Syncthing service is running ($(syncthing --version | awk '{print $2}'))"
else bad "Syncthing service is not running: systemctl --user start syncthing"; fi

if [[ $(loginctl show-user "$USER" -p Linger --value 2>/dev/null) == yes ]]; then ok "Syncthing starts when WSL starts (linger)"
else bad "Linger is off: sudo loginctl enable-linger $USER"; fi

if pgrep -fx 'sleep infinity' >/dev/null; then ok "Windows is keeping WSL running (keep-alive found)"
else bad "No keep-alive: WSL stops when its windows close.  Run setup.cmd on Windows"; fi

# type -P: only real programs count, which is what Emacs can run.
for tool in rg fd; do
  if type -P "$tool" >/dev/null; then ok "$tool is installed (Emacs uses it for searching)"
  else bad "$tool is missing: run install.sh"; fi
done

if fc-list : family | grep -q "Symbols Nerd Font Mono"; then ok "Icon font for Emacs is installed"
else bad "Icon font missing (Emacs shows boxes instead of icons): run install.sh"; fi

syncthing cli show system >/dev/null 2>&1 || { bad "Syncthing's API isn't answering"; exit 1; }

if folder_known; then
  vtype=$(syncthing cli config folders "$SYNC_FOLDER_ID" versioning type get)
  path=$(syncthing cli config folders "$SYNC_FOLDER_ID" path get)
  ok "Folder \"$SYNC_FOLDER_LABEL\" at $path"
  if [[ $vtype == staggered ]]; then ok "File versioning: staggered"
  else bad "File versioning is '${vtype:-off}': run install.sh"; fi
else
  bad "No \"$SYNC_FOLDER_LABEL\" folder: run install.sh"
fi

echo
echo "  This computer's ID: $(my_device_id)"
echo "  Other computers:"
key=$(syncthing cli config gui apikey get)
me=$(my_device_id)
api() { curl -fsS -H "X-API-Key: $key" "http://127.0.0.1:8384/rest/$1"; }
conns=$(api system/connections)
stats=$(api stats/device)
for id in $(syncthing cli config folders "$SYNC_FOLDER_ID" devices list 2>/dev/null); do
  [[ $id == "$me" ]] && continue
  name=$(syncthing cli config devices "$id" name get)
  done_pct=$(api "db/completion?folder=$SYNC_FOLDER_ID&device=$id" |
    python3 -c 'import json,sys,math; print(math.floor(json.load(sys.stdin)["completion"] * 10) / 10)')
  python3 - "$id" "$name" "$done_pct" "$conns" "$stats" <<'EOF'
import json, sys
id, name, pct, conns, stats = sys.argv[1:]
connected = json.loads(conns)["connections"].get(id, {}).get("connected")
seen = json.loads(stats).get(id, {}).get("lastSeen", "")[:16].replace("T", " ")
state = "connected" if connected else f"offline, last seen {seen or 'never'}"
print(f"    {name:<32} {state:<36} has {pct}% of the folder")
EOF
done
echo
