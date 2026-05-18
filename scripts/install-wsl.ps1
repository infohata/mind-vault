#Requires -Version 5.1
#Requires -PSEdition Desktop
#Requires -RunAsAdministrator
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
function Invoke-Wsl {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & wsl.exe @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "wsl.exe $($Arguments -join ' ') exited with code $code"
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
function Test-Feature {
    param([string]$Name)
    $f = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction SilentlyContinue
    return ($null -ne $f) -and ($f.State -eq 'Enabled')
}

function Enable-Feature {
    param([string]$Name)
    $result = Enable-WindowsOptionalFeature -Online -FeatureName $Name -All -NoRestart -ErrorAction Stop
    return [bool]$result.RestartNeeded
}

Write-Step 'Enabling required Windows features'
$rebootNeeded = $false
foreach ($feat in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
    if (Test-Feature -Name $feat) {
        Write-Ok "$feat already enabled"
    } else {
        Write-Info "Enabling $feat ..."
        if (Enable-Feature -Name $feat) { $rebootNeeded = $true }
        Write-Ok "$feat enabled"
    }
}

# `wsl --set-default-version`, `wsl --update`, and especially `wsl --install`
# will hard-fail until the feature enable is finalized by a reboot — bail out
# now and ask the user to re-run after rebooting.
if ($rebootNeeded) {
    Write-Warn2 'Windows feature changes require a reboot before WSL commands can run.'
    Write-Info  'After reboot, re-run this script; already-enabled features are detected as such'
    Write-Info  'and the kernel / distro install will continue from where it left off.'
    if ($NoReboot -or $Force) {
        Write-Info 'Exiting now (-Force / -NoReboot suppresses the reboot prompt). Reboot manually.'
        exit 0
    }
    $r = Read-Host 'Reboot now? (y/N)'
    if ($r -match '^[Yy]') {
        Write-Info 'Rebooting in 5 seconds... Ctrl+C to cancel.'
        Start-Sleep -Seconds 5
        Restart-Computer -Force
    } else {
        Write-Warn2 'Reboot manually before re-running this script.'
    }
    exit 0
}

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

    $kernelUrl = 'https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi'
    $kernelMsi = Join-Path $env:TEMP 'wsl_update_x64.msi'
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

        # `Start-Process -Wait` does NOT throw on non-zero MSI exits — capture
        # the process object with -PassThru and inspect ExitCode explicitly.
        $msi = Start-Process -FilePath 'msiexec.exe' `
            -ArgumentList "/i `"$kernelMsi`" /quiet /norestart" `
            -Wait -PassThru
        if ($msi.ExitCode -ne 0) {
            throw "msiexec exited with code $($msi.ExitCode)"
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
        $raw = & wsl.exe --list --online 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { return @() }
        $lines = $raw -split "`r?`n" | Where-Object { $_ -match '^\s*[A-Za-z0-9]' }
        # Skip ALL preamble lines ("The following...", "Install using...", etc.)
        # until the header row, then parse only what follows.
        $sawHeader = $false
        $rows = @()
        foreach ($l in $lines) {
            if (-not $sawHeader) {
                if ($l -match '^\s*NAME\s+FRIENDLY') { $sawHeader = $true }
                continue
            }
            if ($l.Trim().Length -eq 0) { continue }
            $parts = $l.Trim() -split '\s{2,}', 2
            if ($parts.Count -ge 1 -and $parts[0]) {
                $rows += [pscustomobject]@{
                    Name     = $parts[0].Trim()
                    Friendly = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
                }
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
        Write-Info 'List available distros with: wsl --list --online'
        exit 1
    }
}

# ----------------------------------------------------------------------------
# 8. Summary
# ----------------------------------------------------------------------------
# `$rebootNeeded` is handled inline (section 4 exits the script the moment a
# feature enable reports RestartNeeded), so by the time we reach Summary the
# reboot prompt is dead code — kept the message simple.
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
