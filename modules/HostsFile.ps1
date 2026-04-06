<#
.SYNOPSIS
    Hosts File module
#>

function Read-MainHostFile {
    param([Parameter(Mandatory=$true)][string]$FilePath)

    $fullPath = if ([System.IO.Path]::IsPathRooted($FilePath)) { $FilePath } else { Join-Path $ScriptDir $FilePath }

    if (-not (Test-Path $fullPath)) {
        $defaultContent = "# GitHub Hosts`n140.82.121.3 github.com"
        $defaultContent | Out-File -FilePath $fullPath -Encoding UTF8
        Write-Host "  [!] Created default hosts file" -ForegroundColor Yellow
        return @{}
    }

    $hosts = @{}
    $content = Get-Content -Path $fullPath -Encoding UTF8

    foreach ($line in $content) {
        $trimmedLine = $line.Trim()
        if ($trimmedLine -eq '' -or $trimmedLine.StartsWith('#')) { continue }

        $parts = $trimmedLine -split '\s+', 2
        if ($parts.Count -eq 2) {
            $hosts[$parts[1].Trim()] = $parts[0].Trim()
        }
    }

    return $hosts
}

function Update-MainHostFile {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][array]$Results
    )

    $fullPath = if ([System.IO.Path]::IsPathRooted($FilePath)) { $FilePath } else { Join-Path $ScriptDir $FilePath }

    $ipMap = @{}
    foreach ($result in $Results) {
        if ($result.Status -eq 'Replaced') {
            if (-not $ipMap.ContainsKey($result.Domain)) {
                $ipMap[$result.Domain] = $result.IP
            }
        }
    }

    if ($ipMap.Count -eq 0) { return }

    $content = Get-Content -Path $fullPath -Encoding UTF8
    $newContent = @()
    $processedDomains = @{}

    foreach ($line in $content) {
        $trimmedLine = $line.Trim()

        if ($trimmedLine -eq '' -or $trimmedLine.StartsWith('#')) {
            $newContent += $line
            continue
        }

        $parts = $trimmedLine -split '\s+', 2
        if ($parts.Count -eq 2) {
            $domain = $parts[1].Trim()

            if ($ipMap.ContainsKey($domain) -and -not $processedDomains.ContainsKey($domain)) {
                $newContent += "$($ipMap[$domain]) $domain"
                $processedDomains[$domain] = $true
            } else {
                $newContent += $line
                $processedDomains[$domain] = $true
            }
        } else {
            $newContent += $line
        }
    }

    $newDomains = $ipMap.Keys | Where-Object { -not $processedDomains.ContainsKey($_) }
    if ($newDomains) {
        $newContent += ""
        $newContent += "# GitHub Hosts Updated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        foreach ($domain in $newDomains) {
            $newContent += "$($ipMap[$domain]) $domain"
        }
    }

    $newContent | Out-File -FilePath $fullPath -Encoding UTF8
}

function Backup-SystemHosts {
    param([Parameter(Mandatory=$true)][string]$HostsPath)

    $backupDir = Join-Path $ScriptDir 'hosts-backup'

    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupFile = Join-Path $backupDir "hosts_$timestamp"

    try {
        Copy-Item -Path $HostsPath -Destination $backupFile -Force
        return $true
    } catch {
        return $false
    }
}

function Update-SystemHosts {
    param(
        [Parameter(Mandatory=$true)][string]$HostsPath,
        [Parameter(Mandatory=$true)][array]$Results,
        [bool]$AutoBackup = $true
    )

    if (-not (Test-AdminPrivilege)) {
        return $false
    }

    $ipMap = @{}
    foreach ($result in $Results) {
        if (-not $ipMap.ContainsKey($result.Domain)) {
            $ipMap[$result.Domain] = $result.IP
        }
    }

    if ($ipMap.Count -eq 0) { return $true }

    if ($AutoBackup) { Backup-SystemHosts -HostsPath $HostsPath | Out-Null }

    $content = Get-Content -Path $HostsPath -Encoding UTF8
    $newContent = @()
    $existingDomains = @{}

    foreach ($line in $content) {
        $trimmedLine = $line.Trim()

        if ($trimmedLine -eq '' -or $trimmedLine.StartsWith('#')) {
            $newContent += $line
            continue
        }

        $parts = $trimmedLine -split '\s+', 2
        if ($parts.Count -eq 2) {
            $domain = $parts[1].Trim()
            $existingDomains[$domain] = $true

            if ($ipMap.ContainsKey($domain)) {
                $newContent += "$($ipMap[$domain]) $domain"
            } else {
                $newContent += $line
            }
        } else {
            $newContent += $line
        }
    }

    $newDomains = $ipMap.Keys | Where-Object { -not $existingDomains.ContainsKey($_) }
    if ($newDomains) {
        $newContent += ""
        $newContent += "# GitHub Hosts $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        foreach ($domain in $newDomains) {
            $newContent += "$($ipMap[$domain]) $domain"
        }
    }

    try {
        $newContent | Out-File -FilePath $HostsPath -Encoding UTF8
        $Global:Stats.SystemHostsWritten = $true
        return $true
    } catch {
        return $false
    }
}
