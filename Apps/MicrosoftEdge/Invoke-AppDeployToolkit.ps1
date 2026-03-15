<#
.SYNOPSIS
    PSAppDeployToolkit - This script performs the installation or uninstallation of an application(s).
.DESCRIPTION
    - The script is provided as a template to perform an install, uninstall, or repair of an application(s).
    - The script either performs an "Install", "Uninstall", or "Repair" deployment type.
    - The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.

    The script imports the PSAppDeployToolkit module which contains the logic and functions required to install or uninstall an application.
.PARAMETER DeploymentType
    The type of deployment to perform.
.PARAMETER DeployMode
    Specifies whether the installation should be run in Interactive, Silent, NonInteractive, or Auto mode.
.INPUTS
    None.
.OUTPUTS
    None.
.LINK
    https://psappdeploytoolkit.com
#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [System.String]$DeploymentType,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Auto', 'Interactive', 'NonInteractive', 'Silent')]
    [System.String]$DeployMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$SuppressRebootPassThru,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$TerminalServerMode,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter]$DisableLogging
)

##================================================
## MARK: Variables
##================================================

$adtSession = @{
    AppVendor = 'Microsoft'
    AppName = 'Microsoft Edge'
    AppVersion = ''
    AppArch = 'x64'
    AppLang = 'EN'
    AppRevision = '01'
    AppSuccessExitCodes = @(0)
    AppRebootExitCodes = @(1641, 3010)
    AppProcessesToClose = @(@{ Name = 'msedge'; Description = 'Microsoft Edge' })
    AppScriptVersion = '1.0.0'
    AppScriptDate = '2025-07-08'
    AppScriptAuthor = 'IntuneAppFactory'
    RequireAdmin = $true
    InstallName = ''
    InstallTitle = ''
    DeployAppScriptFriendlyName = $MyInvocation.MyCommand.Name
    DeployAppScriptParameters = $PSBoundParameters
    DeployAppScriptVersion = '4.1.8'
}

function Install-ADTDeployment
{
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"
    Show-ADTInstallationWelcome -CloseProcesses $adtSession.AppProcessesToClose -AllowDeferCloseProcesses -DeferTimes 3 -PersistPrompt

    $adtSession.InstallPhase = $adtSession.DeploymentType
    Show-ADTInstallationProgress
    $msiFile = Get-ChildItem -Path $adtSession.DirFiles -Filter 'MicrosoftEdge*.msi' | Select-Object -First 1
    Start-ADTMsiProcess -Action Install -FilePath $msiFile.Name -ArgumentList 'ALLUSERS=1'

    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"
}

function Uninstall-ADTDeployment
{
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    $adtSession.InstallPhase = $adtSession.DeploymentType
    Uninstall-ADTApplication -Name 'Microsoft Edge'

    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"
}

function Repair-ADTDeployment
{
    $adtSession.InstallPhase = "Pre-$($adtSession.DeploymentType)"

    $adtSession.InstallPhase = $adtSession.DeploymentType

    $adtSession.InstallPhase = "Post-$($adtSession.DeploymentType)"
}

##================================================
## MARK: Initialization
##================================================

$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
$ProgressPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
Set-StrictMode -Version 1

try
{
    if (Test-Path -LiteralPath "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1" -PathType Leaf)
    {
        Get-ChildItem -LiteralPath "$PSScriptRoot\PSAppDeployToolkit" -Recurse -File | Unblock-File -ErrorAction Ignore
        Import-Module -FullyQualifiedName @{ ModuleName = "$PSScriptRoot\PSAppDeployToolkit\PSAppDeployToolkit.psd1"; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }
    else
    {
        Import-Module -FullyQualifiedName @{ ModuleName = 'PSAppDeployToolkit'; Guid = '8c3c366b-8606-4576-9f2d-4051144f7ca2'; ModuleVersion = '4.1.8' } -Force
    }

    $iadtParams = Get-ADTBoundParametersAndDefaultValues -Invocation $MyInvocation
    $adtSession = Remove-ADTHashtableNullOrEmptyValues -Hashtable $adtSession
    $adtSession = Open-ADTSession @adtSession @iadtParams -PassThru
}
catch
{
    $Host.UI.WriteErrorLine((Out-String -InputObject $_ -Width ([System.Int32]::MaxValue)))
    exit 60008
}

##================================================
## MARK: Invocation
##================================================

try
{
    Get-ChildItem -LiteralPath $PSScriptRoot -Directory | & {
        process
        {
            if ($_.Name -match 'PSAppDeployToolkit\..+$')
            {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -File | Unblock-File -ErrorAction Ignore
                Import-Module -Name $_.FullName -Force
            }
        }
    }

    & "$($adtSession.DeploymentType)-ADTDeployment"
    Close-ADTSession
}
catch
{
    $mainErrorMessage = "An unhandled error within [$($MyInvocation.MyCommand.Name)] has occurred.`n$(Resolve-ADTErrorRecord -ErrorRecord $_)"
    Write-ADTLogEntry -Message $mainErrorMessage -Severity 3
    Show-ADTInstallationPrompt -Message "$($adtSession.DeploymentType) failed at line $($_.InvocationInfo.ScriptLineNumber):`n$($_.Exception.Message)" -MessageAlignment Left -ButtonRightText OK -Icon Error -NoWait
    Close-ADTSession -ExitCode 60001
}
