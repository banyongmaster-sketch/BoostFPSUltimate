<#
.SYNOPSIS
    Boost FPS Ultimate - One Line Installer

.DESCRIPTION
    Automated installer for Boost FPS Ultimate

    Features:
    - Administrator elevation
    - GitHub Raw downloader
    - Config manifest system
    - Retry failed downloads
    - User-Agent support
    - Desktop shortcut
    - Start Menu shortcut
    - Install summary
#>

$ErrorActionPreference = "Stop"

# =====================================
# CONFIG
# =====================================

$RepoBase = "https://raw.githubusercontent.com/banyongmaster-sketch/BoostFPSUltimate/main/BoostFPSUltimate/BoostFPSUltimate"
$InstallDir = "$env:LOCALAPPDATA\BoostFPSUltimate"

$Headers = @{
    "User-Agent" = "Mozilla/5.0 BoostFPSUltimateInstaller/1.0"
    "Accept" = "application/vnd.github.raw"
}


# =====================================
# ADMIN CHECK
# =====================================

function Test-BFUAdmin {

    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()

    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltinRole]::Administrator
    )
}


if (-not (Test-BFUAdmin)) {

    Write-Host ""
    Write-Host "Requesting Administrator permission..." -ForegroundColor Yellow

    $cmd = "irm '$RepoBase/install.ps1' | iex"
    
    Start-Process powershell `
        -Verb RunAs `
        -ArgumentList "-NoExit","-Command",$cmd

    exit
}



# =====================================
# HEADER
# =====================================

Clear-Host

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "      Boost FPS Ultimate Installer"
Write-Host "=====================================" -ForegroundColor Cyan

Write-Host ""



# =====================================
# CREATE INSTALL DIR
# =====================================

if (!(Test-Path $InstallDir)) {

    New-Item `
        -Path $InstallDir `
        -ItemType Directory `
        -Force | Out-Null
}



# =====================================
# DOWNLOAD CONFIG
# =====================================

$configUrl = "$RepoBase/config.json"


Write-Host "[1/3] Downloading manifest..."
Write-Host $configUrl


try {

    $configRaw = Invoke-WebRequest `
        -Uri $configUrl `
        -Headers $Headers `
        -UseBasicParsing


    $config = $configRaw.Content | ConvertFrom-Json


}
catch {

    Write-Host ""
    Write-Host "FAILED: Cannot download config.json" -ForegroundColor Red

    Write-Host $_.Exception.Message

    exit 1
}



# Override RepoBase from config

if ($config.RepoBaseUrl) {

    $RepoBase = $config.RepoBaseUrl.TrimEnd("/")

}



Write-Host ""

Write-Host "Application : $($config.AppName)"
Write-Host "Version     : $($config.Version)"
Write-Host ""



# =====================================
# DOWNLOAD FILES
# =====================================

Write-Host "[2/3] Installing files..."

$total = $config.Files.Count

$current = 0

$failed = @()



foreach ($file in $config.Files) {


    $current++


    $url = "$RepoBase/$file"


    $destination = Join-Path `
        $InstallDir `
        ($file -replace "/","\"
        )


    $folder = Split-Path $destination



    if (!(Test-Path $folder)) {

        New-Item `
            -Path $folder `
            -ItemType Directory `
            -Force | Out-Null

    }



    Write-Progress `
        -Activity "Downloading Boost FPS Ultimate" `
        -Status "$file ($current/$total)" `
        -PercentComplete (($current/$total)*100)



    $success = $false



    for ($try = 1; $try -le 3; $try++) {


        try {


            Invoke-WebRequest `
                -Uri $url `
                -Headers $Headers `
                -OutFile $destination `
                -UseBasicParsing



            if ((Get-Item $destination).Length -gt 0) {

                $success = $true

                break

            }


        }
        catch {


            Write-Host ""
            Write-Host `
            "Retry $try/3 : $file" `
            -ForegroundColor Yellow


            Start-Sleep -Seconds 3


        }

    }



    if (!$success) {

        $failed += $file

    }

}



Write-Progress `
    -Activity "Downloading Boost FPS Ultimate" `
    -Completed




# =====================================
# CREATE SHORTCUT
# =====================================

Write-Host ""

Write-Host "[3/3] Creating shortcuts..."



$wsh = New-Object -ComObject WScript.Shell


$target = Join-Path `
    $InstallDir `
    "BoostFPS.ps1"



$args = "-ExecutionPolicy Bypass -NoExit -File `"$target`""



$locations = @(

    [Environment]::GetFolderPath("Desktop")

    [Environment]::GetFolderPath("StartMenu") + "\Programs"

)



foreach ($location in $locations) {


    $shortcut = $wsh.CreateShortcut(

        (Join-Path `
        $location `
        "Boost FPS Ultimate.lnk")

    )


    $shortcut.TargetPath = "powershell.exe"

    $shortcut.Arguments = $args

    $shortcut.WorkingDirectory = $InstallDir

    $shortcut.IconLocation = "powershell.exe"

    $shortcut.Save()

}



# =====================================
# SUMMARY
# =====================================


Write-Host ""

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "          INSTALL SUMMARY"
Write-Host "=====================================" -ForegroundColor Cyan


Write-Host ""

Write-Host "Install Path:"
Write-Host $InstallDir


Write-Host ""

Write-Host "Installed:"
Write-Host "$($total - $failed.Count) / $total files"



if ($failed.Count -eq 0) {


    Write-Host ""

    Write-Host "Installation completed successfully!" `
        -ForegroundColor Green


}
else {


    Write-Host ""

    Write-Host "Failed Files:" `
        -ForegroundColor Red


    foreach ($f in $failed) {

        Write-Host " - $f"

    }


}



Write-Host ""

Write-Host "Launch:"
Write-Host "powershell -ExecutionPolicy Bypass -File `"$target`""

Write-Host ""

Pause
