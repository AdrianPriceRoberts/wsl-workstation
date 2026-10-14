#!/usr/bin/env bash
# Set up Emacs and an always-on Syncthing inside WSL.  Safe to run again:
# each step checks what is already done.
#
# Exit status 10 means systemd was just turned on and WSL must restart
# before the rest can run; setup.ps1 does that and runs this again.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $EUID -ne 0 ]] || die "Run this as your normal user, not root; it uses sudo where needed."
grep -qi microsoft /proc/version || die "This is meant to run inside WSL."

step "Systemd (runs Syncthing in the background)"
if grep -qsE '^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true' /etc/wsl.conf; then
  note "Already on in /etc/wsl.conf"
else
  if grep -qsE '^[[:space:]]*systemd[[:space:]]*=' /etc/wsl.conf; then
    sudo sed -i -E 's/^[[:space:]]*systemd[[:space:]]*=.*/systemd=true/' /etc/wsl.conf
  elif grep -qs '^\[boot\]' /etc/wsl.conf; then
    sudo sed -i '/^\[boot\]/a systemd=true' /etc/wsl.conf
  else
    printf '\n[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf >/dev/null
  fi
  note "Turned on in /etc/wsl.conf"
fi
if [[ ! -d /run/systemd/system ]]; then
  note "WSL has to restart for systemd to start; run this again afterwards."
  exit 10
fi

step "Syncthing's own package repository (for current releases)"
keyring=/etc/apt/keyrings/syncthing-archive-keyring.gpg
if [[ -s $keyring ]]; then
  note "Already set up"
else
  sudo mkdir -p /etc/apt/keyrings
  sudo curl -fsSL -o "$keyring" https://syncthing.net/release-key.gpg
  echo "deb [signed-by=$keyring] https://apt.syncthing.net/ syncthing stable-v2" |
    sudo tee /etc/apt/sources.list.d/syncthing.list >/dev/null
  # Prefer it over Ubuntu's older syncthing package.
  printf 'Package: *\nPin: origin apt.syncthing.net\nPin-Priority: 990\n' |
    sudo tee /etc/apt/preferences.d/syncthing.pref >/dev/null
  note "Added apt.syncthing.net (stable-v2)"
fi
sudo apt-get update -qq

step "Emacs version"
candidate=$(apt-cache policy emacs | awk '/Candidate:/ {print $2}')
major=$(sed -E 's/^[0-9]+://; s/^([0-9]+).*/\1/' <<<"$candidate")
if [[ $major =~ ^[0-9]+$ ]] && (( major >= MIN_EMACS_MAJOR )); then
  note "Ubuntu offers Emacs $candidate, which is new enough"
else
  note "Ubuntu offers Emacs ${candidate:-none}; adding the ubuntuhandbook1/emacs PPA for a newer one"
  sudo apt-get install -y -qq software-properties-common
  sudo add-apt-repository -y ppa:ubuntuhandbook1/emacs
  sudo apt-get update -qq
fi

step "Installing packages"
mapfile -t packages < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$here/packages.txt")
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages[@]}"
note "Emacs $(emacs --version | head -1 | awk '{print $3}'), Syncthing $(syncthing --version | awk '{print $2}')"

step "Syncthing as a background service"
# Linger starts your services when WSL boots, not only once you open a shell.
sudo loginctl enable-linger "$USER"
if pgrep -u "$USER" -x syncthing >/dev/null && ! systemctl --user is-active -q syncthing; then
  note "Stopping a Syncthing started some other way (e.g. from Emacs) so the service can take over"
  pkill -u "$USER" -x syncthing
  sleep 3
fi
systemctl --user enable -q syncthing
# Restart so an upgraded binary is the one running.
systemctl --user restart syncthing
wait_for_syncthing
note "Running; this computer's Syncthing ID is $(my_device_id)"

step "Synced folder $SYNC_DIR"
mkdir -p "$SYNC_DIR"
if folder_known; then
  note "Already set up"
else
  syncthing cli config folders add --id "$SYNC_FOLDER_ID" --label "$SYNC_FOLDER_LABEL" \
    --path "$SYNC_DIR" --type sendreceive
  note "Added folder \"$SYNC_FOLDER_LABEL\""
fi
# Keep old versions of every file another computer overwrites or deletes,
# in $SYNC_DIR/.stversions: the safety net for sync mistakes.
syncthing cli config folders "$SYNC_FOLDER_ID" versioning type set staggered
note "Staggered file versioning is on"

step "Emacs configuration"
if [[ -e ~/.emacs.d ]]; then
  note "~/.emacs.d already exists; leaving it alone"
elif [[ -n ${EMACS_CONFIG_REPO:-} ]]; then
  git clone -q "$EMACS_CONFIG_REPO" ~/.emacs.d
  note "Cloned $EMACS_CONFIG_REPO"
else
  note "No EMACS_CONFIG_REPO in config.env; skipped"
fi

step "Helper scripts in ~/wsl-workstation"
src=$(cd "$here/.." && pwd -P)
dest=~/wsl-workstation
if [[ $src == "$(realpath -m "$dest")" ]]; then
  note "Running from there already"
else
  # Running from a copy on the Windows side: keep one in WSL for later.
  mkdir -p "$dest"
  cp -r "$src/config.env" "$src/wsl" "$dest/"
  chmod +x "$dest"/wsl/*.sh
  note "Copied from $src"
fi

step "Done"
note "Syncthing web page (from Windows too): http://localhost:8384"
note "To connect this computer to one that already has your files, run:"
note "  ~/wsl-workstation/wsl/join.sh"
