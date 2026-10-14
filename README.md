# WSL workstation

Sets up a Windows PC with Ubuntu (via WSL), Emacs, and Syncthing, so a
folder of notes (`~/org`) stays in sync across all your computers. Syncing
keeps running in the background whether or not Emacs or a terminal is open.

## Set up a new computer

1. **Edit `config.env`** if this isn't your own computer: set
   `EMACS_CONFIG_REPO` to the Emacs configuration you want, or empty it.
2. **Double-click `setup.cmd`.** It will:
   - install WSL and Ubuntu if they're missing. Windows asks for permission,
     and you may need to restart Windows and run `setup.cmd` again. Ubuntu
     asks you to pick a user name and password; remember the password.
   - install Emacs and Syncthing inside Ubuntu, asking for that password.
   - make Windows keep Ubuntu running in the background from sign-in.
   - check that everything works.
3. **Connect it to a computer that already has your notes.** In Ubuntu, run

       ~/wsl-workstation/wsl/join.sh

   and follow what it says. You paste in the other computer's ID, then
   approve this one on the other computer.

Running `setup.cmd` again is always safe. It only does what isn't done yet.

## Is syncing working?

In Ubuntu:

    ~/wsl-workstation/wsl/check.sh

It lists anything that needs fixing, and which computers are connected and
how up to date they are. You can also open Syncthing's own page at
<http://localhost:8384> in any browser on the PC.

## If something goes wrong

- **A note was overwritten or deleted.** Syncthing keeps the old versions of
  anything another computer replaced, in `~/org/.stversions`. Emacs also keeps
  the last 20 saves of every file in `~/.emacs.d/backups`.
- **A file named `...sync-conflict-...` appeared.** Two computers changed the
  same file before they could sync. Both versions are kept. In Emacs, run
  `M-x my/resolve-sync-conflict` to merge them.

## How it works

| Piece | What it does |
|---|---|
| `setup.ps1` (Windows) | Installs WSL; turns on *mirrored networking* in `%USERPROFILE%\.wslconfig` (Windows 11) so computers on the same network connect directly; allows Syncthing's ports through the WSL firewall; adds a hidden `sleep infinity` to the Startup folder to keep WSL running. |
| `wsl/install.sh` (Ubuntu) | Turns on systemd; installs packages from `wsl/packages.txt`, including current Syncthing from `apt.syncthing.net`; runs Syncthing as a systemd user service; creates the synced folder with staggered versioning; clones the Emacs config. |
| `wsl/join.sh` / `wsl/add-device.sh` | Pair a new computer with an existing one. The existing computer becomes the new one's *introducer*, so the new one also learns about your other computers. |
| `wsl/check.sh` | Health check. |

Each computer gets its own Syncthing identity. Don't copy `~/.config/syncthing`
or `~/.local/state/syncthing` between computers, or clone a whole WSL
installation with `wsl --export`; that makes two computers share one
identity and breaks syncing.

To stop WSL from running in the background, delete *WSL keep-alive* from
your Startup folder (press Win+R, type `shell:startup`).
