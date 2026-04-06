<#
.SYNOPSIS
    Admin module
#>

function Test-AdminPrivilege {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdminPrivilege {
    param([string]$ScriptPath)

    try {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        Start-Process powershell -ArgumentList $arguments -Verb RunAs -Wait
        return $true
    } catch {
        return $false
    }
}
