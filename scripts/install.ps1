# Silvr Installer for Windows (PowerShell)
# Usage: iwr -useb https://raw.githubusercontent.com/haseebuchiha/silvr/main/scripts/install.ps1 | iex
# Or: & ([scriptblock]::Create((iwr -useb https://raw.githubusercontent.com/haseebuchiha/silvr/main/scripts/install.ps1))) -NoOnboard

param(
    [string]$InstallMethod = "npm",
    [string]$Tag = "latest",
    [string]$GitDir = "$env:USERPROFILE\silvr",
    [switch]$NoOnboard,
    [switch]$NoGitUpdate,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Colors — monochrome silvr palette
# Use [char]27 for ESC since backtick-e only works in PS 6+
$ESC = [char]27
$C_ACCENT = "$ESC[38;2;255;255;255m"
$C_SUCCESS = "$ESC[38;2;74;222;128m"
$C_WARN = "$ESC[38;2;255;176;32m"
$C_ERR = "$ESC[38;2;230;57;70m"
$C_MUTED = "$ESC[38;2;90;100;128m"
$C_NC = "$ESC[0m"

function Write-Status {
    param([string]$Message, [string]$Level = "info")
    $msg = switch ($Level) {
        "success" { "${C_SUCCESS}OK${C_NC} $Message" }
        "warn" { "${C_WARN}!${C_NC} $Message" }
        "error" { "${C_ERR}X${C_NC} $Message" }
        default { "${C_MUTED}>${C_NC} $Message" }
    }
    Write-Host $msg
}

function Write-Banner {
    Write-Host ""
    Write-Status "${C_ACCENT}  * Silvr Installer${C_NC}"
    Write-Status "${C_MUTED}  All your chats, one gateway.${C_NC}"
    Write-Host ""
}

function Get-ExecutionPolicyStatus {
    $policy = Get-ExecutionPolicy
    if ($policy -eq "Restricted" -or $policy -eq "AllSigned") {
        return @{ Blocked = $true; Policy = $policy }
    }
    return @{ Blocked = $false; Policy = $policy }
}

function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-ExecutionPolicy {
    $status = Get-ExecutionPolicyStatus
    if ($status.Blocked) {
        Write-Status "PowerShell execution policy is set to: $($status.Policy)" -Level warn
        Write-Status "This prevents scripts like npm.ps1 from running." -Level warn
        Write-Host ""

        # Try to set execution policy for current process
        try {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -ErrorAction Stop
            Write-Status "Set execution policy to RemoteSigned for current process" -Level success
            return $true
        } catch {
            Write-Status "Could not automatically set execution policy" -Level error
            Write-Host ""
            Write-Status "To fix this, run:"
            Write-Status "  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process"
            Write-Host ""
            Write-Status "Or run PowerShell as Administrator and execute:"
            Write-Status "  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine"
            return $false
        }
    }
    return $true
}

function Get-NodeVersion {
    try {
        $version = node --version 2>$null
        if ($version) {
            return $version -replace '^v', ''
        }
    } catch { }
    return $null
}

function Get-NpmVersion {
    try {
        $version = npm --version 2>$null
        if ($version) {
            return $version
        }
    } catch { }
    return $null
}

function Install-Node {
    Write-Status "Node.js not found"
    Write-Status "Installing Node.js..."

    # Try winget first
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Status "  Using winget..."
        try {
            winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            Write-Status "  Node.js installed via winget" -Level success
            return $true
        } catch {
            Write-Status "  Winget install failed: $_" -Level warn
        }
    }

    # Try chocolatey
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Status "  Using chocolatey..."
        try {
            choco install nodejs-lts -y 2>&1 | Out-Null
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            Write-Status "  Node.js installed via chocolatey" -Level success
            return $true
        } catch {
            Write-Status "  Chocolatey install failed: $_" -Level warn
        }
    }

    # Try scoop
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Status "  Using scoop..."
        try {
            scoop install nodejs-lts 2>&1 | Out-Null
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            Write-Status "  Node.js installed via scoop" -Level success
            return $true
        } catch {
            Write-Status "  Scoop install failed: $_" -Level warn
        }
    }

    Write-Status "Could not install Node.js automatically" -Level error
    Write-Status "Please install Node.js 22+ manually from: https://nodejs.org"
    return $false
}

function Ensure-Node {
    $nodeVersion = Get-NodeVersion
    if ($nodeVersion) {
        $major = [int]($nodeVersion -split '\.')[0]
        if ($major -ge 22) {
            Write-Status "Node.js v$nodeVersion found" -Level success
            return $true
        }
        Write-Status "Node.js v$nodeVersion found, but need v22+" -Level warn
    }
    return Install-Node
}

function Get-GitVersion {
    try {
        $version = git --version 2>$null
        if ($version) {
            return $version
        }
    } catch { }
    return $null
}

function Install-Git {
    Write-Status "Git not found"

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Status "  Installing Git via winget..."
        try {
            winget install Git.Git --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            Write-Status "  Git installed" -Level success
            return $true
        } catch {
            Write-Status "  Winget install failed" -Level warn
        }
    }

    Write-Status "Please install Git for Windows from: https://git-scm.com" -Level error
    return $false
}

function Ensure-Git {
    $gitVersion = Get-GitVersion
    if ($gitVersion) {
        Write-Status "$gitVersion found" -Level success
        return $true
    }
    return Install-Git
}

function Install-SilvrNpm {
    param([string]$Version = "latest")

    Write-Status "Installing Silvr (@haseebuchiha/silvr@$Version)..."

    try {
        npm install -g @haseebuchiha/silvr@$Version --no-fund --no-audit 2>&1
        Write-Status "Silvr installed" -Level success
        return $true
    } catch {
        Write-Status "npm install failed: $_" -Level error
        return $false
    }
}

function Install-SilvrGit {
    param([string]$RepoDir, [switch]$Update)

    Write-Status "Installing Silvr from git..."

    if (!(Test-Path $RepoDir)) {
        Write-Status "  Cloning repository..."
        git clone https://github.com/haseebuchiha/silvr.git $RepoDir 2>&1
    } elseif ($Update) {
        Write-Status "  Updating repository..."
        git -C $RepoDir pull --rebase 2>&1
    }

    # Install pnpm if not present
    if (!(Get-Command pnpm -ErrorAction SilentlyContinue)) {
        Write-Status "  Installing pnpm..."
        npm install -g pnpm 2>&1
    }

    # Install dependencies
    Write-Status "  Installing dependencies..."
    pnpm install --dir $RepoDir 2>&1

    # Build
    Write-Status "  Building..."
    pnpm --dir $RepoDir build 2>&1

    # Create wrapper — CLI command stays `openclaw`
    $wrapperDir = "$env:USERPROFILE\.local\bin"
    if (!(Test-Path $wrapperDir)) {
        New-Item -ItemType Directory -Path $wrapperDir -Force | Out-Null
    }

    @"
@echo off
node "%~dp0..\silvr\dist\entry.js" %*
"@ | Out-File -FilePath "$wrapperDir\openclaw.cmd" -Encoding ASCII -Force

    Write-Status "Silvr installed" -Level success
    return $true
}

function Add-ToPath {
    param([string]$Path)

    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notlike "*$Path*") {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$Path", "User")
        Write-Status "Added $Path to user PATH"
    }
}

# Main
function Main {
    Write-Banner

    Write-Status "Windows detected" -Level success

    # Check and handle execution policy FIRST, before any npm calls
    if (!(Ensure-ExecutionPolicy)) {
        Write-Host ""
        Write-Status "Installation cannot continue due to execution policy restrictions" -Level error
        exit 1
    }

    if (!(Ensure-Node)) {
        exit 1
    }

    if ($InstallMethod -eq "git") {
        if (!(Ensure-Git)) {
            exit 1
        }

        if ($DryRun) {
            Write-Status "[DRY RUN] Would install Silvr from git to $GitDir"
        } else {
            Install-SilvrGit -RepoDir $GitDir -Update:(-not $NoGitUpdate)
        }
    } else {
        # npm method
        if (!(Ensure-Git)) {
            Write-Status "Git is required for npm installs. Please install Git and try again." -Level warn
        }

        if ($DryRun) {
            Write-Status "[DRY RUN] Would install Silvr via npm (tag: $Tag)"
        } else {
            if (!(Install-SilvrNpm -Version $Tag)) {
                exit 1
            }
        }
    }

    # Try to add npm global bin to PATH
    try {
        $npmPrefix = npm config get prefix 2>$null
        if ($npmPrefix) {
            Add-ToPath -Path "$npmPrefix"
        }
    } catch { }

    if (!$NoOnboard -and !$DryRun) {
        Write-Host ""
        Write-Status "Run 'openclaw onboard' to complete setup"
    }

    Write-Host ""
    Write-Status "* Silvr installed successfully!" -Level success
}

Main
