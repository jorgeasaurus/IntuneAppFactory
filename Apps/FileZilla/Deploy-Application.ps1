<#
.SYNOPSIS
    Install or uninstall FileZilla.
#>
[string]$installPhase = 'Pre-Installation'
Show-InstallationWelcome -CloseApps 'filezilla' -AllowDefer -DeferTimes 3 -CheckDiskSpace -PersistPrompt
Show-InstallationProgress

[string]$installPhase = 'Installation'
$installer = Get-ChildItem -Path "$dirFiles" -Include "FileZilla_*_win64-setup.exe" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
Write-Log -Message "Installing $($installer.FullName)" -Severity 1 -Source $deployAppScriptFriendlyName
Execute-Process -Path $installer.FullName -Parameters "/S" -WaitForMsiExec

[string]$installPhase = 'Post-Installation'
