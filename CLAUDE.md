# wsl-workstation

Sets up WSL, Emacs and Syncthing on Windows PCs; see README.md. The
README is for non-technical users, so keep it in plain language.

- Every step in `setup.ps1` and `wsl/install.sh` must be safe to run again:
  check what's already done before changing anything.
- Never restart or shut down WSL (`wsl --shutdown`, `wsl --terminate`)
  without asking the user first; it closes everything running in it.
- Line endings are set in `.gitattributes`: LF for shell scripts and
  `config.env`, CRLF for `.ps1` and `.cmd`.
- The Emacs configuration lives in its own repository
  (`EMACS_CONFIG_REPO`, cloned to `~/.emacs.d`), which has its own CLAUDE.md:
  edit its `emacs.org`, never `init.el`.

## Privacy: the user's notes are off limits

Never read, open, list, search, grep, or summarize the user's notes
without explicit permission for that specific request. Permission given
once does not carry over to later requests or sessions. This covers:

- the synced folder (`SYNC_DIR`, `~/org` by default), including
  `.stversions`, conflict copies and attachments;
- files derived from the notes in `~/.emacs.d` (`vulpea.db`,
  `.org-id-locations`, `backups/`, `sync-conflict-archive/`);
- indirect reads, such as starting Emacs with the user's configuration
  (vulpea scans the notes folder).

Checking Syncthing's state is fine (`check.sh`, `syncthing cli`, the REST
API's status and completion figures), as long as it doesn't list or print
file names or contents from the notes folder.
