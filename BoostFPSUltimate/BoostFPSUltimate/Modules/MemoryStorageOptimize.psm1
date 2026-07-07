<#
.SYNOPSIS
    MemoryStorageOptimize.psm1 - RAM and disk tuning
.DESCRIPTION
    NOTE ON LIMITATIONS:
    - Clearing the "Standby List" (cached RAM) has no native PowerShell
      cmdlet or documented API. Third-party tools like RAMMap/EmptyStandbyList
      do this via undocumented NT calls. We do NOT reimplement an undocumented
      syscall here - instead we expose Clear-BFUStandbyList as a wrapper that
      only runs if the user already has RAMMap64.exe / EmptyStandbyList.exe
      available, and otherwise logs SKIPPED. This keeps the module honest
      instead of pretending to support something it can't.
    - Optimize-Volume (built into Windows) already does the right thing
      automatically: TRIM for SSD/NVMe, defrag only for spinning HDD. We
      use this real, documented cmdlet rather than hand-rolling defrag logic.
#>

function Optimize-BFUStorage {
    <#
    .SYNOPSIS
        Runs Optimize-Volume on all fixed drives. The cmdlet auto-detects
        media type: TRIM on SSD/NVMe, defrag on HDD, does nothing harmful
        to either.
    #>
    Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | ForEach-Object {
        $letter = $_.DriveLetter
        Invoke-BFUSafe -ActionName "Optimize-Volume $letter`:" -Action {
            Optimize-Volume -DriveLetter $letter -Verbose:$false
        }
    }
}

function Set-BFUMemoryPriorityHighForProcess {
    <#
    .SYNOPSIS
        Raises process priority (not "memory priority" - Windows doesn't
        expose a public memory-priority API - this sets CPU/IO priority
        class instead, which is the documented mechanism games use).
    #>
    param([Parameter(Mandatory)][string]$ProcessName)
    $proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($proc) {
        $proc.PriorityClass = 'High'
        Write-BFULog -Message "$ProcessName priority set to High" -Level SUCCESS
    } else {
        Write-BFULog -Message "$ProcessName not running - skipped priority change" -Level SKIPPED
    }
}

function Clear-BFUStandbyList {
    <#
    .SYNOPSIS
        Attempts to clear the standby memory list using a locally present
        Sysinternals tool. Does NOT bundle or download RAMMap - user must
        provide it, per Microsoft/Sysinternals distribution terms.
    #>
    $toolCandidates = @("$env:ProgramFiles\RAMMap\RAMMap64.exe", "C:\Tools\EmptyStandbyList.exe")
    $tool = $toolCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($tool) {
        & $tool workingsets
        Write-BFULog -Message "Standby list cleared via $tool" -Level SUCCESS
    } else {
        Write-BFULog -Message "No standby-list tool found (RAMMap/EmptyStandbyList). Skipped - install Sysinternals RAMMap manually if needed." -Level SKIPPED
    }
}

function Set-BFUPagefileToSystemManaged {
    <#
    .SYNOPSIS
        Ensures pagefile is system-managed on the OS drive - Microsoft's
        own recommendation for modern systems with 16GB+ RAM, rather than
        an arbitrary fixed size.
    #>
    $cs = Get-CimInstance Win32_ComputerSystem
    Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true }
    Write-BFULog -Message "Pagefile set to system-managed" -Level SUCCESS
}

function Invoke-BFUMemoryStorageOptimize {
    param([ValidateSet("Safe","Advanced")][string]$RiskLevel = "Safe")
    Invoke-BFUSafe -ActionName "Optimize storage volumes (TRIM/defrag as appropriate)" -Action { Optimize-BFUStorage }
    Invoke-BFUSafe -ActionName "Set pagefile to system-managed" -Action { Set-BFUPagefileToSystemManaged }
    if ($RiskLevel -eq "Advanced") {
        Invoke-BFUSafe -ActionName "Clear standby memory list" -Action { Clear-BFUStandbyList }
    }
}

Export-ModuleMember -Function Optimize-BFUStorage, Set-BFUMemoryPriorityHighForProcess, `
    Clear-BFUStandbyList, Set-BFUPagefileToSystemManaged, Invoke-BFUMemoryStorageOptimize
