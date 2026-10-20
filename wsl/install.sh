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
# Ubuntu calls fd "fdfind"; Emacs packages look for "fd".
if ! type -P fd >/dev/null; then
  sudo ln -sf /usr/bin/fdfind /usr/local/bin/fd
  note "Linked fd to fdfind"
fi

step "Icon font (for the Emacs mode line)"
if fc-list : family | grep -q "Symbols Nerd Font Mono"; then
  note "Already installed"
else
  mkdir -p ~/.local/share/fonts
  curl -fsSL -o ~/.local/share/fonts/NFM.ttf \
    https://raw.githubusercontent.com/rainstormstudio/nerd-icons.el/main/fonts/NFM.ttf
  fc-cache -f ~/.local/share/fonts
  note "Installed Symbols Nerd Font Mono in ~/.local/share/fonts"
fi

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
# Folders only sync between computers that give them the same ID, so don't
# add a second folder on top of one set up by hand under another ID.
for f in $(syncthing cli config folders list); do
  [[ $f != "$SYNC_FOLDER_ID" ]] || continue
  if [[ $(folder_path "$f") == "$(realpath -m "$SYNC_DIR")" ]]; then
    die "Syncthing already syncs $SYNC_DIR, as folder ID \"$f\" instead of \"$SYNC_FOLDER_ID\".
       If your other computers share it as \"$f\", set SYNC_FOLDER_ID=\"$f\" in
       ~/wsl-workstation/config.env (on every computer), then run setup again.
       Otherwise remove that folder at http://localhost:8384 (your files stay
       on disk) and run setup again."
  fi
done
if folder_known; then
  note "Already set up"
  if [[ $(folder_path "$SYNC_FOLDER_ID") != "$(realpath -m "$SYNC_DIR")" ]]; then
    note "(it is at $(folder_path "$SYNC_FOLDER_ID") on this computer, not $SYNC_DIR)"
  fi
else
  syncthing cli config folders add --id "$SYNC_FOLDER_ID" --label "$SYNC_FOLDER_LABEL" \
    --path "$SYNC_DIR" --type sendreceive
  note "Added folder \"$SYNC_FOLDER_LABEL\""
fi
# Keep old versions of every file another computer overwrites or deletes,
# in $SYNC_DIR/.stversions: the safety net for sync mistakes.
syncthing cli config folders "$SYNC_FOLDER_ID" versioning type set staggered
note "Staggered file versioning is on"
# Syncthing creates an empty "Default Folder" (~/Sync) on first start;
# remove it if nothing was put in it or shared through it.
if syncthing cli config folders list | grep -qx default; then
  dpath=$(folder_path default)
  shared=$(syncthing cli config folders default devices list | grep -vx "$(my_device_id)" || true)
  if [[ -z $shared && -z $(ls -A "$dpath" 2>/dev/null | grep -vx .stfolder) ]]; then
    syncthing cli config folders default delete
    rm -rf "$dpath/.stfolder"
    rmdir "$dpath" 2>/dev/null || true
    note "Removed Syncthing's unused Default Folder ($dpath)"
  fi
fi

step "Emacs configuration"
if [[ -d ~/.emacs.d/.git ]]; then
  if [[ -n $(git -C ~/.emacs.d status --porcelain --untracked-files=no) ]]; then
    note "~/.emacs.d has uncommitted changes, so it wasn't updated."
    note "Commit or stash them, then run this again to update."
  elif git -C ~/.emacs.d pull -q --ff-only; then
    note "Up to date with $(git -C ~/.emacs.d remote get-url origin 2>/dev/null || echo its remote)"
  else
    note "Couldn't update ~/.emacs.d with git pull (offline, or it has commits of its own); left as is"
  fi
elif [[ -e ~/.emacs.d ]]; then
  note "~/.emacs.d exists but isn't a git clone; leaving it alone"
elif [[ -n ${EMACS_CONFIG_REPO:-} ]]; then
  git clone -q "$EMACS_CONFIG_REPO" ~/.emacs.d
  note "Cloned $EMACS_CONFIG_REPO"
else
  note "No EMACS_CONFIG_REPO in config.env; skipped"
fi

step "This setup in ~/wsl-workstation"
src=$(cd "$here/.." && pwd -P)
dest=~/wsl-workstation
if [[ $src == "$(realpath -m "$dest")" ]]; then
  note "Running from there already"
else
  # Running from a copy on the Windows side: keep a git clone in WSL, so
  # "git pull" there brings later updates.
  if [[ -d $dest/.git ]]; then
    git -C "$dest" pull -q --ff-only --autostash ||
      note "Couldn't update $dest with git pull; left as is"
  else
    if [[ -e $dest ]]; then
      old="$dest.old-$(date +%Y%m%d-%H%M%S)"
      mv "$dest" "$old"
      note "Moved the previous copy to $old"
    fi
    if [[ -n ${WORKSTATION_REPO:-} ]] && git clone -q "$WORKSTATION_REPO" "$dest"; then
      note "Cloned $WORKSTATION_REPO"
    else
      cp -r "$src" "$dest"
      note "Couldn't clone WORKSTATION_REPO; copied $src instead (updates won't come through git)"
    fi
  fi
  # Keep any settings edited in the copy that was run.
  if ! cmp -s "$src/config.env" "$dest/config.env"; then
    cp "$src/config.env" "$dest/config.env"
    note "Copied your config.env from $src"
  fi
  chmod +x "$dest"/wsl/*.sh
fi

step "Done"
note "Syncthing web page (from Windows too): http://localhost:8384"
note "To connect this computer to one that already has your files, run:"
note "  ~/wsl-workstation/wsl/join.sh"
note "Emacs downloads its packages the first time it starts; give it a few minutes."
