#Requires -Version 5.1
<#
.SYNOPSIS
    Test Intune App Factory workflows locally
.DESCRIPTION
    This script runs the Intune App Factory pipeline locally, either using Docker/act or directly via PowerShell.
.PARAMETER UseDocker
    Use Docker and act to run the workflow. Default is false (runs directly).
.PARAMETER SecretsFile
    Path to the secrets file. Default is '.secrets.local'
.PARAMETER SkipModuleInstall
    Skip PowerShell module installation if already installed.
.PARAMETER TestOnly
    Only run validation tests without downloading or publishing.
.PARAMETER SkipPublish
    Skip the publish to Intune step.
.PARAMETER SkipAssignment
    Skip the assignment step.
.PARAMETER VerboseLogging
    Enable verbose logging for all operations.
.EXAMPLE
    .\Test-LocalWorkflow.ps1
    Runs the full pipeline locally without Docker
.EXAMPLE
    .\Test-LocalWorkflow.ps1 -TestOnly
    Only validates configurations without processing apps
.EXAMPLE
    .\Test-LocalWorkflow.ps1 -UseDocker
    Runs using Docker and act
.EXAMPLE
    .\Test-LocalWorkflow.ps1 -VerboseLogging
    Runs with detailed verbose logging enabled
#>
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$UseDocker,
    
    [Parameter()]
    [string]$SecretsFile = '.secrets.local',
    
    [Parameter()]
    [switch]$SkipModuleInstall,
    
    [Parameter()]
    [switch]$TestOnly,
    
    [Parameter()]
    [switch]$SkipPublish,
    
    [Parameter()]
    [switch]$SkipAssignment,
    
    [Parameter()]
    [switch]$VerboseLogging
)

# Set error action preference
$ErrorActionPreference = 'Stop'

# Enable verbose preference if requested
if ($VerboseLogging) {
    $VerbosePreference = 'Continue'
    Write-Verbose "Verbose logging enabled"
}

# Function to write verbose log
function Write-VerboseLog {
    param([string]$Message)
    if ($VerboseLogging) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor DarkGray
    }
}

# Function to write colored output
function Write-StepHeader {
    param([string]$Message)
    Write-Host "`n" -NoNewline
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Green
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function Write-StepResult {
    param(
        [string]$Message,
        [switch]$Success,
        [switch]$Warning,
        [switch]$Error
    )
    if ($Success) {
        Write-Host "✅ $Message" -ForegroundColor Green
    } elseif ($Warning) {
        Write-Host "⚠️ $Message" -ForegroundColor Yellow
    } elseif ($Error) {
        Write-Host "❌ $Message" -ForegroundColor Red
    } else {
        Write-Host $Message -ForegroundColor Gray
    }
}

# If using Docker, run the original act-based workflow
if ($UseDocker) {
    # Check if act is installed
    $actPath = Get-Command act -ErrorAction SilentlyContinue
    if (-not $actPath) {
        Write-Error "act is not installed. Please install act from https://github.com/nektos/act"
        Write-Host "Installation options:" -ForegroundColor Yellow
        Write-Host "  macOS:    brew install act" -ForegroundColor Gray
        Write-Host "  Windows:  choco install act-cli" -ForegroundColor Gray
        exit 1
    }
    
    # Check if Docker is running
    try {
        docker ps 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Docker is not running"
        }
    } catch {
        Write-Error "Docker is not running. Please start Docker Desktop."
        exit 1
    }

    # Check if secrets file exists
    if (-not (Test-Path $SecretsFile)) {
        Write-Warning "Secrets file '$SecretsFile' not found. Creating from template..."
        if (Test-Path '.secrets') {
            Copy-Item '.secrets' $SecretsFile
            Write-Host "Created $SecretsFile from template. Please edit it with your actual values." -ForegroundColor Yellow
            exit 1
        } else {
            Write-Error "No .secrets template file found."
            exit 1
        }
    }
    
    # Validate secrets file has been edited
    $secretsContent = Get-Content $SecretsFile -Raw
    if ($secretsContent -match 'your-.*-here') {
        Write-Error "Please edit $SecretsFile and replace the placeholder values with your actual secrets."
        exit 1
    }

    # Build act command
    $actCommand = "act"
    $actArgs = @()
    
    # Add event type
    $actArgs += 'workflow_dispatch'
    
    # Add workflow file
    $actArgs += '-W', ".github/workflows/publish.yml"
    
    # Add secrets file
    $actArgs += '--secret-file', $SecretsFile
    
    # Add verbosity for better debugging
    $actArgs += '-v'
    
    # Show what we're running
    Write-Host "Running: $actCommand $($actArgs -join ' ')" -ForegroundColor Cyan
    
    # Run act
    & $actCommand $actArgs
    
    # Check result
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nWorkflow completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "`nWorkflow failed with exit code: $LASTEXITCODE" -ForegroundColor Red
    }
    exit $LASTEXITCODE
}

# Run the pipeline directly without Docker
Write-Host "`n🚀 Intune App Factory - Local Pipeline Runner" -ForegroundColor Magenta
Write-Host "Running pipeline directly without Docker/act" -ForegroundColor Cyan
Write-VerboseLog "Starting pipeline execution with parameters:"
Write-VerboseLog "  UseDocker: $UseDocker"
Write-VerboseLog "  SkipModuleInstall: $SkipModuleInstall"
Write-VerboseLog "  TestOnly: $TestOnly"
Write-VerboseLog "  SkipPublish: $SkipPublish"
Write-VerboseLog "  SkipAssignment: $SkipAssignment"
Write-VerboseLog "  VerboseLogging: $VerboseLogging"
Write-VerboseLog "  Working Directory: $PSScriptRoot"

# Load secrets from file
Write-StepHeader "Loading Configuration"
Write-VerboseLog "Checking for secrets file: $SecretsFile"

if (-not (Test-Path $SecretsFile)) {
    Write-VerboseLog "Secrets file not found, checking environment variables"
    # Try to use environment variables
    $tenantId = $env:TENANT_ID
    $clientId = $env:CLIENT_ID
    $clientSecret = $env:CLIENT_SECRET
    $workspaceId = $env:LOG_ANALYTICS_WORKSPACE_ID
    $sharedKey = $env:LOG_ANALYTICS_SHARED_KEY
    
    Write-VerboseLog "Environment variables found:"
    Write-VerboseLog "  TENANT_ID: $(if ($tenantId) { 'Set' } else { 'Not set' })"
    Write-VerboseLog "  CLIENT_ID: $(if ($clientId) { 'Set' } else { 'Not set' })"
    Write-VerboseLog "  CLIENT_SECRET: $(if ($clientSecret) { 'Set' } else { 'Not set' })"
    
    if (-not $tenantId -or -not $clientId -or -not $clientSecret) {
        Write-Error "No secrets file found and required environment variables are not set."
        Write-Host "Please either:" -ForegroundColor Yellow
        Write-Host "  1. Create a .secrets.local file with your credentials" -ForegroundColor Gray
        Write-Host "  2. Set environment variables: TENANT_ID, CLIENT_ID, CLIENT_SECRET" -ForegroundColor Gray
        exit 1
    }
    Write-StepResult "Using environment variables for authentication" -Success
} else {
    Write-VerboseLog "Loading secrets from file: $SecretsFile"
    # Load secrets from file
    $secrets = @{}
    Get-Content $SecretsFile | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            $secrets[$matches[1]] = $matches[2]
            Write-VerboseLog "  Found secret: $($matches[1])"
        }
    }
    
    $tenantId = $secrets['TENANT_ID']
    $clientId = $secrets['CLIENT_ID']
    $clientSecret = $secrets['CLIENT_SECRET']
    $workspaceId = $secrets['LOG_ANALYTICS_WORKSPACE_ID']
    $sharedKey = $secrets['LOG_ANALYTICS_SHARED_KEY']
    
    Write-VerboseLog "Secrets loaded:"
    Write-VerboseLog "  TENANT_ID: $(if ($tenantId) { 'Set' } else { 'Not set' })"
    Write-VerboseLog "  CLIENT_ID: $(if ($clientId) { 'Set' } else { 'Not set' })"
    Write-VerboseLog "  CLIENT_SECRET: $(if ($clientSecret) { 'Set' } else { 'Not set' })"
    
    if (-not $tenantId -or -not $clientId -or -not $clientSecret) {
        Write-Error "Required secrets (TENANT_ID, CLIENT_ID, CLIENT_SECRET) not found in $SecretsFile"
        exit 1
    }
    Write-StepResult "Loaded secrets from $SecretsFile" -Success
}

# Set environment variables for the scripts
Write-VerboseLog "Setting environment variables for pipeline scripts"
$env:BUILD_SOURCESDIRECTORY = $PSScriptRoot
$env:BUILD_BINARIESDIRECTORY = $PSScriptRoot
$env:BUILD_ARTIFACTSTAGINGDIRECTORY = $PSScriptRoot
$env:PIPELINE_WORKSPACE = $PSScriptRoot
Write-VerboseLog "  BUILD_SOURCESDIRECTORY: $PSScriptRoot"
Write-VerboseLog "  BUILD_BINARIESDIRECTORY: $PSScriptRoot"
Write-VerboseLog "  BUILD_ARTIFACTSTAGINGDIRECTORY: $PSScriptRoot"
Write-VerboseLog "  PIPELINE_WORKSPACE: $PSScriptRoot"

# Step 1: Install PowerShell Modules
if (-not $SkipModuleInstall) {
    Write-StepHeader "Installing PowerShell Modules"
    Write-VerboseLog "Starting PowerShell module installation"
    
    try {
        # Import PowerShellGet first
        Import-Module PowerShellGet -Force
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        
        $modules = @(
            'Evergreen',
            'Microsoft.Graph.Authentication',
            'Microsoft.Graph.DeviceManagement',
            'Microsoft.Graph.DeviceManagement.Actions',
            'Microsoft.Graph.Groups',
            'MSAL.PS'
        )
        
        foreach ($module in $modules) {
            Write-VerboseLog "Checking module: $module"
            if (Get-Module -ListAvailable -Name $module) {
                $moduleVersion = (Get-Module -ListAvailable -Name $module | Select-Object -First 1).Version
                Write-VerboseLog "  Module $module version $moduleVersion is already installed"
                Write-StepResult "$module already installed" -Success
            } else {
                Write-VerboseLog "  Module $module not found, installing..."
                Write-Host "Installing $module..." -ForegroundColor Cyan
                Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
                Write-StepResult "$module installed" -Success
            }
        }
    } catch {
        Write-StepResult "Failed to install modules: $_" -Error
        exit 1
    }
} else {
    Write-StepResult "Skipping module installation (SkipModuleInstall flag set)" -Warning
}

# Step 2: Test Templates
Write-StepHeader "Testing Templates"
Write-VerboseLog "Running template validation script"

try {
    Write-VerboseLog "Executing: $PSScriptRoot\Scripts\Test-TemplatesFolder.ps1"
    if ($VerboseLogging) {
        $result = & "$PSScriptRoot\Scripts\Test-TemplatesFolder.ps1" -Verbose
    } else {
        $result = & "$PSScriptRoot\Scripts\Test-TemplatesFolder.ps1"
    }
    Write-Output $result
    if ($result -match "aborting pipeline") {
        Write-StepResult "Template validation failed - missing required files" -Error
        exit 1
    }
    Write-StepResult "Template validation passed" -Success
} catch {
    Write-StepResult "Template validation failed: $_" -Error
    exit 1
}

# Step 3: Test App Files
Write-StepHeader "Validating App Configurations"
Write-VerboseLog "Running app file validation script"

try {
    Write-VerboseLog "Executing: $PSScriptRoot\Scripts\Test-AppFiles.ps1"
    if ($VerboseLogging) {
        & "$PSScriptRoot\Scripts\Test-AppFiles.ps1" -Verbose
    } else {
        & "$PSScriptRoot\Scripts\Test-AppFiles.ps1"
    }
    
    # Move AppsProcessList.json to expected location
    if (Test-Path "$PSScriptRoot\AppsProcessList.json") {
        Write-VerboseLog "Moving AppsProcessList.json to expected location"
        New-Item -ItemType Directory -Path "$PSScriptRoot\AppsProcessList" -Force | Out-Null
        Move-Item -Path "$PSScriptRoot\AppsProcessList.json" -Destination "$PSScriptRoot\AppsProcessList\AppsProcessList.json" -Force
        Write-VerboseLog "  Moved to: $PSScriptRoot\AppsProcessList\AppsProcessList.json"
        Write-StepResult "App configurations validated" -Success
    } else {
        Write-VerboseLog "AppsProcessList.json not created"
    }
} catch {
    Write-StepResult "App validation failed: $_" -Error
    exit 1
}

if ($TestOnly) {
    Write-StepResult "Test-only mode completed successfully" -Success
    exit 0
}

# Step 4: Check for New Application Versions
Write-StepHeader "Checking for New Application Versions"
Write-VerboseLog "Running application version check"

try {
    Write-VerboseLog "Executing: $PSScriptRoot\Scripts\Test-AppList.ps1"
    Write-VerboseLog "  TenantID: $(if ($tenantId) { $tenantId.Substring(0,8) + '...' } else { 'Not set' })"
    Write-VerboseLog "  ClientID: $(if ($clientId) { $clientId.Substring(0,8) + '...' } else { 'Not set' })"
    
    if ($VerboseLogging) {
        & "$PSScriptRoot\Scripts\Test-AppList.ps1" `
            -TenantID $tenantId `
            -ClientID $clientId `
            -ClientSecret $clientSecret `
            -Verbose
    } else {
        & "$PSScriptRoot\Scripts\Test-AppList.ps1" `
            -TenantID $tenantId `
            -ClientID $clientId `
            -ClientSecret $clientSecret
    }
    
    # Check if any apps need processing
    if (Test-Path "$PSScriptRoot\AppsDownloadList.json") {
        Write-VerboseLog "Reading AppsDownloadList.json"
        $apps = Get-Content "$PSScriptRoot\AppsDownloadList.json" | ConvertFrom-Json
        Write-VerboseLog "Apps found in download list: $($apps.Count)"
        if ($apps.Count -eq 0) {
            Write-StepResult "No applications need updating" -Warning
            exit 0
        }
        foreach ($app in $apps) {
            Write-VerboseLog "  - $($app.IntuneAppName): $($app.AppVersion)"
        }
        Write-StepResult "Found $($apps.Count) applications to process" -Success
    } else {
        Write-VerboseLog "AppsDownloadList.json not found"
        Write-StepResult "No applications to process" -Warning
        exit 0
    }
} catch {
    Write-StepResult "Version check failed: $_" -Error
    exit 1
}

# Step 5: Download Applications
Write-StepHeader "Downloading Application Installers"
Write-VerboseLog "Starting application download process"

if (Test-Path "$PSScriptRoot\AppsDownloadList.json") {
    try {
        Write-VerboseLog "Preparing AppsDownloadList directory"
        # Move AppsDownloadList.json to expected location
        if (-not (Test-Path "$PSScriptRoot\AppsDownloadList")) {
            New-Item -ItemType Directory -Path "$PSScriptRoot\AppsDownloadList" -Force | Out-Null
            Write-VerboseLog "  Created directory: $PSScriptRoot\AppsDownloadList"
        }
        Copy-Item -Path "$PSScriptRoot\AppsDownloadList.json" -Destination "$PSScriptRoot\AppsDownloadList\AppsDownloadList.json" -Force
        Write-VerboseLog "  Copied AppsDownloadList.json to AppsDownloadList directory"
        
        # Run the download script
        Write-VerboseLog "Executing: $PSScriptRoot\Scripts\Save-Installer.ps1"
        if ($VerboseLogging) {
            & "$PSScriptRoot\Scripts\Save-Installer.ps1" -Verbose
        } else {
            & "$PSScriptRoot\Scripts\Save-Installer.ps1"
        }
        Write-StepResult "Applications downloaded successfully" -Success
    } catch {
        Write-StepResult "Download failed: $_" -Error
        exit 1
    }
}

# Step 6: Prepare Application Packages
Write-StepHeader "Preparing Application Packages"
Write-VerboseLog "Starting application package preparation"

try {
    # The Save-Installer script should create AppsPrepareList.json
    if (Test-Path "$PSScriptRoot\AppsPrepareList.json") {
        Write-VerboseLog "Found AppsPrepareList.json"
        # Move AppsPrepareList.json to expected location
        if (-not (Test-Path "$PSScriptRoot\AppsPrepareList")) {
            New-Item -ItemType Directory -Path "$PSScriptRoot\AppsPrepareList" -Force | Out-Null
            Write-VerboseLog "  Created directory: $PSScriptRoot\AppsPrepareList"
        }
        Move-Item -Path "$PSScriptRoot\AppsPrepareList.json" -Destination "$PSScriptRoot\AppsPrepareList\AppsPrepareList.json" -Force
        Write-VerboseLog "  Moved AppsPrepareList.json to AppsPrepareList directory"
    } elseif (Test-Path "$PSScriptRoot\AppsDownloadList.json") {
        Write-VerboseLog "AppsPrepareList.json not found, using AppsDownloadList.json as fallback"
        # Create AppsPrepareList.json from AppsDownloadList.json
        $downloadList = Get-Content "$PSScriptRoot\AppsDownloadList.json" | ConvertFrom-Json
        $downloadList | ConvertTo-Json -Depth 10 | Out-File -FilePath "$PSScriptRoot\AppsPrepareList.json" -Encoding UTF8
        Write-VerboseLog "  Created AppsPrepareList.json from AppsDownloadList.json"
        
        # Move to expected location
        if (-not (Test-Path "$PSScriptRoot\AppsPrepareList")) {
            New-Item -ItemType Directory -Path "$PSScriptRoot\AppsPrepareList" -Force | Out-Null
            Write-VerboseLog "  Created directory: $PSScriptRoot\AppsPrepareList"
        }
        Move-Item -Path "$PSScriptRoot\AppsPrepareList.json" -Destination "$PSScriptRoot\AppsPrepareList\AppsPrepareList.json" -Force
        Write-VerboseLog "  Moved AppsPrepareList.json to AppsPrepareList directory"
    }
    
    # Run the prepare script
    Write-VerboseLog "Executing: $PSScriptRoot\Scripts\Prepare-AppPackageFolder.ps1"
    if ($VerboseLogging) {
        & "$PSScriptRoot\Scripts\Prepare-AppPackageFolder.ps1" -Verbose
    } else {
        & "$PSScriptRoot\Scripts\Prepare-AppPackageFolder.ps1"
    }
    
    # Check results
    if (Test-Path "$PSScriptRoot\AppsPublishList.json") {
        Write-VerboseLog "Found AppsPublishList.json"
        $publishApps = Get-Content "$PSScriptRoot\AppsPublishList.json" | ConvertFrom-Json
        Write-VerboseLog "Apps ready for publishing: $($publishApps.Count)"
        foreach ($app in $publishApps) {
            Write-VerboseLog "  - $($app.IntuneAppName)"
        }
        Write-StepResult "Prepared $($publishApps.Count) apps for publishing" -Success
        
        # Move AppsPublishList.json to expected location
        if (-not (Test-Path "$PSScriptRoot\AppsPublishList")) {
            New-Item -ItemType Directory -Path "$PSScriptRoot\AppsPublishList" -Force | Out-Null
            Write-VerboseLog "  Created directory: $PSScriptRoot\AppsPublishList"
        }
        Move-Item -Path "$PSScriptRoot\AppsPublishList.json" -Destination "$PSScriptRoot\AppsPublishList\AppsPublishList.json" -Force
        Write-VerboseLog "  Moved AppsPublishList.json to AppsPublishList directory"
    } else {
        Write-VerboseLog "AppsPublishList.json not found"
        Write-StepResult "No apps prepared for publishing" -Warning
    }
} catch {
    Write-StepResult "Package preparation failed: $_" -Error
    exit 1
}

# Step 7: Download IntuneWinAppUtil
Write-StepHeader "Downloading IntuneWinAppUtil"
Write-VerboseLog "Checking for IntuneWinAppUtil.exe"

$IntuneWinAppUtilPath = "$PSScriptRoot\IntuneWinAppUtil.exe"
Write-VerboseLog "  Path: $IntuneWinAppUtilPath"

if (-not (Test-Path $IntuneWinAppUtilPath)) {
    Write-VerboseLog "IntuneWinAppUtil.exe not found, downloading..."
    try {
        $ProgressPreference = 'SilentlyContinue'
        $url = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe"
        Write-VerboseLog "  Download URL: $url"
        Invoke-WebRequest -Uri $url -OutFile $IntuneWinAppUtilPath -UseBasicParsing
        Write-VerboseLog "  Downloaded successfully"
        Write-StepResult "Downloaded IntuneWinAppUtil.exe" -Success
    } catch {
        Write-VerboseLog "  Download failed: $_"
        Write-StepResult "Failed to download IntuneWinAppUtil.exe: $_" -Error
        exit 1
    }
} else {
    $fileInfo = Get-Item $IntuneWinAppUtilPath
    Write-VerboseLog "  File exists (Size: $($fileInfo.Length) bytes, Modified: $($fileInfo.LastWriteTime))"
    Write-StepResult "IntuneWinAppUtil.exe already exists" -Success
}

# Step 8: Publish to Intune
if (-not $SkipPublish) {
    Write-StepHeader "Publishing Applications to Intune"
    Write-VerboseLog "Starting Intune publishing process"
    
    if (Test-Path "$PSScriptRoot\AppsPublishList\AppsPublishList.json") {
        try {
            Write-VerboseLog "Reading AppsPublishList.json"
            $publishApps = Get-Content "$PSScriptRoot\AppsPublishList\AppsPublishList.json" | ConvertFrom-Json
            Write-Host "Publishing $($publishApps.Count) applications:" -ForegroundColor Cyan
            foreach ($app in $publishApps) {
                Write-Host "  - $($app.IntuneAppName)" -ForegroundColor Gray
                Write-VerboseLog "    Version: $($app.AppVersion)"
            }
            
            Write-VerboseLog "Executing: $PSScriptRoot\Scripts\New-Win32App-GraphSDK.ps1"
            Write-VerboseLog "  TenantID: $(if ($tenantId) { $tenantId.Substring(0,8) + '...' } else { 'Not set' })"
            Write-VerboseLog "  ClientID: $(if ($clientId) { $clientId.Substring(0,8) + '...' } else { 'Not set' })"
            
            # Use the Graph SDK version of the script
            if ($VerboseLogging) {
                & "$PSScriptRoot\Scripts\New-Win32App-GraphSDK.ps1" `
                    -TenantID $tenantId `
                    -ClientID $clientId `
                    -ClientSecret $clientSecret `
                    -WorkspaceID $(if ($workspaceId) { $workspaceId } else { "dummy" }) `
                    -SharedKey $(if ($sharedKey) { $sharedKey } else { "dummy" }) `
                    -Verbose
            } else {
                & "$PSScriptRoot\Scripts\New-Win32App-GraphSDK.ps1" `
                    -TenantID $tenantId `
                    -ClientID $clientId `
                    -ClientSecret $clientSecret `
                    -WorkspaceID $(if ($workspaceId) { $workspaceId } else { "dummy" }) `
                    -SharedKey $(if ($sharedKey) { $sharedKey } else { "dummy" })
            }
            
            Write-StepResult "Applications published successfully" -Success
        } catch {
            Write-StepResult "Publishing failed: $_" -Error
            exit 1
        }
    } else {
        Write-VerboseLog "AppsPublishList.json not found at: $PSScriptRoot\AppsPublishList\AppsPublishList.json"
        Write-StepResult "No apps to publish" -Warning
    }
} else {
    Write-VerboseLog "Skipping publish step due to SkipPublish flag"
    Write-StepResult "Skipping publish step (SkipPublish flag set)" -Warning
}

# Step 9: Assign Applications
if (-not $SkipAssignment -and -not $SkipPublish) {
    Write-StepHeader "Assigning Applications"
    Write-VerboseLog "Starting application assignment process"
    
    if (Test-Path "$PSScriptRoot\AppsAssignmentList.json") {
        try {
            Write-VerboseLog "Found AppsAssignmentList.json"
            Write-VerboseLog "Executing: $PSScriptRoot\Scripts\New-AppAssignment-GraphSDK.ps1"
            
            if ($VerboseLogging) {
                & "$PSScriptRoot\Scripts\New-AppAssignment-GraphSDK.ps1" `
                    -TenantID $tenantId `
                    -ClientID $clientId `
                    -ClientSecret $clientSecret `
                    -WorkspaceID $(if ($workspaceId) { $workspaceId } else { "dummy" }) `
                    -SharedKey $(if ($sharedKey) { $sharedKey } else { "dummy" }) `
                    -Verbose
            } else {
                & "$PSScriptRoot\Scripts\New-AppAssignment-GraphSDK.ps1" `
                    -TenantID $tenantId `
                    -ClientID $clientId `
                    -ClientSecret $clientSecret `
                    -WorkspaceID $(if ($workspaceId) { $workspaceId } else { "dummy" }) `
                    -SharedKey $(if ($sharedKey) { $sharedKey } else { "dummy" })
            }
            
            Write-StepResult "Applications assigned successfully" -Success
        } catch {
            Write-StepResult "Assignment failed: $_" -Error
            exit 1
        }
    } else {
        Write-VerboseLog "AppsAssignmentList.json not found"
        Write-StepResult "No assignments to process" -Warning
    }
} else {
    if ($SkipAssignment) {
        Write-VerboseLog "Skipping assignment step due to SkipAssignment flag"
        Write-StepResult "Skipping assignment step (SkipAssignment flag set)" -Warning
    } else {
        Write-VerboseLog "Skipping assignment step because publish was skipped"
    }
}

# Step 10: Cleanup
Write-StepHeader "Cleaning Up"
Write-VerboseLog "Starting cleanup process"

try {
    # Remove temporary files
    $tempFiles = @(
        "$PSScriptRoot\AppsDownloadList.json",
        "$PSScriptRoot\AppsPublishList.json",
        "$PSScriptRoot\AppsAssignmentList.json",
        "$PSScriptRoot\AppsProcessList.json"
    )
    
    foreach ($file in $tempFiles) {
        if (Test-Path $file) {
            Write-VerboseLog "Removing file: $file"
            Remove-Item $file -Force
            Write-Host "  Removed: $(Split-Path $file -Leaf)" -ForegroundColor Gray
        } else {
            Write-VerboseLog "File not found (skipping): $file"
        }
    }
    
    # Clean up folders
    $tempFolders = @(
        "$PSScriptRoot\AppsDownloadList",
        "$PSScriptRoot\AppsPublishList",
        "$PSScriptRoot\AppsAssignmentList",
        "$PSScriptRoot\AppsProcessList",
        "$PSScriptRoot\AppsPrepareList"
    )
    
    foreach ($folder in $tempFolders) {
        if (Test-Path $folder) {
            Write-VerboseLog "Removing folder: $folder"
            Remove-Item $folder -Recurse -Force
            Write-Host "  Removed: $(Split-Path $folder -Leaf) folder" -ForegroundColor Gray
        } else {
            Write-VerboseLog "Folder not found (skipping): $folder"
        }
    }
    
    # Optional: Clean up download and output folders
    if (Test-Path "$PSScriptRoot\Downloads") {
        Write-VerboseLog "Removing Downloads folder"
        Remove-Item "$PSScriptRoot\Downloads" -Recurse -Force
        Write-Host "  Removed: Downloads folder" -ForegroundColor Gray
    } else {
        Write-VerboseLog "Downloads folder not found"
    }
    
    if (Test-Path "$PSScriptRoot\Output") {
        Write-VerboseLog "Removing Output folder"
        Remove-Item "$PSScriptRoot\Output" -Recurse -Force
        Write-Host "  Removed: Output folder" -ForegroundColor Gray
    } else {
        Write-VerboseLog "Output folder not found"
    }
    
    Write-VerboseLog "Cleanup process completed"
    Write-StepResult "Cleanup completed" -Success
} catch {
    Write-VerboseLog "Cleanup error: $_"
    Write-StepResult "Cleanup failed: $_" -Warning
}

Write-VerboseLog "Pipeline execution completed"
Write-Host "`n" -NoNewline
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "✅ Pipeline completed successfully!" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green

if ($VerboseLogging) {
    Write-Host "`nVerbose logging was enabled. Review the timestamped logs above for detailed execution information." -ForegroundColor DarkGray
}