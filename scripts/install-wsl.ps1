#Requires -Version 5.1
#Requires -PSEdition Desktop
# NOTE: deliberately NOT using `#Requires -RunAsAdministrator` — the manual
# admin check in section 1 produces a friendlier error than PowerShell's
# default `#Requires` failure message. (`-PSEdition Desktop` blocks pwsh 7+
# upfront because the DISM cmdlets used below are Windows-PowerShell-only.)
<#
.SYNOPSIS
    Installs WSL2 on Windows 10 (build 19041+) or Windows 11.

.DESCRIPTION
    - Verifies admin rights and supported Windows build.
    - Confirms CPU virtualization is enabled in firmware.
    - Enables the 'Microsoft-Windows-Subsystem-Linux' and 'VirtualMachinePlatform' optional features.
    - On Win11 / Win10 21H2+ uses `wsl --install`; on older Win10 (19041..19043) installs the WSL2 kernel MSI manually.
    - Sets WSL default version to 2, runs `wsl --update`.
    - Lets the user pick a distro interactively or via -Distro.

.PARAMETER Distro
    Distro name (e.g. Ubuntu, Ubuntu-22.04, Debian, kali-linux, openSUSE-Tumbleweed).
    If omitted, the script lists the online catalog and prompts.

.PARAMETER NoReboot
    Skip the post-install reboot prompt even if Windows reports one is required.

.PARAMETER Force
    Continue past non-fatal warnings (e.g. virtualization not detected) without prompting.
    Also implies -NoReboot — the script exits cleanly instead of asking to reboot.

.EXAMPLE
    .\install-wsl.ps1

.EXAMPLE
    .\install-wsl.ps1 -Distro Ubuntu-22.04

.EXAMPLE
    .\install-wsl.ps1 -Distro Debian -NoReboot -Force

.NOTES
    Run from an elevated PowerShell prompt.
    Right-click PowerShell -> Run as administrator, then:
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
        .\install-wsl.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Distro,

    [switch]$NoReboot,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ----------------------------------------------------------------------------
# Pretty printing
# ----------------------------------------------------------------------------
function Write-Step { param($Msg) Write-Host "`n==> $Msg" -ForegroundColor Cyan }
function Write-Ok   { param($Msg) Write-Host "[OK]   $Msg" -ForegroundColor Green }
function Write-Info { param($Msg) Write-Host "[info] $Msg" -ForegroundColor Gray  }
function Write-Warn2{ param($Msg) Write-Host "[warn] $Msg" -ForegroundColor Yellow }
function Write-Err2 { param($Msg) Write-Host "[err]  $Msg" -ForegroundColor Red    }

function Confirm-Or-Exit {
    param([string]$Prompt, [string]$ExitMsg = 'Aborted.')
    if ($Force) { return }
    $r = Read-Host "$Prompt (y/N)"
    if ($r -notmatch '^[Yy]') {
        Write-Err2 $ExitMsg
        exit 1
    }
}

# PowerShell's `try { & native.exe }` does NOT throw on non-zero exit codes.
# Wrap wsl.exe invocations so callers can rely on catch{} for failure paths.
#
# NOTE: deliberately a simple function (no param block, no [CmdletBinding()]).
# [CmdletBinding()] adds the -Debug common parameter, and PowerShell's
# parameter-prefix matcher would silently consume a literal `-d` flag from
# the caller as -Debug, breaking `Invoke-Wsl --install -d $Distro --no-launch`.
# Plain `$args` keeps every token intact.
# Resolve `wsl.exe` once to an absolute path so an attacker can't smuggle in a
# PATH-shadowing binary into an elevated session. 32-bit PowerShell on 64-bit
# Windows must use `Sysnative` (the file-system redirector rewrites System32).
$script:WslExe = if ([Environment]::Is64BitOperatingSystem -and `
                     -not [Environment]::Is64BitProcess) {
    Join-Path $env:WINDIR 'Sysnative\wsl.exe'
} else {
    Join-Path $env:WINDIR 'System32\wsl.exe'
}

function Invoke-Wsl {
    & $script:WslExe @args
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "wsl.exe $($args -join ' ') exited with code $code"
    }
}

# ----------------------------------------------------------------------------
# 1. Admin check
# ----------------------------------------------------------------------------
Write-Step 'Checking administrator privileges'
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    Write-Err2 'This script must be run as Administrator.'
    Write-Info 'Close this window and re-launch PowerShell with "Run as administrator".'
    exit 1
}
Write-Ok 'Running as Administrator'

# ----------------------------------------------------------------------------
# 2. Windows version
# ----------------------------------------------------------------------------
Write-Step 'Detecting Windows version'
$os       = Get-CimInstance -ClassName Win32_OperatingSystem
$build    = [int]$os.BuildNumber
$caption  = $os.Caption
$arch     = $os.OSArchitecture
$prodType = [int]$os.ProductType  # 1=Workstation/client, 2=DC, 3=Server

Write-Info "OS:           $caption"
Write-Info "Build:        $build"
Write-Info "Architecture: $arch"
Write-Info "ProductType:  $prodType (1=client)"

# Win Server shares the build numbering with Win10/11 client builds (e.g.
# Server 2022 = 20348) — gate to client SKUs so we don't try to enable
# client-only optional features on Server.
if ($prodType -ne 1) {
    Write-Err2 "This script is for Windows 10/11 client SKUs. Detected ProductType=$prodType ($caption)."
    Write-Info  'For Windows Server, follow the Server-specific WSL guide:'
    Write-Info  'https://learn.microsoft.com/en-us/windows/wsl/install-on-server'
    exit 1
}

# WSL2 requires a 64-bit OS regardless of build year — fail up front, before
# any optional-feature or wsl.exe side effects.
if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Err2 "32-bit Windows detected ($arch); WSL2 requires 64-bit."
    exit 1
}

$isWin11 = $build -ge 22000
$isWin10 = ($build -ge 10240) -and ($build -lt 22000)

if ($isWin11) {
    Write-Ok 'Windows 11 detected'
} elseif ($isWin10) {
    if ($build -lt 19041) {
        Write-Err2 "Windows 10 build $build is too old for WSL2."
        Write-Info  'WSL2 requires Windows 10 build 19041 (version 2004) or newer.'
        Write-Info  'Run Windows Update and re-run this script.'
        exit 1
    }
    Write-Ok "Windows 10 build $build detected"
} else {
    Write-Err2 "Unsupported Windows build: $build"
    exit 1
}

# `wsl --install` (modern path) shipped with Windows 10 21H2 (build 19044).
# Builds 19041..19043 need the manual WSL2 kernel MSI + Microsoft Store distro install.
#
# Build-number alone isn't a perfect signal — `wsl.exe` can be missing/disabled
# on customized images even when the build supports it. Section 7's `wsl --install`
# catch{} falls back to the Microsoft Store guidance if the command actually fails,
# rather than assuming build implies command-availability.
$useModernInstall = $isWin11 -or ($build -ge 19044)

# ----------------------------------------------------------------------------
# 3. CPU virtualization
# ----------------------------------------------------------------------------
Write-Step 'Checking CPU virtualization'
$cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1

$vtFirmware = [bool]$cpu.VirtualizationFirmwareEnabled
$slat       = [bool]$cpu.SecondLevelAddressTranslationExtensions
$vmMonitor  = [bool]$cpu.VMMonitorModeExtensions

Write-Info "CPU:               $($cpu.Name.Trim())"
Write-Info "VT enabled in BIOS: $vtFirmware"
Write-Info "SLAT support:       $slat"
Write-Info "VMX extensions:     $vmMonitor"

if (-not $slat) {
    Write-Err2 'CPU lacks SLAT (Second Level Address Translation). WSL2 / Hyper-V cannot run.'
    exit 1
}

if (-not $vtFirmware) {
    Write-Warn2 'Hardware virtualization does NOT appear to be enabled in firmware (BIOS/UEFI).'
    Write-Info  'Enable Intel VT-x or AMD-V/SVM in BIOS, then reboot.'
    Write-Info  'Verify via Task Manager -> Performance -> CPU -> "Virtualization: Enabled".'
    Write-Info  '(Some OEMs report this incorrectly; if Task Manager says Enabled, you can continue.)'
    Confirm-Or-Exit 'Continue anyway?'
} else {
    Write-Ok 'Virtualization is enabled in firmware'
}

# ----------------------------------------------------------------------------
# 4. Optional Windows features
# ----------------------------------------------------------------------------
function Get-FeatureState {
    param([string]$Name)
    $f = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction SilentlyContinue
    if ($null -eq $f) { return 'Missing' }
    return [string]$f.State  # 'Enabled' | 'EnabledPending' | 'Disabled' | 'DisabledPending'
}

function Enable-Feature {
    param([string]$Name)
    $result = Enable-WindowsOptionalFeature -Online -FeatureName $Name -All -NoRestart -ErrorAction Stop
    return [bool]$result.RestartNeeded
}

Write-Step 'Enabling required Windows features'
$rebootNeeded = $false
foreach ($feat in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
    # If a prior iteration's *Pending state already requires a reboot, stop —
    # running Enable-WindowsOptionalFeature on the remaining feature(s) against
    # a system with a pending reboot can fail or leave them in inconsistent state.
    if ($rebootNeeded) { break }

    $state = Get-FeatureState -Name $feat
    switch ($state) {
        'Enabled' {
            Write-Ok "$feat already enabled"
        }
        'EnabledPending' {
            # Previous run / manual change already enabled this; a reboot is
            # required before any WSL command will work.
            Write-Warn2 "$feat is enabled but pending reboot"
            $rebootNeeded = $true
        }
        'DisabledPending' {
            # A previous disable is queued; enabling now races with the pending
            # disable. Reboot first, then re-run — Enable-WindowsOptionalFeature
            # against this state can fail or leave the feature in an inconsistent
            # state.
            Write-Warn2 "$feat is disabled but pending reboot — reboot first, then re-run"
            $rebootNeeded = $true
        }
        default {
            Write-Info "Enabling $feat (current state: $state) ..."
            if (Enable-Feature -Name $feat) { $rebootNeeded = $true }
            Write-Ok "$feat enabled"
        }
    }
}

# Reusable reboot gate — invoked anywhere $rebootNeeded can transition to $true:
#   - after Section 4 feature enable (RestartNeeded or EnabledPending/DisabledPending),
#   - after Section 5 MSI install (msiexec exit 3010 = ERROR_SUCCESS_REBOOT_REQUIRED).
# WSL commands hard-fail until the pending reboot completes, so we exit cleanly
# and ask the user to re-run after rebooting.
function Invoke-RebootGate {
    param([Parameter(Mandatory = $true)][string]$Reason)
    Write-Warn2 "$Reason requires a reboot before WSL commands can run."
    Write-Info  'After reboot, re-run this script; already-enabled features / installed kernel are'
    Write-Info  'detected as such and the install continues from where it left off.'
    if ($NoReboot -or $Force) {
        Write-Info 'Exiting now (-Force / -NoReboot suppresses the reboot prompt). Reboot manually.'
        exit 0
    }
    $r = Read-Host 'Reboot now? (y/N)'
    if ($r -match '^[Yy]') {
        Write-Warn2 'FORCED REBOOT — save work in any open application NOW; data in unsaved buffers WILL be lost.'
        Write-Info 'Rebooting in 10 seconds... Ctrl+C to cancel.'
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    } else {
        Write-Warn2 'Reboot manually before re-running this script.'
    }
    exit 0
}

if ($rebootNeeded) { Invoke-RebootGate -Reason 'Windows feature changes' }

# ----------------------------------------------------------------------------
# 5. WSL2 kernel (manual path for older Win10) and default version
# ----------------------------------------------------------------------------
Write-Step 'Configuring WSL kernel and default version'

if (-not $useModernInstall) {
    Write-Info 'Older Windows 10 build — downloading WSL2 kernel update MSI'

    # 32-bit check is already enforced up front (section 2). Here we only need
    # to refuse ARM64 — the blob URL hosts the x64 MSI exclusively, and ARM64
    # users on 19041..19043 should upgrade to 21H2 anyway.
    if ($cpu.Architecture -eq 12 -or
        $env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or
        $env:PROCESSOR_ARCHITEW6432  -eq 'ARM64') {
        Write-Err2 'WSL2 kernel MSI from blob storage is x64-only; this CPU is ARM64.'
        Write-Info 'Update to Windows 10 21H2 (build 19044+) — the modern `wsl --install` supports ARM64.'
        Write-Info 'Or download the matching kernel manually: https://aka.ms/wsl2kernel'
        exit 1
    }

    # NOTE: `aka.ms/wsl2kernel` redirects to a Microsoft Learn documentation page
    # (HTML), NOT to the MSI binary — using it here saves the HTML page as the
    # .msi file and Get-AuthenticodeSignature then fails with a misleading
    # "Status: NotSigned" error. The direct blob URL is the canonical MSI source.
    # If that URL changes in the future, update it here; do NOT switch back to
    # aka.ms/wsl2kernel without verifying the redirect chain ends at a .msi.
    $kernelUrl = 'https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi'
    # Unique temp path — fixed names in a user-writable temp dir are clobber /
    # symlink / hardlink-attack vectors when the script runs elevated. New-
    # TemporaryFile atomically creates a 0-byte file with a random name (O_EXCL
    # semantics); we then move it to a .msi extension so msiexec recognises it.
    $tmp = New-TemporaryFile
    $kernelMsi = [System.IO.Path]::ChangeExtension($tmp.FullName, '.msi')
    Move-Item -LiteralPath $tmp.FullName -Destination $kernelMsi -Force
    try {
        Invoke-WebRequest -Uri $kernelUrl -OutFile $kernelMsi -UseBasicParsing

        # The MSI runs elevated; verify Microsoft's Authenticode signature before exec.
        Write-Info 'Verifying Authenticode signature of downloaded MSI...'
        $sig = Get-AuthenticodeSignature -FilePath $kernelMsi
        if ($sig.Status -ne 'Valid') {
            throw "MSI signature is not Valid (Status: $($sig.Status))"
        }
        if ($sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
            throw "MSI signer is not Microsoft: $($sig.SignerCertificate.Subject)"
        }
        Write-Ok "MSI signature verified ($($sig.SignerCertificate.Subject))"

        # Absolute path for msiexec.exe + `Start-Process -Wait` does NOT throw
        # on non-zero MSI exits, so capture the process and check ExitCode.
        $msiExe = if ([Environment]::Is64BitOperatingSystem -and `
                      -not [Environment]::Is64BitProcess) {
            Join-Path $env:WINDIR 'Sysnative\msiexec.exe'
        } else {
            Join-Path $env:WINDIR 'System32\msiexec.exe'
        }
        $msi = Start-Process -FilePath $msiExe `
            -ArgumentList "/i `"$kernelMsi`" /quiet /norestart" `
            -Wait -PassThru
        # msiexec success codes — 0 = clean, 3010 = ERROR_SUCCESS_REBOOT_REQUIRED
        # (install completed, a reboot is pending), 1641 = ERROR_SUCCESS_REBOOT_INITIATED
        # (install completed AND reboot is being initiated — we suppress this with
        # /norestart but allow defensively in case msiexec ignores it).
        switch ($msi.ExitCode) {
            0     { }
            3010  { Write-Warn2 'MSI install succeeded but reboot is required (msiexec 3010)'; $rebootNeeded = $true }
            1641  { Write-Warn2 'MSI install succeeded and reboot was initiated (msiexec 1641)' }
            default { throw "msiexec exited with code $($msi.ExitCode)" }
        }
        Write-Ok 'WSL2 kernel update installed'
    } catch {
        Write-Err2 "Failed to install WSL2 kernel MSI: $_"
        Write-Info 'Download manually: https://aka.ms/wsl2kernel'
        exit 1
    } finally {
        # Remove the MSI on every exit path — success, throw, or signature-reject.
        if (Test-Path -LiteralPath $kernelMsi) {
            Remove-Item -LiteralPath $kernelMsi -Force -ErrorAction SilentlyContinue
        }
    }

    # msiexec 3010 set $rebootNeeded — bail to reboot BEFORE attempting
    # `wsl --set-default-version` (which would fail with the kernel pending reboot).
    if ($rebootNeeded) { Invoke-RebootGate -Reason 'WSL2 kernel MSI install' }
}

try {
    Invoke-Wsl --set-default-version 2 | Out-Null
    Write-Ok 'Default WSL version set to 2'
} catch {
    Write-Warn2 "Could not set default WSL version yet: $_"
    Write-Info  'This is normal if a reboot is pending — re-run after reboot.'
}

if ($useModernInstall) {
    try {
        Invoke-Wsl --update | Out-Null
        Write-Ok 'WSL runtime updated (wsl --update)'
    } catch {
        Write-Warn2 "wsl --update failed (not fatal): $_"
    }
}

# ----------------------------------------------------------------------------
# 6. Distro selection
# ----------------------------------------------------------------------------
Write-Step 'Selecting Linux distribution'

function Get-OnlineDistros {
    try {
        $raw = & $script:WslExe --list --online 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { return @() }
        $lines = $raw -split "`r?`n" | Where-Object { $_ -match '^\s*[A-Za-z0-9]' }
        # Locale-agnostic parser. The English header line ("NAME FRIENDLY NAME")
        # is localized on non-English Windows, so matching that exact text would
        # silently skip every row on a German/Spanish/etc. host. Instead, classify
        # each line by content:
        #   - preamble sentences end with '.' or contain literal 'wsl.exe'
        #   - header rows have an all-CAPS first token (NAME / NOMBRE / NOM / NAMA)
        #   - data rows have a mixed-case distro name as the first token
        $rows = @()
        foreach ($l in $lines) {
            $trimmed = $l.Trim()
            if ($trimmed.Length -eq 0) { continue }
            if ($trimmed -match 'wsl\.exe' -or $trimmed.EndsWith('.')) { continue }

            $parts = $trimmed -split '\s{2,}', 2
            if ($parts.Count -lt 1 -or -not $parts[0]) { continue }
            $name = $parts[0]
            # Skip the localized header row — distro names like "Ubuntu", "Debian",
            # "kali-linux" are never all-uppercase; headers always are.
            if ($name -cmatch '^[A-Z]+$') { continue }

            $rows += [pscustomobject]@{
                Name     = $name
                Friendly = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
            }
        }
        return $rows
    } catch {
        return @()
    }
}

if (-not $useModernInstall) {
    # `wsl --install -d <Distro>` doesn't exist on Win10 19041..19043 — distros come
    # from the Microsoft Store. Honor an explicit -Distro by surfacing it in the
    # guidance, then clear it so section 7 + summary don't claim a non-existent install.
    $requested = if ($Distro) { $Distro } else { '<DistroName>' }
    if ($Distro) {
        Write-Warn2 "Explicit '-Distro $Distro' on legacy Win10 (build $build) cannot be auto-installed."
    } else {
        Write-Warn2 'On this older Windows 10 build, distros must be installed from the Microsoft Store.'
    }
    Write-Info 'Open the Microsoft Store, search for Ubuntu / Debian / Kali / openSUSE / etc., and click Install.'
    Write-Info "Then run: wsl --set-default $requested"
    $Distro = $null
} elseif (-not $Distro) {
    $rows = Get-OnlineDistros
    if ($rows.Count -gt 0) {
        Write-Host ''
        Write-Host 'Available distros:' -ForegroundColor Cyan
        for ($i = 0; $i -lt $rows.Count; $i++) {
            '{0,3}.  {1,-28} {2}' -f ($i + 1), $rows[$i].Name, $rows[$i].Friendly | Write-Host
        }
        Write-Host ''
        $pick = Read-Host 'Pick a number, type a name, or press Enter for Ubuntu'
        if ([string]::IsNullOrWhiteSpace($pick)) {
            $Distro = 'Ubuntu'
        } elseif ($pick -match '^\d+$') {
            $idx = [int]$pick - 1
            if ($idx -ge 0 -and $idx -lt $rows.Count) {
                $Distro = $rows[$idx].Name
            } else {
                Write-Err2 "Index $pick out of range"
                exit 1
            }
        } else {
            $Distro = $pick.Trim()
        }
    } else {
        Write-Warn2 "Could not enumerate online distros — defaulting to 'Ubuntu'."
        $Distro = 'Ubuntu'
    }
}

# ----------------------------------------------------------------------------
# 7. Distro install
# ----------------------------------------------------------------------------
if ($Distro -and $useModernInstall) {
    Write-Step "Installing distro: $Distro"
    try {
        Invoke-Wsl --install -d $Distro --no-launch
        Write-Ok "Distro '$Distro' installed"
        Write-Info "Launch with: wsl -d $Distro"
        Write-Info 'You will be prompted to create a UNIX username and password on first launch.'
    } catch {
        Write-Err2 "Failed to install distro '$Distro': $_"
        Write-Info 'Possible causes: distro name not recognized, wsl --install not supported on this'
        Write-Info 'build (a customized image can disable it), or transient network error.'
        Write-Info 'List available distros: wsl --list --online'
        Write-Info "Or install manually from the Microsoft Store, then run: wsl --set-default $Distro"
        exit 1
    }
}

# ----------------------------------------------------------------------------
# 8. Summary
# ----------------------------------------------------------------------------
# `$rebootNeeded` is handled inline at every transition point via Invoke-RebootGate
# — Section 4 (feature enable / pending states) and Section 5 (MSI 3010). By the
# time we reach the Summary block, $rebootNeeded is guaranteed false.
Write-Step 'Summary'
if ($Distro) {
    Write-Ok "WSL installation steps completed. Launch with: wsl -d $Distro"
    Write-Info "Distro installed: $Distro"
} elseif (-not $useModernInstall) {
    Write-Ok 'WSL kernel + Windows features are ready.'
    Write-Info 'Install a distro from the Microsoft Store, then run: wsl --set-default <DistroName>'
} else {
    Write-Ok 'WSL is ready. Install a distro with: wsl --install -d <DistroName>'
}
