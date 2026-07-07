<#
.SYNOPSIS
    NetworkOptimize.psm1 - TCP/network tuning for gaming latency
.DESCRIPTION
    Uses Set-NetTCPSetting / netsh (documented, supported cmdlets).
    Nagle's Algorithm disabling is included under "Advanced" risk level
    with an explicit warning, since it's a legitimate, Microsoft-documented
    per-adapter registry tweak (TcpAckFrequency / TCPNoDelay) but can
    increase overall packet count on the network.
#>

function Set-BFUTcpAutoTuning {
    param([ValidateSet("normal","highlyrestricted","restricted","disabled")][string]$Level = "normal")
    netsh int tcp set global autotuninglevel=$Level | Out-Null
    Write-BFULog -Message "TCP auto-tuning set to $Level" -Level SUCCESS
}

function Enable-BFUTcpFastOpen {
    netsh int tcp set global fastopen=enabled | Out-Null
    Write-BFULog -Message "TCP Fast Open enabled" -Level SUCCESS
}

function Set-BFUEcn {
    param([ValidateSet("enabled","disabled")][string]$State = "enabled")
    netsh int tcp set global ecncapability=$State | Out-Null
    Write-BFULog -Message "ECN capability set to $State" -Level SUCCESS
}

function Set-BFUGamingDns {
    <#
    .SYNOPSIS
        Points DNS to a low-latency public resolver. This changes actual
        internet DNS resolution behavior for ALL traffic on the adapter -
        gated as a distinct opt-in action, not bundled silently.
    #>
    param(
        [Parameter(Mandatory)][string]$InterfaceAlias,
        [string[]]$Servers = @("1.1.1.1","8.8.8.8")
    )
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $Servers
    Write-BFULog -Message "DNS for '$InterfaceAlias' set to $($Servers -join ', ')" -Level SUCCESS
}

function Disable-BFUNagleAlgorithm {
    <#
    .SYNOPSIS
        RISK: MEDIUM-HIGH. Disables Nagle's Algorithm per network interface.
        Documented registry path (Microsoft KB): under each interface GUID
        in Tcpip\Parameters\Interfaces. Reduces send-buffering latency but
        increases packet count - can be worse on congested/limited links.
    #>
    param([switch]$Force)
    if (-not $Force) {
        Write-BFULog -Message "Disable-BFUNagleAlgorithm skipped - requires -Force (increases packet rate)" -Level SKIPPED
        return
    }
    $ifPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    Get-ChildItem $ifPath | ForEach-Object {
        Backup-BFURegistryKey -KeyPath "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($_.PSChildName)" -Tag "TcpipIf_$($_.PSChildName)" | Out-Null
        Set-ItemProperty -Path $_.PSPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $_.PSPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force
    }
    Write-BFULog -Message "Nagle's Algorithm disabled on all interfaces (HIGH RISK setting applied)" -Level WARNING
}

function Invoke-BFUNetworkOptimize {
    param([ValidateSet("Safe","Advanced")][string]$RiskLevel = "Safe")
    Invoke-BFUSafe -ActionName "Set TCP auto-tuning to Normal" -Action { Set-BFUTcpAutoTuning -Level normal }
    Invoke-BFUSafe -ActionName "Enable TCP Fast Open" -Action { Enable-BFUTcpFastOpen }
    Invoke-BFUSafe -ActionName "Enable ECN" -Action { Set-BFUEcn -State enabled }

    if ($RiskLevel -eq "Advanced") {
        Invoke-BFUSafe -ActionName "Disable Nagle's Algorithm" -Action { Disable-BFUNagleAlgorithm -Force }
    }
}

Export-ModuleMember -Function Set-BFUTcpAutoTuning, Enable-BFUTcpFastOpen, Set-BFUEcn, `
    Set-BFUGamingDns, Disable-BFUNagleAlgorithm, Invoke-BFUNetworkOptimize
