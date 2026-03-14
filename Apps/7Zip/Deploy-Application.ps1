<#
.SYNOPSIS
    This script performs the installation or uninstallation of 7-Zip.
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
Show-InstallationWelcome -CloseApps 'explorer' -AllowDefer -DeferTimes 3 -CheckDiskSpace -PersistPrompt

## Show Progress Message (with the default message)
Show-InstallationProgress

## <Perform Pre-Installation tasks here>


##*===============================================
##* INSTALLATION
##*===============================================
[string]$installPhase = 'Installation'

## <Perform Installation tasks here>
If ($ENV:PROCESSOR_ARCHITECTURE -eq 'x86'){
    Write-Log -Message "Detected 32-bit OS Architecture" -Severity 1 -Source $deployAppScriptFriendlyName
    $ExePath = Get-ChildItem -Path "$dirFiles" -Include 7z*-x86.msi -File -Recurse -ErrorAction SilentlyContinue
}
Else {
    Write-Log -Message "Detected 64-bit OS Architecture" -Severity 1 -Source $deployAppScriptFriendlyName
    $ExePath = Get-ChildItem -Path "$dirFiles" -Include 7z*-x64.msi -File -Recurse -ErrorAction SilentlyContinue
}

Write-Log -Message "Found $($ExePath.FullName), now attempting to install $installTitle." -Severity 1 -Source $deployAppScriptFriendlyName

# Install application
Execute-MSI -Action Install -Path $ExePath -AddParameters "ALLUSERS=1 /qn"

##*===============================================
##* POST-INSTALLATION
##*===============================================
[string]$installPhase = 'Post-Installation'

## <Perform Post-Installation tasks here>

## Display a message at the end of the install
If (-not $useDefaultMsi) { Show-InstallationPrompt -Message '7-Zip has been installed successfully.' -ButtonRightText 'OK' -Icon Information -NoWait }