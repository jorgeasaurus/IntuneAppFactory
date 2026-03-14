<#
.SYNOPSIS
    This script performs the installation or uninstallation of VLC Media Player.
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
Show-InstallationWelcome -CloseApps 'vlc' -AllowDefer -DeferTimes 3 -CheckDiskSpace -PersistPrompt

## Show Progress Message (with the default message)
Show-InstallationProgress

## <Perform Pre-Installation tasks here>


##*===============================================
##* INSTALLATION
##*===============================================
[string]$installPhase = 'Installation'

## <Perform Installation tasks here>
$ExePath = Get-ChildItem -Path "$dirFiles" -Include vlc-*-win64.msi -File -Recurse -ErrorAction SilentlyContinue

Write-Log -Message "Found $($ExePath.FullName), now attempting to install $installTitle." -Severity 1 -Source $deployAppScriptFriendlyName

# Install application
Execute-MSI -Action Install -Path $ExePath -AddParameters "ALLUSERS=1 /qn"

##*===============================================
##* POST-INSTALLATION
##*===============================================
[string]$installPhase = 'Post-Installation'

## <Perform Post-Installation tasks here>

## Display a message at the end of the install
If (-not $useDefaultMsi) { Show-InstallationPrompt -Message 'VLC Media Player has been installed successfully.' -ButtonRightText 'OK' -Icon Information -NoWait }