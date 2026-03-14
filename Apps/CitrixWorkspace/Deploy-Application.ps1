<#
.SYNOPSIS
    Install or uninstall Citrix Workspace.
#>
[string]$installPhase = 'Pre-Installation'
Show-InstallationWelcome -CloseApps 'wfica32,Receiver,SelfService' -AllowDefer -DeferTimes 3 -CheckDiskSpace -PersistPrompt
Show-InstallationProgress

[string]$installPhase = 'Installation'
$installer = Get-ChildItem -Path "$dirFiles" -Include "CitrixWorkspaceApp*.exe" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
Write-Log -Message "Installing $($installer.FullName)" -Severity 1 -Source $deployAppScriptFriendlyName
Execute-Process -Path $installer.FullName -Parameters "/silent /noreboot /AutoUpdateCheck=disabled" -WaitForMsiExec

[string]$installPhase = 'Post-Installation'
