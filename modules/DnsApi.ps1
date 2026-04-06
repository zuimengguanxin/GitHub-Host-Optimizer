<#
.SYNOPSIS
    DNS API module
#>

function Get-IPFromTutorialspoint {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Domain
    )

    try {
        $url = "https://tools.tutorialspoint.com/ip_lookup_ajax.php?host=" + $Domain
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
        $content = $response.Content

        if ($content -match "IP address of .+? is (\d+\.\d+\.\d+\.\d+)") {
            return @($matches[1])
        }
    } catch {}

    return @()
}

function Get-IPsFromMultipleSources {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Domain
    )

    $allIPs = @()

    $tutorialspointResult = Get-IPFromTutorialspoint -Domain $Domain
    $allIPs += $tutorialspointResult

    return @($allIPs | Select-Object -Unique)
}
