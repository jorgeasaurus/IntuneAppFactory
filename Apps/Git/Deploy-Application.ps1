<#
.SYNOPSIS
    Install or uninstall Git for Windows.
#>
[string]$installPhase = 'Pre-Installation'
Show-InstallationWelcome -CloseApps 'git,git-bash' -AllowDefer -DeferTimes 3 -CheckDiskSpace -PersistPrompt
Show-InstallationProgress

[string]$installPhase = 'Installation'
$installer = Get-ChildItem -Path "$dirFiles" -Include "Git-*-64-bit.exe" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
Write-Log -Message "Installing $($installer.FullName)" -Severity 1 -Source $deployAppScriptFriendlyName
Execute-Process -Path $installer.FullName -Parameters "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS=ext,ext\shellhere,ext\guihere,gitlfs,assoc,assoc_sh" -WaitForMsiExec

[string]$installPhase = 'Post-Installation'
