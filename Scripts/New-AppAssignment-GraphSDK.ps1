<#
.SYNOPSIS
    This script creates assignment for the published application according to what's defined in the app specific App.json file using Microsoft Graph SDK.

.DESCRIPTION
    This script creates assignment for the published application according to what's defined in the app specific App.json file.
    This version uses Microsoft Graph SDK instead of the deprecated IntuneWin32App module.

.EXAMPLE
    .\New-AppAssignment-GraphSDK.ps1

.NOTES
    FileName:    New-AppAssignment-GraphSDK.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2023-10-08
    Updated:     2025-01-02

    Version history:
    1.0.0 - (2023-10-08) Script created
    2.0.0 - (2025-01-02) Migrated to Microsoft Graph SDK
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantID,

    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ClientID,

    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ClientSecret
)
Process {
    # Import required modules
    Import-Module Microsoft.Graph.Authentication -Force
    Import-Module Microsoft.Graph.DeviceManagement -Force

    # Construct path for AppsAssignList.json file created in previous stage
    $AppsAssignListFileName = "AppsAssignList.json"
    $AppsAssignListFilePath = Join-Path -Path (Join-Path -Path $env:BUILD_ARTIFACTSTAGINGDIRECTORY -ChildPath "AppsPublishedList") -ChildPath $AppsAssignListFileName

    # Connect to Microsoft Graph using client credentials
    Write-Output -InputObject "Connecting to Microsoft Graph"
    $SecureClientSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
    $ClientSecretCredential = [PSCredential]::new($ClientID, $SecureClientSecret)
    Connect-MgGraph -TenantId $TenantID -ClientSecretCredential $ClientSecretCredential -NoWelcome -ErrorAction Stop

    if (Test-Path -Path $AppsAssignListFilePath) {
        # Read content from AppsAssignList.json file and convert from JSON format
        Write-Output -InputObject "Reading contents from: $($AppsAssignListFilePath)"
        $AppsAssignList = Get-Content -Path $AppsAssignListFilePath | ConvertFrom-Json

        # Process each application in list and create assignment according to what's defined in the app specific App.json file
        foreach ($App in $AppsAssignList) {
            Write-Output -InputObject "[APPLICATION: $($App.IntuneAppName)] - Initializing"

            # Read app specific App.json manifest and convert from JSON
            $AppDataFile = Join-Path -Path $App.AppPublishFolderPath -ChildPath "App.json"
            if (Test-Path -Path $AppDataFile) {
                Write-Output -InputObject "Reading contents from: $($AppDataFile)"
                $AppData = Get-Content -Path $AppDataFile | ConvertFrom-Json

                # Detect if current in list has assignment configuration in it's app specific App.json file
                Write-Output -InputObject "Checking for application assignment configuration"
                if ($AppData.Assignment -ne $null) {
                    $AppAssignmentCount = ($AppData.Assignment | Measure-Object).Count
                    Write-Output -InputObject "Found $($AppAssignmentCount) assignment(s) in application manifest"
                    if ($AppAssignmentCount -ge 1) {
                        foreach ($AppAssignmentItem in $AppData.Assignment) {
                            # Prepare assignment body
                            $AssignmentBody = @{
                                "@odata.type" = "#microsoft.graph.mobileAppAssignment"
                                intent = $AppAssignmentItem.Intent.ToLower()
                                settings = @{
                                    "@odata.type" = "#microsoft.graph.win32LobAppAssignmentSettings"
                                    notifications = if ($AppAssignmentItem.Notification) { $AppAssignmentItem.Notification.ToLower() } else { "showAll" }
                                    restartSettings = $null
                                    installTimeSettings = $null
                                    deliveryOptimizationPriority = if ($AppAssignmentItem.DeliveryOptimizationPriority) { $AppAssignmentItem.DeliveryOptimizationPriority.ToLower() } else { "notConfigured" }
                                }
                            }

                            # Add optional settings
                            if ($AppAssignmentItem.EnableRestartGracePeriod -eq $true) {
                                $AssignmentBody.settings.restartSettings = @{
                                    "@odata.type" = "#microsoft.graph.win32LobAppRestartSettings"
                                    gracePeriodInMinutes = if ($AppAssignmentItem.RestartGracePeriodInMinutes) { $AppAssignmentItem.RestartGracePeriodInMinutes } else { 1440 }
                                    countdownDisplayBeforeRestartInMinutes = if ($AppAssignmentItem.RestartCountDownDisplayInMinutes) { $AppAssignmentItem.RestartCountDownDisplayInMinutes } else { 15 }
                                    restartNotificationSnoozeDurationInMinutes = if ($AppAssignmentItem.RestartNotificationSnoozeInMinutes) { $AppAssignmentItem.RestartNotificationSnoozeInMinutes } else { 240 }
                                }
                            }

                            # Add install time settings if available or deadline time is specified
                            if ($AppAssignmentItem.AvailableTime -or $AppAssignmentItem.DeadlineTime) {
                                $AssignmentBody.settings.installTimeSettings = @{
                                    "@odata.type" = "#microsoft.graph.mobileAppInstallTimeSettings"
                                    useLocalTime = if ($AppAssignmentItem.UseLocalTime) { [System.Convert]::ToBoolean($AppAssignmentItem.UseLocalTime) } else { $false }
                                    startDateTime = if ($AppAssignmentItem.AvailableTime) { $AppAssignmentItem.AvailableTime } else { $null }
                                    deadlineDateTime = if ($AppAssignmentItem.DeadlineTime) { $AppAssignmentItem.DeadlineTime } else { $null }
                                }
                            }

                            # Process assignment based on type
                            switch ($AppAssignmentItem.Type) {
                                "VirtualGroup" {
                                    Write-Output -InputObject "Preparing assignment parameters for: '$($AppAssignmentItem.GroupName)'"

                                    # Set target based on virtual group name
                                    switch ($AppAssignmentItem.GroupName) {
                                        "AllDevices" {
                                            $AssignmentBody.target = @{
                                                "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget"
                                            }
                                        }
                                        "AllUsers" {
                                            $AssignmentBody.target = @{
                                                "@odata.type" = "#microsoft.graph.allLicensedUsersAssignmentTarget"
                                            }
                                        }
                                    }

                                    # Add filter if specified
                                    if ($AppAssignmentItem.FilterName -and $AppAssignmentItem.FilterMode) {
                                        # Note: Filter support would require looking up the filter ID by name
                                        Write-Warning -Message "Filter-based assignments require additional implementation to look up filter IDs"
                                    }

                                    try {
                                        # Create application assignment
                                        Write-Output -InputObject "Adding assignment with intent '$($AppAssignmentItem.Intent.ToLower())' for virtual group: '$($AppAssignmentItem.GroupName)'"
                                        $Assignment = New-MgDeviceAppManagementMobileAppAssignment -MobileAppId $App.IntuneAppObjectID -BodyParameter $AssignmentBody -ErrorAction Stop
                                        Write-Output -InputObject "Successfully created assignment with ID: $($Assignment.Id)"
                                    }
                                    catch [System.Exception] {
                                        Write-Warning -Message "An error occurred while attempting to create assignment for virtual group: '$($AppAssignmentItem.GroupName)'. Error message: $($_.Exception.Message)"
                                    }
                                }
                                "Group" {
                                    Write-Output -InputObject "Preparing assignment parameters for group with ID: '$($AppAssignmentItem.GroupID)'"

                                    # Set target based on group mode
                                    switch ($AppAssignmentItem.GroupMode.ToLower()) {
                                        "include" {
                                            $AssignmentBody.target = @{
                                                "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                                                groupId = $AppAssignmentItem.GroupID
                                            }
                                        }
                                        "exclude" {
                                            $AssignmentBody.target = @{
                                                "@odata.type" = "#microsoft.graph.exclusionGroupAssignmentTarget"
                                                groupId = $AppAssignmentItem.GroupID
                                            }
                                        }
                                    }

                                    # Add filter if specified
                                    if ($AppAssignmentItem.FilterName -and $AppAssignmentItem.FilterMode) {
                                        # Note: Filter support would require looking up the filter ID by name
                                        Write-Warning -Message "Filter-based assignments require additional implementation to look up filter IDs"
                                    }

                                    try {
                                        # Create application assignment
                                        Write-Output -InputObject "Adding '$($AppAssignmentItem.GroupMode.ToLower())' assignment with intent '$($AppAssignmentItem.Intent.ToLower())' for group with ID: '$($AppAssignmentItem.GroupID)'"
                                        $Assignment = New-MgDeviceAppManagementMobileAppAssignment -MobileAppId $App.IntuneAppObjectID -BodyParameter $AssignmentBody -ErrorAction Stop
                                        Write-Output -InputObject "Successfully created assignment with ID: $($Assignment.Id)"
                                    }
                                    catch [System.Exception] {
                                        Write-Warning -Message "An error occurred while attempting to create assignment for group with ID: '$($AppAssignmentItem.GroupID)'. Error message: $($_.Exception.Message)"
                                    }
                                }
                            }
                        }
                    }
                    else {
                        Write-Output -InputObject "No eligible assignments found, skipping assignment configuration"
                    }
                }
                else {
                    Write-Output -InputObject "No assignment configuration found, skipping assignment configuration"
                }
            }
            else {
                Write-Output -InputObject "Could not find app specific App.json manifest in: $($App.AppPublishFolderPath)"
            }

            # Handle current application output completed message
            Write-Output -InputObject "[APPLICATION: $($App.IntuneAppName)] - Completed"
        }
    }
    else {
        Write-Output -InputObject "Attempted to read contents from: $($AppsAssignListFilePath)"
        Write-Output -InputObject "No application assignment list found, skipping assignment configuration"
    }

    # Disconnect from Graph
    Disconnect-MgGraph
}