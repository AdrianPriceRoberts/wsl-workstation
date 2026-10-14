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
    & wsl.exe --install -d $Distro
    if ($LASTEXITCODE -ne 0) { throw "Installing $Distro failed." }
} else {
    Note "Already installed"
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
    & wsl.exe -d $Distro --cd "~" -- bash $installSh
    if ($LASTEXITCODE -eq 10 -and $attempt -eq 1) {
        Warn "$Distro must restart for systemd to start.  This closes every program running in it."
        Read-Host "    Save your work in $Distro, then press Enter to restart it (Ctrl+C to stop here)"
        & wsl.exe --terminate $Distro | Out-Null
        continue
    }
    if ($LASTEXITCODE -ne 0) { throw "install.sh failed (exit $LASTEXITCODE); see the messages above." }
    break
}

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
& wsl.exe -d $Distro --cd "~" -- bash ~/wsl-workstation/wsl/check.sh

Write-Host ""
Write-Host "All set.  Open Emacs from the Start menu or by running 'emacs' in Ubuntu."
Write-Host "To connect this PC to another one with your files, run in Ubuntu:"
Write-Host "    ~/wsl-workstation/wsl/join.sh"
