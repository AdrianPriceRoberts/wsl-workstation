<#
.SYNOPSIS
  Set up this Windows PC: WSL with Ubuntu, kept running in the background,
  with Emacs and Syncthing inside it.

.DESCRIPTION
  Double-click setup.cmd, or run:
    powershell -ExecutionPolicy Bypass -File setup.ps1
  Safe to run again; each step checks what is already done.  Admin rights
  are only asked for when installing WSL and for one optional firewall rule.

.PARAMETER Distro
  The WSL distribution to use (default: Ubuntu).
#>
param(
    [string]$Distro = "Ubuntu"
)

$ErrorActionPreference = "Stop"
$env:WSL_UTF8 = "1"   # make wsl.exe print plain text, not UTF-16

# Any error ends setup with a message that can't be mistaken for success.
trap {
    Write-Host ""
    Write-Host "Setup did NOT finish: $_" -ForegroundColor Red
    Write-Host "Fix what it says (or send these messages to whoever gave you this setup)," -ForegroundColor Red
    Write-Host "then run setup.cmd again; it carries on from where it stopped." -ForegroundColor Red
    exit 1
}

function Step($Message) { Write-Host "`n==> $Message" -ForegroundColor Cyan }
function Note($Message) { Write-Host "    $Message" }
function Warn($Message) { Write-Host "    $Message" -ForegroundColor Yellow }

function Invoke-Elevated($Script) {
    # Run a PowerShell snippet as administrator; $true if it ran.
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
    try {
        $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru `
            -ArgumentList "-NoProfile -EncodedCommand $encoded"
        return ($p.ExitCode -eq 0)
    } catch {
        return $false
    }
}

function Set-IniValue($Path, $Section, $Key, $Value) {
    # Set Key=Value under [Section] in an ini-style file; $true if it changed.
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path $Path) {
        foreach ($l in @(Get-Content $Path)) { if ($null -ne $l) { $lines.Add($l) } }
    }
    $inSection = $false
    $sectionAt = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = $lines[$i].Trim()
        if ($t -match '^\[(.+)\]$') {
            $inSection = ($Matches[1] -eq $Section)
            if ($inSection) { $sectionAt = $i }
            continue
        }
        if ($inSection -and $t -match "^$Key\s*=\s*(.*)$") {
            if ($Matches[1].Trim() -eq $Value) { return $false }
            $lines[$i] = "$Key=$Value"
            Set-Content -Path $Path -Value $lines -Encoding ASCII
            return $true
        }
    }
    if ($sectionAt -ge 0) {
        $lines.Insert($sectionAt + 1, "$Key=$Value")
    } else {
        $lines.Add("[$Section]")
        $lines.Add("$Key=$Value")
    }
    Set-Content -Path $Path -Value $lines -Encoding ASCII
    return $true
}

function Get-LinuxPath($WindowsPath) {
    # \\wsl.localhost\<distro>\home\... and \\wsl$\<distro>\... are already inside WSL.
    if ($WindowsPath -match '^\\\\wsl(\.localhost|\$)\\[^\\]+(\\.*)$') {
        return ($Matches[2] -replace '\\', '/')
    }
    return (& wsl.exe -d $Distro -- wslpath -a -u ($WindowsPath -replace '\\', '/')).Trim()
}

# ---------------------------------------------------------------------------

Step "WSL"
& wsl.exe --status *> $null
if ($LASTEXITCODE -ne 0) {
    Note "Installing WSL (Windows will ask for permission)..."
    & wsl.exe --install --no-distribution
    Warn "Restart Windows, then run setup again to continue."
    exit 0
}
Note "Installed"

Step "Linux distribution '$Distro'"
$installed = @(& wsl.exe --list --quiet) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
if ($installed -notcontains $Distro) {
    Note "Installing $Distro.  When it asks, choose a Linux user name and password"
    Note "(they don't have to match Windows; remember the password, sudo asks for it)."
    Note "If it then leaves you at a Linux prompt ending in '`$', type exit and press"
    Note "Enter, and setup carries on."
    & wsl.exe --install -d $Distro
    if ($LASTEXITCODE -ne 0) { throw "Installing $Distro failed." }
} else {
    Note "Already installed"
}

Step "Linux user"
# If choosing a user name was cancelled, Ubuntu has no user of its own and
# logs everyone in as root.  Make (or find) one, and make it the default.
$linuxUser = (& wsl.exe -d $Distro -- whoami).Trim()
if ($linuxUser -eq "root") {
    $linuxUser = (& wsl.exe -d $Distro -u root --exec sh -c 'getent passwd 1000 | cut -d: -f1').Trim()
    if ($linuxUser) {
        Note "Using the existing user '$linuxUser'"
    } else {
        Warn "$Distro has no user of its own yet (choosing one was probably cancelled)."
        do {
            $linuxUser = (Read-Host "    Choose a Linux user name (lower-case letters and digits, e.g. sam)").Trim()
        } until ($linuxUser -cmatch '^[a-z][a-z0-9_-]{0,31}$')
        & wsl.exe -d $Distro -u root -- useradd -m -s /bin/bash -G sudo $linuxUser
        if ($LASTEXITCODE -ne 0) { throw "Creating the user '$linuxUser' failed." }
        Note "Now choose its password (remember it; sudo asks for it):"
        do { & wsl.exe -d $Distro -u root -- passwd $linuxUser } until ($LASTEXITCODE -eq 0)
    }
    $setDefault = @'
f=/etc/wsl.conf; touch $f; if grep -q '^\[user\]' $f; then sed -i '/^\[user\]/,/^\[/{/^default[[:space:]]*=/d}' $f; sed -i '/^\[user\]/a default=NAME' $f; else printf '\n[user]\ndefault=NAME\n' >> $f; fi
'@ -replace 'NAME', $linuxUser
    & wsl.exe -d $Distro -u root --exec sh -c $setDefault.Trim()
    Note "'$linuxUser' is now the default user (from the next time $Distro restarts)"
} else {
    Note "Using '$linuxUser'"
}

Step "WSL networking"
$wslconfig = Join-Path $env:USERPROFILE ".wslconfig"
$needShutdown = $false
if ([Environment]::OSVersion.Version.Build -ge 22621) {
    # Mirrored networking puts WSL on the PC's own network, so Syncthing can
    # reach computers on the same network directly instead of via relays.
    if (Set-IniValue $wslconfig "wsl2" "networkingMode" "mirrored") {
        Note "Turned on mirrored networking in $wslconfig"
        $needShutdown = $true
    } else {
        Note "Mirrored networking is already on"
    }
    if (Get-Command Get-NetFirewallHyperVRule -ErrorAction SilentlyContinue) {
        $rules = @(Get-NetFirewallHyperVRule -Name "Syncthing-*" -ErrorAction SilentlyContinue)
        if ($rules.Count -ge 3) {
            Note "Firewall already lets other computers reach Syncthing"
        } else {
            Note "Allowing other computers to reach Syncthing (Windows will ask for permission)..."
            $ok = Invoke-Elevated @'
$vm = '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'
foreach ($r in @(@('Syncthing-TCP','TCP',22000), @('Syncthing-QUIC','UDP',22000), @('Syncthing-Discovery','UDP',21027))) {
    if (-not (Get-NetFirewallHyperVRule -Name $r[0] -ErrorAction SilentlyContinue)) {
        New-NetFirewallHyperVRule -Name $r[0] -DisplayName "$($r[0]) ($($r[1]) $($r[2]))" `
            -Direction Inbound -VMCreatorId $vm -Protocol $r[1] -LocalPorts $r[2] -Action Allow | Out-Null
    }
}
'@
            if ($ok) { Note "Done" }
            else { Warn "Skipped.  Syncing still works, just through Syncthing's relays (slower)." }
        }
    }
} else {
    Note "This Windows version is older than Windows 11 22H2, so WSL keeps its default"
    Note "network; Syncthing will still work, via relays when computers can't connect directly."
}

Step "Emacs and Syncthing inside $Distro"
$installSh = Get-LinuxPath (Join-Path $PSScriptRoot "wsl\install.sh")
for ($attempt = 1; $attempt -le 2; $attempt++) {
    & wsl.exe -d $Distro -u $linuxUser --cd "~" -- bash $installSh
    if ($LASTEXITCODE -eq 10 -and $attempt -eq 1) {
        Warn "$Distro must restart for systemd to start.  This closes every program running in it."
        Read-Host "    Save your work in $Distro, then press Enter to restart it (Ctrl+C to stop here)"
        & wsl.exe --terminate $Distro | Out-Null
        continue
    }
    if ($LASTEXITCODE -ne 0) {
        throw ("Installing inside $Distro failed (exit $LASTEXITCODE); see the messages above, or the log at " +
               "\\wsl.localhost\$Distro\home\$linuxUser\.cache\wsl-workstation\install.log")
    }
    break
}

# Don't report success unless the programs are really there.
$missing = @(& wsl.exe -d $Distro -u $linuxUser --exec sh -c 'for c in emacs syncthing git rg fd; do command -v $c >/dev/null || echo $c; done') |
    ForEach-Object { $_.Trim() } | Where-Object { $_ }
if ($missing) { throw "Still missing in $Distro after installing: $($missing -join ', ')" }
Note "Emacs, Syncthing, git, ripgrep and fd are installed in $Distro"

# Make plain 'wsl' and new terminal tabs open this distribution.
& wsl.exe --set-default $Distro | Out-Null

Step "Keep WSL running in the background"
# WSL shuts a distribution down shortly after its last window closes, which
# would stop Syncthing.  A hidden 'sleep infinity' started at sign-in keeps
# it up.  To undo, delete the shortcut below from your Startup folder.
$startup = [Environment]::GetFolderPath("Startup")
$lnkPath = Join-Path $startup "WSL keep-alive ($Distro).lnk"
$wslExe = Join-Path $env:WINDIR "System32\wsl.exe"
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath = Join-Path $env:WINDIR "System32\conhost.exe"
$lnk.Arguments = "--headless `"$wslExe`" -d $Distro --exec sleep infinity"
$lnk.Description = "Keeps WSL ($Distro) and Syncthing running in the background"
$lnk.WindowStyle = 7
$lnk.Save()
Note "Starts at every sign-in: $lnkPath"

if ($needShutdown) {
    Warn "The network change takes effect the next time WSL restarts (e.g. after a reboot)."
    Warn "Restarting now closes every WSL window and program, including Emacs and anything"
    Warn "else running in WSL.  Everything else works without it."
    $answer = Read-Host "    Restart WSL now? [y/N]"
    if ($answer -match '^(y|yes)$') {
        & wsl.exe --shutdown
    } else {
        Note "Skipped.  Later, close your WSL programs and run 'wsl --shutdown' in PowerShell,"
        Note "or just restart Windows."
    }
}
Start-Process -FilePath $lnkPath
Start-Sleep -Seconds 5
Note "Keep-alive started"

Step "Checking"
& wsl.exe -d $Distro -u $linuxUser --cd "~" -- bash ~/wsl-workstation/wsl/check.sh

Write-Host ""
Write-Host "All set.  Open Emacs from the Start menu (Emacs ($Distro)), or open $Distro from"
Write-Host "the Start menu (or type 'wsl' in PowerShell) and run 'emacs'."
Write-Host "To connect this PC to another one with your files, run in Ubuntu:"
Write-Host "    ~/wsl-workstation/wsl/join.sh"
