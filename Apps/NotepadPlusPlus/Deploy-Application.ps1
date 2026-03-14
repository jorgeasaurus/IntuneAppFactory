<#
.SYNOPSIS
    This script performs the installation or uninstallation of Notepad++.
.DESCRIPTION
    The script is provided as a template to perform an install or uninstall of an application(s).
.NOTES
    File Name  : Deploy-Application.ps1
#>

##*===============================================
##* PRE-INSTALLATION
##*===============================================
[string]$installPhase = 'Pre-Installation'

## Show Welcome Message, close Internet Explorer if required, allow up to 3 deferrals, verify there is enough disk space to complete the install, and persist the prompt
Show-InstallationWelcome -CloseApps 'notepad++' -AllowDefer -DeferTimes 3 -CheckDiskSpace -PersistPrompt

## Show Progress Message (with the default message)
Show-InstallationProgress

## <Perform Pre-Installation tasks here>


##*===============================================
##* INSTALLATION
##*===============================================
[string]$installPhase = 'Installation'

## <Perform Installation tasks here>
$ExePath = Get-ChildItem -Path "$dirFiles" -Include npp.*.exe -File -Recurse -ErrorAction SilentlyContinue

Write-Log -Message "Found $($ExePath.FullName), now attempting to install $installTitle." -Severity 1 -Source $deployAppScriptFriendlyName

# Install application
Execute-Process -Path $ExePath -Parameters '/S' -WindowStyle Hidden

##*===============================================
##* POST-INSTALLATION
##*===============================================
[string]$installPhase = 'Post-Installation'

## <Perform Post-Installation tasks here>

## Display a message at the end of the install
If (-not $useDefaultMsi) { Show-InstallationPrompt -Message 'Notepad++ has been installed successfully.' -ButtonRightText 'OK' -Icon Information -NoWait }