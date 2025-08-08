<#
.SYNOPSIS
    This script processes each onboarded application in the appList.json file to determine if the app doesn't exist or if a newer version should be published.

.DESCRIPTION
    This script processes each onboarded application in the appList.json file to determine if the app doesn't exist or if a newer version should be published.

.EXAMPLE
    .\Test-AppList.ps1

.NOTES
    FileName:    Test-AppList.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2022-03-29
    Updated:     2024-08-25

    Version history:
    1.0.0 - (2022-03-29) Script created
    1.0.1 - (2022-10-26) Added support for Azure Storage Account source
    1.0.2 - (2023-06-14) Added more data to the app list item required for downloading setup files in the next phase
    1.0.3 - (2024-03-04) Added more Evergreen filter options, improved storage account blob content retrieval using Az module, added more error handling and logging
    1.0.4 - (2024-03-07) Added support for empty filter options in Get-EvergreenAppItem function
    1.0.5 - (2024-08-25) Added function to test and convert version strings with invalid characters to improve version comparison for detected applications in Intune.
                         Improved application detection logic using the new naming convention property specified in the appList.json file.
    1.0.6 - (2024-09-03) Removed Azure Storage Account support and added GitHub Release and DirectUrl sources
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
    # Functions
    function ConvertTo-Version {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$Version
        )
        Process {
            # Split the version string by non-numerical characters and then join them by a period to construct the version number
            $ConvertVersion = ($Version -split "\D") -join "."

            # Return the converted version number
            return $ConvertVersion
        }
    }

    function Test-Version {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$Version
        )
        Process {
            # Attempt to parse the version string
            try {
                $null = [System.Version]::Parse($Version)
                $Result = $true
            }
            catch {
                $Result = $false
            }
    
            # Return the result of the parsing attempt
            return $Result
        }
    }

    function Get-EvergreenAppItem {
        param (
            [parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$AppId,
    
            [parameter(Mandatory = $false)]
            [ValidateNotNullOrEmpty()]
            [System.Object[]]$FilterOptions
        )
        if ($PSBoundParameters["FilterOptions"]) {
            # Construct array list to build the dynamic filter list
            $FilterList = New-Object -TypeName "System.Collections.ArrayList"
                
            # Process known filter properties and add them to array list if present on current object
            if ($FilterOptions.Architecture) {
                $FilterList.Add("`$PSItem.Architecture -eq ""$($FilterOptions.Architecture)""") | Out-Null
            }
            if ($FilterOptions.Platform) {
                $FilterList.Add("`$PSItem.Platform -eq ""$($FilterOptions.Platform)""") | Out-Null
            }
            if ($FilterOptions.Channel) {
                $FilterList.Add("`$PSItem.Channel -eq ""$($FilterOptions.Channel)""") | Out-Null
            }
            if ($FilterOptions.Type) {
                $FilterList.Add("`$PSItem.Type -eq ""$($FilterOptions.Type)""") | Out-Null
            }
            if ($FilterOptions.InstallerType) {
                $FilterList.Add("`$PSItem.InstallerType -eq ""$($FilterOptions.InstallerType)""") | Out-Null
            }
            if ($FilterOptions.Language) {
                $FilterList.Add("`$PSItem.Language -eq ""$($FilterOptions.Language)""") | Out-Null
            }
            if ($FilterOptions.Edition) {
                $FilterList.Add("`$PSItem.Edition -eq ""$($FilterOptions.Edition )""") | Out-Null
            }
            if ($FilterOptions.Ring) {
                $FilterList.Add("`$PSItem.Ring -eq ""$($FilterOptions.Ring)""") | Out-Null
            }
            if ($FilterOptions.Release) {
                $FilterList.Add("`$PSItem.Release -eq ""$($FilterOptions.Release)""") | Out-Null
            }
            if ($FilterOptions.ImageType) {
                $FilterList.Add("`$PSItem.Release -eq ""$($FilterOptions.Release)""") | Out-Null
            }

            # Construct script block from filter list array
            $FilterExpression = [scriptblock]::Create(($FilterList -join " -and "))

            # Get the evergreen app based on dynamic filter list
            $EvergreenApp = Get-EvergreenApp -Name $AppId | Where-Object -FilterScript $FilterExpression
        }
        else {
            $EvergreenApp = Get-EvergreenApp -Name $AppId
        }
        
        # Handle return value
        return $EvergreenApp
    }

    function Get-WindowsPackageManagerItem {
        param (
            [parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$AppId
        )
        process {
            # Initialize variables
            $AppResult = $true
        
            # Test if provided id exists in the winget repo
            [string[]]$WinGetArguments = @("search", "$($AppId)")
            [string[]]$WinGetStream = & "winget" $WinGetArguments | Out-String -Stream
            foreach ($RowItem in $WinGetStream) {
                if ($RowItem -eq "No package found matching input criteria.") {
                    $AppResult = $false
                }
            }
        
            if ($AppResult -eq $true) {
                # Show winget package details for provided id and capture output
                [string[]]$WinGetArguments = @("show", "$($AppId)")
                [string[]]$WinGetStream = & "winget" $WinGetArguments | Out-String -Stream
        
                # Construct custom object for return value
                $PSObject = [PSCustomObject]@{
                    "Id" = $AppId
                    "Version" = ($WinGetStream | Where-Object { $PSItem -match "^Version\:.*(?<AppVersion>(\d+(\.\d+){0,3}))$" }).Replace("Version:", "").Trim()
                    "URI" = (($WinGetStream | Where-Object { $PSItem -match "^.*(Download|Installer) Url\:.*$" }) -replace "(Download|Installer) Url:", "").Trim()
                }
        
                # Handle return value
                return $PSObject
            }
            else {
                Write-Warning -Message "No package found matching specified id: $($AppId)"
            }
        }
    }


    # Intitialize variables
    $AppsDownloadListFileName = "AppsDownloadList.json"
    $AppsDownloadListFilePath = Join-Path -Path $env:BUILD_BINARIESDIRECTORY -ChildPath $AppsDownloadListFileName
    $SourceDirectory = $env:BUILD_SOURCESDIRECTORY

    try {
        # Retrieve authentication token using client secret from key vault
        $AuthToken = Get-AccessToken -TenantID $TenantID -ClientID $ClientID -ClientSecret $ClientSecret -ErrorAction "Stop"

        # Construct list of applications to be processed in the next stage
        $AppsDownloadList = New-Object -TypeName "System.Collections.ArrayList"

        # Read content from AppsProcessList.json file created in previous stage
        $AppsProcessListFileName = "AppsProcessList.json"
        $AppsProcessListFilePath = Join-Path -Path (Join-Path -Path $env:BUILD_ARTIFACTSTAGINGDIRECTORY -ChildPath "AppsProcessList") -ChildPath $AppsProcessListFileName

        # Foreach application in appList.json, check existence in Intunem and determine if new application / version should be published
        $AppsProcessList = Get-Content -Path $AppsProcessListFilePath -ErrorAction "Stop" | ConvertFrom-Json
        foreach ($App in $AppsProcessList) {
            Write-Output -InputObject "[APPLICATION: $($App.IntuneAppName)] - Initializing"

            # Read app specific App.json manifest and convert from JSON
            $AppPackageFolderPath = Join-Path -Path $SourceDirectory -ChildPath "Apps\$($App.AppFolderName)"
            $AppDataFile = Join-Path -Path $AppPackageFolderPath -ChildPath "App.json"
            $AppData = Get-Content -Path $AppDataFile | ConvertFrom-Json

            # Set application publish value to false, will change to true if determined in logic below that an application should be published
            $AppDownload = $false

            try {
                # Get app details based on app source
                switch ($App.AppSource) {
                    "Winget" {
                        Write-Output -InputObject "Attempting to retrieve app details from Windows Package Manager"
                        Write-Output -InputObject "AppId value: $($App.AppId)"
                        $AppItem = Get-WindowsPackageManagerItem -AppId $App.AppId
                    }
                    "Evergreen" {
                        Write-Output -InputObject "Attempting to retrieve app details from Evergreen"
                        if ($App.FilterOptions -ne $null) {
                            Write-Output -InputObject "AppId value: $($App.AppId)"
                            Write-Output -InputObject "Filter options: $($App.FilterOptions)"
                            $AppItem = Get-EvergreenAppItem -AppId $App.AppId -FilterOptions $App.FilterOptions
                        }
                        else {
                            Write-Output -InputObject "AppId value: $($App.AppId)"
                            $AppItem = Get-EvergreenAppItem -AppId $App.AppId
                        }
                    }
                    "GitHubRelease" {
                        Write-Output -InputObject "Attempting to retrieve app details from GitHub Release"
                        $DownloadUrl = "https://github.com/$($App.GitHubRepo)/releases/download/$($App.ReleaseTag)/$($App.SetupFile)"
                        $FileExt = [System.IO.Path]::GetExtension($App.SetupFile).TrimStart('.')
                        $AppItem = [PSCustomObject]@{
                            Version = $App.ReleaseTag
                            URI = $DownloadUrl
                            InstallerType = $FileExt
                            FileExtension = $FileExt
                        }
                    }
                    "DirectUrl" {
                        Write-Output -InputObject "Using direct download URL"
                        $FileExt = [System.IO.Path]::GetExtension($App.DownloadUrl).TrimStart('.')
                        $AppItem = [PSCustomObject]@{
                            Version = $App.Version
                            URI = $App.DownloadUrl
                            InstallerType = $FileExt
                            FileExtension = $FileExt
                        }
                    }
                }

                # Continue if app details could be retrieved from current app source
                if ($AppItem -ne $null) {
                    Write-Output -InputObject "Found app details based on '$($App.AppSource)' query:"
                    Write-Output -InputObject "Version: $($AppItem.Version)"
                    Write-Output -InputObject "URI: $($AppItem.URI)"

                    try {
                        # Attempt to deserialize the setup file name from the URI
                        $AppSetupFileName = [Uri]$AppItem.URI | Select-Object -ExpandProperty "Segments" | Select-Object -Last 1
                        Write-Output -InputObject "Setup file name: $($AppSetupFileName)"

                        try {
                            # Determine the display name based on the naming convention, to ensure the correct application is detected
                            switch ($App.IntuneAppNamingConvention) {
                                "PublisherAppNameAppVersion" {
                                    $AppDisplayName = -join@($App.AppPublisher, " ", $App.IntuneAppName, " ", $AppItem.Version)
                                }
                                "PublisherAppName" {
                                    $AppDisplayName = -join@($App.AppPublisher, " ", $App.IntuneAppName)
                                }
                                "AppNameAppVersion" {
                                    $AppDisplayName = -join@($App.IntuneAppName, " ", $AppItem.Version)
                                }
                                "AppName" {
                                    $AppDisplayName = $App.IntuneAppName
                                }
                                default {
                                    $AppDisplayName = $App.IntuneAppName
                                }
                            }
                            
                            # Attempt to locate the application in Intune
                            Write-Output -InputObject "Attempting to find application in Intune using naming convention: $($AppDisplayName)"
                            $Win32AppResources = Invoke-MSGraphOperation -Get -APIVersion "Beta" -Resource "deviceAppManagement/mobileApps?`$filter=isof('microsoft.graph.win32LobApp')"
                            if ($Win32AppResources -ne $null) {

                                # Detect Win32 application matching displayName
                                $Win32Apps = $Win32AppResources | Where-Object { $PSItem.displayName -like "$($AppDisplayName)*" }
                                if ($Win32Apps -ne $null) {
                                    $Win32AppsCount = ($Win32Apps | Measure-Object).Count
                                    Write-Output -InputObject "Count of detected Intune Win32 applications: $($Win32AppsCount)"
                                }
                                else {
                                    Write-Output -InputObject "Application with defined name '$($AppDisplayName)' was not found, adding to download list"
    
                                    # Mark new application to be published
                                    $AppDownload = $true
                                }
    
                                # Filter for the latest version published in Intune, if multiple applications objects was detected
                                $Win32AppLatestPublishedVersion = $Win32Apps.displayVersion | Where-Object { $PSItem -as [System.Version] } | Sort-Object { [System.Version]$PSItem } -Descending | Select-Object -First 1
    
                                # Version validation and conversion if necessary
                                if (Test-Version -Version $AppItem.Version) {
                                    Write-Output -InputObject "Version string is valid"
                                }
                                else {
                                    Write-Output -InputObject "Version string contains invalid characters, attempting to convert"
                                    $AppItem.Version = ConvertTo-Version -Version $AppItem.Version
                                    Write-Output -InputObject "Converted version string: $($AppItem.Version)"
                                }

                                # Perform version comparison check
                                Write-Output -InputObject "Performing version comparison check to determine if a newer version of the application exists"
                                if ([System.Version]$AppItem.Version -gt [System.Version]$Win32AppLatestPublishedVersion) {
                                    # Determine value for published version if not found
                                    if ($Win32AppLatestPublishedVersion -eq $null) {
                                        $Win32AppLatestPublishedVersion = "Not found"
                                    }

                                    Write-Output -InputObject "Newer version exists for application, version details:"
                                    Write-Output -InputObject "Latest version: $($AppItem.Version)"
                                    Write-Output -InputObject "Published version: $($Win32AppLatestPublishedVersion)"
                                    Write-Output -InputObject "Adding application to download list"
                                    
                                    # Mark new application version to be published
                                    $AppDownload = $true
                                }
                                else {
                                    Write-Output -InputObject "Latest version of application is already published"
                                }
                            }
                            else {
                                Write-Warning -Message "Unhandled error occurred, application will be skipped"
    
                                # Handle current application output completed message
                                Write-Output -InputObject "[APPLICATION: $($App.IntuneAppName)] - Skipped"
                            }
    
                            # Add current app to list if publishing is required
                            if ($AppDownload -eq $true) {
                                # Construct new application custom object with required properties
                                $AppListItem = [PSCustomObject]@{
                                    "IntuneAppName" = $App.IntuneAppName
                                    "IntuneAppNamingConvention" = $App.IntuneAppNamingConvention
                                    "AppPublisher" = $App.AppPublisher
                                    "AppSource" = $App.AppSource
                                    "AppId" = $App.AppId
                                    "AppFolderName" = $App.AppFolderName
                                    "AppSetupFileName" = $AppSetupFileName
                                    "AppSetupVersion" = $AppItem.Version
                                    "URI" = $AppItem.URI
                                    "InstallerType" = $AppItem.InstallerType
                                    "FileExtension" = $AppItem.FileExtension
                                    "IconURL" = $App.IconURL
                                }
    
                                # Add to list of applications to be published
                                $AppsDownloadList.Add($AppListItem) | Out-Null
    
                                # Handle current application output completed message
                                Write-Output -InputObject "[APPLICATION: $($App.IntuneAppName)] - Completed"
                            }
                        }
                        catch [System.Exception] {
                            Write-Warning -Message "Failed to retrieve Win32 app object from Intune for app: $($App.IntuneAppName)"
    
                            # Handle current application output completed message
                            Write-Output -InputObject "[APPLICATION: $($App.IntuneAppName)] - Skipped"
                        }
                    }
                    catch [System.Exception] {
                        Write-Warning -Message "Failed to deserialize setup file name from URI: $($AppItem.URI)"
                    }
                }
                else {
                    Write-Warning -Message "App details could not be found from app source: $($App.AppSource)"

                    # Handle current application output completed message
                    Write-Output -InputObject "[APPLICATION: $($App.IntuneAppName)] - Skipped"
                }
            }
            catch [System.Exception] {
                Write-Warning -Message "Failed to retrieve app source details using method '$($App.AppSource)' for app: $($App.IntuneAppName). Error message: $($_.Exception.Message)"

                # Handle current application output completed message
                Write-Output -InputObject "[APPLICATION: $($App.IntuneAppName)] - Skipped"
            }
        }

        # Construct new json file with new applications to be published
        if ($AppsDownloadList.Count -ge 1) {
            $AppsDownloadListJSON = $AppsDownloadList | ConvertTo-Json -Depth 3
            Write-Output -InputObject "Creating '$($AppsDownloadListFileName)' in: $($AppsDownloadListFilePath)"
            Write-Output -InputObject "App list file contains the following items: $($AppsDownloadList.IntuneAppName -join ", ")"
            Out-File -InputObject $AppsDownloadListJSON -FilePath $AppsDownloadListFilePath -NoClobber -Force
        }

        # Handle next stage execution or not if no new applications are to be published
        if ($AppsDownloadList.Count -eq 0) {
            # Don't allow pipeline to continue
            Write-Output -InputObject "No new applications to be published, aborting pipeline"
        }
    }
    catch [System.Exception] {
        throw "$($MyInvocation.MyCommand): Failed to retrieve authentication token with error message: $($_.Exception.Message)"
    }
}