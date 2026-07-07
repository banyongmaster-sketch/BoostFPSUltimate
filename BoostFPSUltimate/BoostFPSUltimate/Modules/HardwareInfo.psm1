<#
.SYNOPSIS
    HardwareInfo.psm1 - Hardware / OS detection
.DESCRIPTION
    Uses only real, documented Windows sources: Get-CimInstance (WMI),
    registry keys that Microsoft documents, and built-in cmdlets
    (Get-Tpm, Confirm-SecureBootUEFI, Get-Volume, Get-NetAdapter...).

    NOTE ON LIMITATIONS (read before using):
    - Mouse DPI: Windows has no standard API exposing hardware DPI for
      generic HID mice. We report Polling behavior indirectly via HID
      report descriptors when possible, otherwise "Unknown - vendor
      software required (Logitech G Hub / Razer Synapse / etc.)".
    - Monitor G-Sync/FreeSync: not exposed via WMI. We report refresh
      rate/resolution (real) and VRR capability as "Unknown - check
      NVIDIA Control Panel / AMD Software / Windows Display Settings".
    - These are called out explicitly rather than guessed, per the
      project's own rule: no fabricated values.
#>

function Get-BFUCPUInfo {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    [PSCustomObject]@{
        Name              = $cpu.Name.Trim()
        Manufacturer      = $cpu.Manufacturer
        Cores             = $cpu.NumberOfCores
        Threads           = $cpu.NumberOfLogicalProcessors
        BaseClockMHz      = $cpu.MaxClockSpeed
        L2CacheKB         = $cpu.L2CacheSize
        L3CacheKB         = $cpu.L3CacheSize
        VirtualizationOn  = $cpu.VirtualizationFirmwareEnabled
        CurrentLoadPct    = $cpu.LoadPercentage
    }
}

function Get-BFURAMInfo {
    $sticks = Get-CimInstance Win32_PhysicalMemory
    $os     = Get-CimInstance Win32_OperatingSystem
    $totalGB = [math]::Round(($sticks | Measure-Object Capacity -Sum).Sum / 1GB, 1)
    $usedGB  = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)

    [PSCustomObject]@{
        TotalGB      = $totalGB
        UsedGB       = $usedGB
        SpeedMHz     = ($sticks | Select-Object -First 1).ConfiguredClockSpeed
        Manufacturer = ($sticks | Select-Object -First 1).Manufacturer
        SlotsUsed    = $sticks.Count
        MemoryType   = switch (($sticks | Select-Object -First 1).SMBIOSMemoryType) {
                            26 { "DDR4" } 34 { "DDR5" } 24 { "DDR3" } default { "Unknown" }
                       }
    }
}

function Get-BFUGPUInfo {
    Get-CimInstance Win32_VideoController | Where-Object { $_.AdapterCompatibility } | ForEach-Object {
        [PSCustomObject]@{
            Name         = $_.Name
            DriverVer    = $_.DriverVersion
            VRAM_MB      = if ($_.AdapterRAM) { [math]::Round($_.AdapterRAM / 1MB) } else { "Unknown (>4GB reports wrap in WMI, check DXDiag)" }
            Resolution   = "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"
            RefreshHz    = $_.CurrentRefreshRate
        }
    }
}

function Get-BFUHagsStatus {
    # HAGS = Hardware-accelerated GPU Scheduling, documented registry value
    $path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    try {
        $val = Get-ItemPropertyValue -Path $path -Name "HwSchMode" -ErrorAction Stop
        return @{ Enabled = ($val -eq 2); RawValue = $val }
    } catch {
        return @{ Enabled = $false; RawValue = "NotSet" }
    }
}

function Get-BFUMotherboardInfo {
    $board = Get-CimInstance Win32_BaseBoard
    $bios  = Get-CimInstance Win32_BIOS
    [PSCustomObject]@{
        Manufacturer = $board.Manufacturer
        Model        = $board.Product
        BIOSVersion  = $bios.SMBIOSBIOSVersion
        BIOSDate     = $bios.ReleaseDate
    }
}

function Get-BFUStorageInfo {
    Get-PhysicalDisk | ForEach-Object {
        $disk = $_
        [PSCustomObject]@{
            Model      = $disk.FriendlyName
            MediaType  = $disk.MediaType          # SSD / HDD / Unspecified
            BusType    = $disk.BusType             # NVMe / SATA / USB
            SizeGB     = [math]::Round($disk.Size / 1GB, 1)
            HealthStatus = $disk.HealthStatus
        }
    }
}

function Get-BFUTrimStatus {
    # DisableDeleteNotify 0 = TRIM enabled, 1 = disabled
    $result = fsutil behavior query DisableDeleteNotify 2>$null
    [PSCustomObject]@{ RawOutput = $result }
}

function Get-BFUMonitorInfo {
    Get-CimInstance Win32_VideoController | Select-Object -First 1 | ForEach-Object {
        [PSCustomObject]@{
            Resolution = "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)"
            RefreshHz  = $_.CurrentRefreshRate
            HDR_VRR    = "Unknown - not exposed via WMI. Check Windows Settings > Display > HDR / AMD-NVIDIA control panel"
        }
    }
}

function Get-BFUSecurityFeatures {
    $result = [ordered]@{}

    try { $result["SecureBoot"] = Confirm-SecureBootUEFI } catch { $result["SecureBoot"] = "Unsupported/Legacy BIOS" }
    try { $tpm = Get-Tpm; $result["TPM_Present"] = $tpm.TpmPresent; $result["TPM_Enabled"] = $tpm.TpmEnabled } catch { $result["TPM"] = "Unavailable" }

    $vbsPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
    try {
        $result["VBS_ConfiguredEnabled"] = (Get-ItemPropertyValue -Path $vbsPath -Name "EnableVirtualizationBasedSecurity" -ErrorAction Stop) -eq 1
    } catch { $result["VBS_ConfiguredEnabled"] = "Unknown" }

    $miPath = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
    try {
        $result["MemoryIntegrity"] = (Get-ItemPropertyValue -Path $miPath -Name "Enabled" -ErrorAction Stop) -eq 1
    } catch { $result["MemoryIntegrity"] = "Unknown" }

    [PSCustomObject]$result
}

function Get-BFUWindowsInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    [PSCustomObject]@{
        Caption     = $os.Caption
        Build       = $os.BuildNumber
        Version     = $os.Version
        Architecture= $os.OSArchitecture
        InstallDate = $os.InstallDate
    }
}

function Get-BFUFullReport {
    Write-Host "`n=== Boost FPS Ultimate - Hardware & System Report ===" -ForegroundColor Cyan
    [PSCustomObject]@{
        CPU      = Get-BFUCPUInfo
        RAM      = Get-BFURAMInfo
        GPU      = Get-BFUGPUInfo
        HAGS     = Get-BFUHagsStatus
        Motherboard = Get-BFUMotherboardInfo
        Storage  = Get-BFUStorageInfo
        Monitor  = Get-BFUMonitorInfo
        Security = Get-BFUSecurityFeatures
        Windows  = Get-BFUWindowsInfo
    }
}

Export-ModuleMember -Function Get-BFUCPUInfo, Get-BFURAMInfo, Get-BFUGPUInfo, Get-BFUHagsStatus, `
    Get-BFUMotherboardInfo, Get-BFUStorageInfo, Get-BFUTrimStatus, Get-BFUMonitorInfo, `
    Get-BFUSecurityFeatures, Get-BFUWindowsInfo, Get-BFUFullReport
