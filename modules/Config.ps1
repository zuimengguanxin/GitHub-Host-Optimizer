<#
.SYNOPSIS
    Config module
#>

function Get-Config {
    param([string]$ConfigPath = 'config.json')

    $configPath = if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
        $ConfigPath
    } else {
        Join-Path $ScriptDir $ConfigPath
    }

    $defaultConfig = @{
        mainHostFile = 'my-github-hosts.txt'
        systemHostsPath = 'C:\Windows\System32\drivers\etc\hosts'
        backupPoolFile = 'backup-pool.json'
        remoteHostSources = @()
        testTimeoutMs = 1000
        retryCount = 1
        remoteSourceRetryCount = 2
        apiRetryCount = 3
        autoBackup = $true
    }

    if (-not (Test-Path $configPath)) {
        $defaultConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $configPath -Encoding UTF8
        Write-Host ""
        Write-Host "  [!] Config created: $configPath" -ForegroundColor Yellow
        Write-Host "  [i] Please add remoteHostSources to config.json" -ForegroundColor Gray
        Write-Host ""
    }

    try {
        $jsonContent = Get-Content -Path $configPath -Raw -Encoding UTF8
        $config = $jsonContent | ConvertFrom-Json

        foreach ($key in $defaultConfig.Keys) {
            if (-not $config.PSObject.Properties.Match($key)) {
                $config | Add-Member -MemberType NoteProperty -Name $key -Value $defaultConfig[$key]
            }
        }

        return $config
    } catch {
        return $defaultConfig
    }
}
