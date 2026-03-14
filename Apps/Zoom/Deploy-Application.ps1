<#
.SYNOPSIS
    Install or uninstall Zoom Workplace.
#>
[string]$installPhase = 'Pre-Installation'
Show-InstallationWelcome -CloseApps 'Zoom' -AllowDefer -DeferTimes 3 -CheckDiskSpace -PersistPrompt
Show-InstallationProgress

[string]$installPhase = 'Installation'
$msiPath = Get-ChildItem -Path "$dirFiles" -Include "Zoom*.msi" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
Write-Log -Message "Installing $($msiPath.FullName)" -Severity 1 -Source $deployAppScriptFriendlyName
Execute-MSI -Action Install -Path $msiPath -AddParameters "ALLUSERS=1 /qn ZoomAutoUpdate=1"

[string]$installPhase = 'Post-Installation'
