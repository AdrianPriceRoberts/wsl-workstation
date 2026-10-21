# WSL workstation

Sets up a Windows PC with Ubuntu (via WSL), Emacs, and Syncthing, so a
folder of notes (`~/org`) stays in sync across all your computers. Syncing
keeps running in the background whether or not Emacs or a terminal is open.

It installs and configures:

- **WSL and Ubuntu**, kept running in the background from sign-in.
- **Emacs** (version 29 or newer) with the fonts the configuration uses
  (Fira Code, Cantarell, and the Symbols Nerd Font for mode-line icons), and
  the search tools it calls (ripgrep, fd).
- **Your Emacs configuration**, cloned from `EMACS_CONFIG_REPO`.
- **Syncthing**, from Syncthing's own package repository, running as a
  service, with the notes folder set up and old file versions kept.

You need Windows 10 (version 21H2 or later) or Windows 11. Windows 11 22H2
or later syncs faster on a shared network; see [How it works](#how-it-works).

## Set up a new computer

1. **Download this repository.** On GitHub, click *Code → Download ZIP*,
   then right-click the downloaded file and choose *Extract All*. (Or use
   `git clone` if you have Git for Windows.)
2. **Check `config.env`** (open it in Notepad). `EMACS_CONFIG_REPO` is the
   Emacs configuration that gets installed. It is set to the author's own
   configuration, so change it to yours, or empty it to keep a plain Emacs.
3. **Double-click `setup.cmd`.** If Windows shows *Windows protected your
   PC*, click *More info → Run anyway*. Setup then:
   - installs WSL if it's missing. Windows asks for permission, and you
     then restart Windows and double-click `setup.cmd` again.
   - installs Ubuntu. It asks you to pick a Linux user name and password;
     remember the password, because setup asks for it next. If you are left
     at a prompt ending in `$`, type `exit` and press Enter.
   - installs Emacs, the fonts and tools, and Syncthing inside Ubuntu.
   - makes Windows keep Ubuntu running in the background from sign-in.
   - offers to restart WSL to apply a network setting. Say no if you have
     work open in WSL; the setting then applies at your next reboot.
   - checks that everything works.
4. **Connect it to your other computers.** See
   [Syncing between computers](#syncing-between-computers).
5. **Start Emacs**, from the Start menu (*Emacs (Ubuntu)*) or by typing
   `emacs` in Ubuntu. The first start downloads Emacs packages and takes a
   few minutes; later starts are quick.

Running `setup.cmd` again is always safe. It only does what isn't done yet.

## Update an existing computer

Use this to bring a computer that already has WSL and Emacs in line with
the others, or to repair its Syncthing setup.

- **Set up before with this repository** (there's a `~/wsl-workstation`
  folder in Ubuntu that `git status` works in). In Ubuntu, run

      cd ~/wsl-workstation && git pull && explorer.exe .

  and double-click `setup.cmd` in the window that opens.
- **Set up some other way**, including a `~/wsl-workstation` that isn't a git
  clone: follow [Set up a new computer](#set-up-a-new-computer). Setup keeps
  your Ubuntu, files and Emacs, and moves an old `~/wsl-workstation` aside.

What setup does to an existing installation:

- **Emacs** is upgraded to version 29 or newer if it's older. The packages,
  fonts and tools are installed if they're missing.
- **The Emacs configuration** in `~/.emacs.d` is updated with `git pull`,
  unless it has uncommitted changes (then it says so and leaves it alone).
  If `~/.emacs.d` isn't a git clone, it is left alone.
- **Syncthing** is switched to the current release and runs as a background
  service. A Syncthing started some other way, e.g. from Emacs, is stopped.
  Its identity and pairings are kept.
- **The notes folder**: if Syncthing already syncs `~/org` under a different
  folder ID than `SYNC_FOLDER_ID` in `config.env`, setup stops and explains
  what to do. Every computer has to use the same folder ID.

If the computer's `~/org` is an old copy that has been out of sync for a
while, rename it first (e.g. to `~/org-old`) so that it doesn't produce
conflict files. Setup then makes a new empty `~/org`, which fills up once
the computer is connected. Copy anything you need from `~/org-old`
afterwards.

## Syncing between computers

Syncthing copies your notes directly between your own computers. There is
no cloud server, so a change reaches another computer only while both are
on, or when another computer that has already received it is on. Each
computer has a *device ID*, a long code like `ABCDEFG-HIJKLMN-...`, and
two computers sync only after each has accepted the other.

**Connecting a new computer.** You need the new computer and any one
computer that already has your notes.

1. On the new computer, in Ubuntu, run

       ~/wsl-workstation/wsl/join.sh

   It asks for the other computer's device ID. To find that ID, run
   `~/wsl-workstation/wsl/check.sh` on the other computer, or open
   <http://localhost:8384> there and choose *Actions → Show ID*.
2. `join.sh` then prints a command with the new computer's ID. Run it on the
   other computer:

       ~/wsl-workstation/wsl/add-device.sh NEW-COMPUTER-ID

   Alternatively, open <http://localhost:8384> on the other computer, click
   *Add Device* on the message about the new computer, and tick
   *org files* under *Sharing*.
3. Within a minute or two, files start arriving in `~/org`. Run `check.sh`
   to watch progress. It's done when the other computer shows
   *connected* and *100%*.

You only need to connect a new computer to one other computer. That one
becomes the new computer's *introducer*, which tells it about the rest of
your computers, so all of them connect to each other.

**Removing a computer** you no longer use: on each remaining computer,
open <http://localhost:8384>, click the old computer under *Remote
Devices*, then *Edit → Remove*.

## Is syncing working?

In Ubuntu:

    ~/wsl-workstation/wsl/check.sh

It lists anything that needs fixing, and shows which computers are
connected and how up to date they are. Syncthing's own page,
<http://localhost:8384>, works in any browser on the PC.

If two computers won't connect:

- Both must be on, with WSL running (the keep-alive does that after
  sign-in). `check.sh` on each should show no *FIX* lines.
- On Windows 10 or older Windows 11 versions, computers connect through
  Syncthing's public relays. That's slower, but works.
- Corporate or university networks sometimes block Syncthing. It usually
  still connects through relays, after a few minutes.

## Emacs settings for one computer

Settings that differ between computers belong in `~/.emacs.d/local.el`,
which isn't synced or tracked in git. Emacs creates it from
`local.el.example` on first start. It contains:

| Setting | Default | |
|---|---|---|
| `my/font-height` | `nil` | Font size in 1/10 pt (`120` = 12pt); `nil` scales to the screen |
| `my/variable-font-height` | `nil` | Size of the prose font; `nil` = same as above |
| `my/fixed-font`, `my/variable-font` | Fira Code Retina, Cantarell | Font names |
| `my/theme` | `doom-laserwave` | Any theme from `M-x load-theme`, or `nil` |
| `my/org-dir` | `~/org/` | Notes folder; keep it the same as `SYNC_DIR` |
| `my/zotero-pdf-dir` | `nil` | Zotero PDFs; `nil` = `zotero-pdfs/` in the uWaterloo OneDrive |

Restart Emacs after editing it.

## If something goes wrong

- **A note was overwritten or deleted.** Syncthing keeps the old versions
  of anything another computer replaced, in `~/org/.stversions`. Emacs also
  keeps the last 20 saves of every file in `~/.emacs.d/backups`.
- **A file named `...sync-conflict-...` appeared.** Two computers changed
  the same file before they could sync. Both versions are kept. In Emacs,
  run `M-x my/resolve-sync-conflict` to choose which one to keep.
- **Setup was stopped while Ubuntu asked for a user name**, and now says
  *Run this as your normal user, not root*: double-click `setup.cmd`
  again. It notices that Ubuntu has no user yet and asks you for one.
- **Emacs shows boxes instead of icons, or says ripgrep is not found.** Run
  `~/wsl-workstation/wsl/install.sh` in Ubuntu, then restart Emacs.

## How it works

| Piece | What it does |
|---|---|
| `setup.ps1` (Windows) | Installs WSL; turns on *mirrored networking* in `%USERPROFILE%\.wslconfig` (Windows 11 22H2+) so computers on the same network connect directly; allows Syncthing's ports through the WSL firewall; adds a hidden `sleep infinity` to the Startup folder to keep WSL running; runs `install.sh`. |
| `wsl/install.sh` (Ubuntu) | Turns on systemd; installs packages from `wsl/packages.txt`, including current Syncthing from `apt.syncthing.net` and Emacs from a PPA if Ubuntu's is too old; installs the nerd-icons font; runs Syncthing as a systemd user service; creates the synced folder with staggered versioning; clones or updates the Emacs configuration; keeps a git clone of this repository in `~/wsl-workstation`. |
| `wsl/join.sh` / `wsl/add-device.sh` | Pair a new computer with an existing one. The existing computer becomes the new one's introducer. |
| `wsl/check.sh` | Health check. |
| `config.env` | Repository URLs, synced folder, minimum Emacs version. |

Each computer gets its own Syncthing identity. Don't copy
`~/.config/syncthing` or `~/.local/state/syncthing` between computers, or
clone a whole WSL installation with `wsl --export`; that gives two computers
the same identity and breaks syncing.

To stop WSL from running in the background, delete *WSL keep-alive* from
your Startup folder (press Win+R, type `shell:startup`).
