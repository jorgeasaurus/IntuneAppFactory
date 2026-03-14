<#
.SYNOPSIS
    Install or uninstall Visual Studio Code.
#>
[string]$installPhase = 'Pre-Installation'
Show-InstallationWelcome -CloseApps 'Code' -AllowDefer -DeferTimes 3 -CheckDiskSpace -PersistPrompt
Show-InstallationProgress

[string]$installPhase = 'Installation'
$installer = Get-ChildItem -Path "$dirFiles" -Include "VSCode*.exe" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
Write-Log -Message "Installing $($installer.FullName)" -Severity 1 -Source $deployAppScriptFriendlyName
Execute-Process -Path $installer.FullName -Parameters "/VERYSILENT /NORESTART /MERGETASKS=!runcode,addcontextmenufiles,addcontextmenufolders,addtopath" -WaitForMsiExec

[string]$installPhase = 'Post-Installation'
