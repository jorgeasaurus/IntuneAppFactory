<#
.SYNOPSIS
    Install or uninstall Microsoft Edge.
#>
[string]$installPhase = 'Pre-Installation'
Show-InstallationWelcome -CloseApps 'msedge' -AllowDefer -DeferTimes 3 -CheckDiskSpace -PersistPrompt
Show-InstallationProgress

[string]$installPhase = 'Installation'
$msiPath = Get-ChildItem -Path "$dirFiles" -Include "MicrosoftEdge*.msi" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
Write-Log -Message "Installing $($msiPath.FullName)" -Severity 1 -Source $deployAppScriptFriendlyName
Execute-MSI -Action Install -Path $msiPath -AddParameters "ALLUSERS=1 /qn"

[string]$installPhase = 'Post-Installation'
