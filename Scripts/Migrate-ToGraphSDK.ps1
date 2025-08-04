#Requires -Version 5.1

<#
.SYNOPSIS
    Migration guide and helper functions for moving from MSIntuneGraph to Microsoft Graph SDK
.DESCRIPTION
    This script provides mapping between old IntuneWin32App module commands and the new Microsoft Graph SDK
.NOTES
    The IntuneWin32App module uses the older authentication methods. This guide helps migrate to the modern Graph SDK.
#>

# Authentication Migration
Write-Host "=== Authentication Migration ===" -ForegroundColor Cyan

Write-Host @"
OLD METHOD (IntuneWin32App/MSAL.PS):
`$authParams = @{
    TenantId = `$TenantId
    ClientId = `$ClientId
    ClientSecret = (`$ClientSecret | ConvertTo-SecureString -AsPlainText -Force)
}
`$tokenResponse = Get-MsalToken @authParams -Scopes "https://graph.microsoft.com/.default"
Connect-MSIntuneGraph -TenantID `$TenantId -ClientID `$ClientId -ClientSecret `$ClientSecret

NEW METHOD (Microsoft Graph SDK):
`$secureSecret = ConvertTo-SecureString -String `$ClientSecret -AsPlainText -Force
`$credential = [PSCredential]::new(`$ClientId, `$secureSecret)
Connect-MgGraph -TenantId `$TenantId -ClientSecretCredential `$credential -NoWelcome
"@ -ForegroundColor Yellow

# Common Command Mappings
Write-Host "`n=== Common Command Mappings ===" -ForegroundColor Cyan

$commandMappings = @{
    "Get-IntuneWin32App" = "Get-MgDeviceAppManagementMobileApp -Filter `"isof('microsoft.graph.win32LobApp')`""
    "Add-IntuneWin32App" = "New-MgDeviceAppManagementMobileApp -BodyParameter `$win32AppObject"
    "Remove-IntuneWin32App" = "Remove-MgDeviceAppManagementMobileApp -MobileAppId `$appId"
    "Get-IntuneWin32AppAssignment" = "Get-MgDeviceAppManagementMobileAppAssignment -MobileAppId `$appId"
    "Add-IntuneWin32AppAssignmentGroup" = "New-MgDeviceAppManagementMobileAppAssignment -MobileAppId `$appId -BodyParameter `$assignment"
}

foreach ($old in $commandMappings.Keys) {
    Write-Host "`nOLD: $old" -ForegroundColor Red
    Write-Host "NEW: $($commandMappings[$old])" -ForegroundColor Green
}

# Helper Functions
Write-Host "`n=== Helper Functions ===" -ForegroundColor Cyan

function Convert-IntuneWin32AppToGraphObject {
    <#
    .SYNOPSIS
        Converts IntuneWin32App parameters to Graph API object format
    #>
    param(
        [hashtable]$AppParameters
    )
    
    $graphApp = @{
        "@odata.type" = "#microsoft.graph.win32LobApp"
        displayName = $AppParameters.DisplayName
        description = $AppParameters.Description
        publisher = $AppParameters.Publisher
        largeIcon = $null
        isFeatured = $false
        installCommandLine = $AppParameters.InstallCommandLine
        uninstallCommandLine = $AppParameters.UninstallCommandLine
        applicableArchitectures = $AppParameters.Architecture
        minimumSupportedWindowsRelease = $AppParameters.MinimumSupportedWindowsRelease
        fileName = $AppParameters.FileName
        installExperience = @{
            runAsAccount = $AppParameters.InstallExperience
            deviceRestartBehavior = $AppParameters.RestartBehavior
        }
    }
    
    return $graphApp
}

function Get-Win32AppsFromGraph {
    <#
    .SYNOPSIS
        Gets all Win32 apps from Intune using Graph SDK
    #>
    [CmdletBinding()]
    param()
    
    # Get all mobile apps and filter for Win32 apps
    $allApps = Get-MgDeviceAppManagementMobileApp -All
    $win32Apps = $allApps | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.win32LobApp' }
    
    return $win32Apps
}

function New-GraphWin32AppAssignment {
    <#
    .SYNOPSIS
        Creates a new app assignment using Graph SDK
    #>
    param(
        [string]$AppId,
        [string]$GroupId,
        [string]$Intent = "available",
        [string]$Notification = "showAll"
    )
    
    $assignment = @{
        "@odata.type" = "#microsoft.graph.mobileAppAssignment"
        intent = $Intent
        target = @{
            "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
            groupId = $GroupId
        }
        settings = @{
            "@odata.type" = "#microsoft.graph.win32LobAppAssignmentSettings"
            notifications = $Notification
            restartSettings = $null
            installTimeSettings = $null
            deliveryOptimizationPriority = "notConfigured"
        }
    }
    
    New-MgDeviceAppManagementMobileAppAssignment -MobileAppId $AppId -BodyParameter $assignment
}

# Example Usage
Write-Host "`n=== Example Usage ===" -ForegroundColor Cyan
Write-Host @'
# 1. Connect to Graph
$secureSecret = ConvertTo-SecureString -String $env:CLIENT_SECRET -AsPlainText -Force
$credential = [PSCredential]::new($env:CLIENT_ID, $secureSecret)
Connect-MgGraph -TenantId $env:TENANT_ID -ClientSecretCredential $credential -NoWelcome

# 2. Get Win32 Apps
$win32Apps = Get-Win32AppsFromGraph
$win32Apps | Select-Object DisplayName, Id, '@odata.type' | Format-Table

# 3. Create a new assignment
$appId = "12345678-1234-1234-1234-123456789012"
$groupId = "87654321-4321-4321-4321-210987654321"
New-GraphWin32AppAssignment -AppId $appId -GroupId $groupId -Intent "required"

# 4. Disconnect
Disconnect-MgGraph
'@ -ForegroundColor Gray

Write-Host "`n=== Important Notes ===" -ForegroundColor Cyan
Write-Host @"
1. The Microsoft Graph SDK uses different object structures than IntuneWin32App module
2. File upload for .intunewin packages requires additional API calls not covered by the SDK
3. Some features may require using Invoke-MgGraphRequest for direct API calls
4. Always use -All parameter when retrieving lists to get all items (default is 100)
5. Use -Filter parameter for efficient querying instead of client-side filtering
"@ -ForegroundColor Yellow