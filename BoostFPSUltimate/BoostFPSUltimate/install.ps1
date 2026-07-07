<#
.SYNOPSIS
    Boost FPS Ultimate - One-line installer
.DESCRIPTION
    Usage (after you host this repo, see README.md):
        irm https://raw.githubusercontent.com/banyongmaster-sketch/BoostFPSUltimate/main/install.ps1 | iex

    What it does:
    1. Checks for Administrator rights (re-launches elevated if needed)
    2. Reads config.json's file manifest from the repo
    3. Downloads each file, verifying it downloaded fully (size check)
    4. Retries failed downloads up to 3 times
    5. Installs to %LocalAppData%\BoostFPSUltimate
    6. Creates Desktop + Start Menu shortcuts
    7. Prints an install summary
#>

$ErrorActionPreference = "Stop"

$RepoBase = "https://raw.githubusercontent.com/banyongmaster-sketch/BoostFPSUltimate/main/BoostFPSUltimate/BoostFPSUltimate"
$InstallDir = "$env:LocalAppData\BoostFPSUltimate"

function Test-BFUAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

if (-not (Test-BFUAdmin)) {
    Write-Host "Re-launching as Administrator..." -ForegroundColor Yellow
    $psCmd = "irm $RepoBase/install.ps1 | iex"
    Start-Process powershell -Verb RunAs -ArgumentList "-NoExit","-Command",$psCmd
    return
}

Write-Host "=== Boost FPS Ultimate Installer ===" -ForegroundColor Cyan
New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null

# 1. Pull the manifest
$configUrl = "$RepoBase/config.json"
Write-Host "Fetching manifest: $configUrl"
$config = (Invoke-WebRequest -Uri $configUrl -UseBasicParsing).Content | ConvertFrom-Json

$total = $config.Files.Count
$done = 0
$failed = @()

foreach ($relPath in $config.Files) {
    $done++
    $url = "$RepoBase/$relPath"
    $dest = Join-Path $InstallDir $relPath.Replace("/", "\")
    $destFolder = Split-Path $dest -Parent
    if (-not (Test-Path $destFolder)) { New-Item -Path $destFolder -ItemType Directory -Force | Out-Null }

    Write-Progress -Activity "Installing Boost FPS Ultimate" -Status "$relPath ($done/$total)" -PercentComplete (($done / $total) * 100)

    $attempt = 0
    $ok = $false
    while ($attempt -lt 3 -and -not $ok) {
        $attempt++
        try {
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
            if ((Get-Item $dest).Length -gt 0) { $ok = $true }
            else { throw "Downloaded file is 0 bytes" }
        } catch {
            Write-Host "  Retry $attempt/3 for $relPath ($($_.Exception.Message))" -ForegroundColor DarkYellow
            Start-Sleep -Seconds 1
        }
    }
    if (-not $ok) { $failed += $relPath }
}

Write-Progress -Activity "Installing Boost FPS Ultimate" -Completed

# Desktop + Start Menu shortcuts
$wsh = New-Object -ComObject WScript.Shell
$targetScript = Join-Path $InstallDir "BoostFPS.ps1"
$shortcutArgs = "-NoExit -ExecutionPolicy Bypass -File `"$targetScript`""

foreach ($shortcutDir in @(
    [Environment]::GetFolderPath("Desktop"),
    [Environment]::GetFolderPath("StartMenu") + "\Programs"
)) {
    $lnk = $wsh.CreateShortcut((Join-Path $shortcutDir "Boost FPS Ultimate.lnk"))
    $lnk.TargetPath = "powershell.exe"
    $lnk.Arguments = $shortcutArgs
    $lnk.WorkingDirectory = $InstallDir
    $lnk.IconLocation = "powershell.exe"
    $lnk.Save()
}

Write-Host "`n=== Install Summary ===" -ForegroundColor Cyan
Write-Host "Installed to: $InstallDir"
Write-Host "Files installed: $($total - $failed.Count)/$total"
if ($failed.Count -gt 0) {
    Write-Host "Failed files:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "Re-run the installer to retry failed files." -ForegroundColor Yellow
} else {
    Write-Host "All files installed successfully." -ForegroundColor Green
}
Write-Host "`nLaunch it from the Desktop shortcut, or run:"
Write-Host "  powershell -ExecutionPolicy Bypass -File `"$targetScript`"" -ForegroundColor Cyan
