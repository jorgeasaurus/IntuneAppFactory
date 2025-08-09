#Requires -Version 5.1
<#
.SYNOPSIS
    Test Intune App Factory pipeline locally on Windows
.DESCRIPTION
    This script simulates the GitHub Actions workflow locally on Windows without Docker.
    It runs the same PowerShell scripts that the workflow would run.
.PARAMETER SkipModuleInstall
    Skip installing PowerShell modules (use if already installed)
.PARAMETER TestOnly
    Only run the test and check phases, skip publishing
.EXAMPLE
    .\Test-LocalPipeline.ps1
    Runs the full pipeline locally
.EXAMPLE
    .\Test-LocalPipeline.ps1 -TestOnly
    Only tests and checks for new versions without publishing
#>
[CmdletBinding()]
param(
    [switch]$SkipModuleInstall,
    [switch]$TestOnly
)

# Set up environment variables from .secrets.local
function Set-LocalSecrets {
    param([string]$SecretsFile = ".secrets.local")
    
    if (-not (Test-Path $SecretsFile)) {
        Write-Error "Secrets file not found. Please create $SecretsFile from .secrets template"
        Write-Host "Example content:" -ForegroundColor Yellow
        Write-Host @"
TENANT_ID=your-tenant-id-here
CLIENT_ID=your-client-id-here  
CLIENT_SECRET=your-client-secret-here
LOG_ANALYTICS_WORKSPACE_ID=optional-workspace-id
LOG_ANALYTICS_SHARED_KEY=optional-shared-key
"@ -ForegroundColor Gray
        return $false
    }
    
    Write-Host "Loading secrets from $SecretsFile..." -ForegroundColor Cyan
    $secrets = @{}
    Get-Content $SecretsFile | ForEach-Object {
        if ($_ -match '^([^#]\S+)\s*=\s*(.+)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            if ($value -ne 'your-tenant-id-here' -and 
                $value -ne 'your-client-id-here' -and 
                $value -ne 'your-client-secret-here' -and
                $value -ne 'optional-workspace-id' -and
                $value -ne 'optional-shared-key') {
                $secrets[$key] = $value
                Set-Item -Path "env:$key" -Value $value
            }
        }
    }
    
    # Validate required secrets
    $required = @('TENANT_ID', 'CLIENT_ID', 'CLIENT_SECRET')
    $missing = $required | Where-Object { -not $secrets.ContainsKey($_) }
    
    if ($missing) {
        Write-Error "Missing required secrets: $($missing -join ', ')"
        return $false
    }
    
    Write-Host "Loaded $($secrets.Count) secrets" -ForegroundColor Green
    return $true
}

# Main pipeline
try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Intune App Factory - Local Testing" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Load secrets
    if (-not (Set-LocalSecrets)) {
        exit 1
    }
    
    # Set environment variables for Azure DevOps compatibility
    $env:BUILD_SOURCESDIRECTORY = $PSScriptRoot
    $env:BUILD_BINARIESDIRECTORY = $PSScriptRoot
    $env:BUILD_ARTIFACTSTAGINGDIRECTORY = $PSScriptRoot
    $env:PIPELINE_WORKSPACE = $PSScriptRoot
    Write-Host "Set Azure DevOps environment variables for local testing" -ForegroundColor Gray
    
    # Ensure IntuneWinAppUtil.exe is available
    $IntuneWinAppUtilPath = Join-Path $PSScriptRoot "Tools\IntuneWinAppUtil.exe"
    if (-not (Test-Path $IntuneWinAppUtilPath)) {
        Write-Host "`nDownloading IntuneWinAppUtil.exe..." -ForegroundColor Yellow
        $ProgressPreference = 'SilentlyContinue'
        
        # Create Tools directory if it doesn't exist
        $ToolsPath = Join-Path $PSScriptRoot "Tools"
        if (-not (Test-Path $ToolsPath)) {
            New-Item -ItemType Directory -Path $ToolsPath -Force | Out-Null
        }
        
        # Download from Microsoft's official repository
        $url = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe"
        try {
            Invoke-WebRequest -Uri $url -OutFile $IntuneWinAppUtilPath -UseBasicParsing
            Write-Host "Successfully downloaded IntuneWinAppUtil.exe" -ForegroundColor Green
        } catch {
            Write-Error "Failed to download IntuneWinAppUtil.exe: $_"
            exit 1
        }
    } else {
        Write-Host "IntuneWinAppUtil.exe already exists" -ForegroundColor Gray
    }
    
    # Step 1: Install PowerShell Modules
    if (-not $SkipModuleInstall) {
        Write-Host "`n[Step 1] Installing PowerShell Modules..." -ForegroundColor Green
        & ".\Scripts\Install-Modules-GraphSDK.ps1" -Verbose
        if ($LASTEXITCODE -ne 0) { throw "Module installation failed" }
    } else {
        Write-Host "`n[Step 1] Skipping module installation (use -SkipModuleInstall)" -ForegroundColor Yellow
    }
    
    # Step 2: Test Templates
    Write-Host "`n[Step 2] Testing template files..." -ForegroundColor Green
    $templateResult = & ".\Scripts\Test-TemplatesFolder.ps1"
    Write-Output $templateResult
    if ($templateResult -match "aborting pipeline") { 
        throw "Template validation failed - missing required files" 
    }
    
    # Step 2.5: Test App Files and create AppsProcessList.json
    Write-Host "`n[Step 2.5] Validating app configurations..." -ForegroundColor Green
    & ".\Scripts\Test-AppFiles.ps1"
    
    # Move the file to the expected location
    if (Test-Path ".\AppsProcessList.json") {
        if (-not (Test-Path ".\AppsProcessList")) {
            New-Item -ItemType Directory -Path ".\AppsProcessList" -Force | Out-Null
        }
        Move-Item -Path ".\AppsProcessList.json" -Destination ".\AppsProcessList\AppsProcessList.json" -Force
        Write-Host "Moved AppsProcessList.json to AppsProcessList directory" -ForegroundColor Gray
    } else {
        throw "Failed to create AppsProcessList.json"
    }
    
    # Step 3: Test and Check Applications
    Write-Host "`n[Step 3] Checking for new application versions..." -ForegroundColor Green
    & ".\Scripts\Test-AppList.ps1" `
        -TenantID $env:TENANT_ID `
        -ClientID $env:CLIENT_ID `
        -ClientSecret $env:CLIENT_SECRET `
        -Verbose
    
    # Check if any apps need processing
    if (Test-Path ".\AppsDownloadList.json") {
        $apps = Get-Content ".\AppsDownloadList.json" | ConvertFrom-Json
        if ($apps.Count -eq 0) {
            Write-Host "`nNo applications need updating" -ForegroundColor Yellow
            exit 0
        }
        Write-Host "`nFound $($apps.Count) applications to process:" -ForegroundColor Green
        $apps | ForEach-Object { Write-Host "  - $($_.IntuneAppName)" -ForegroundColor Gray }
    } else {
        Write-Host "`nNo applications to process" -ForegroundColor Yellow
        exit 0
    }
    
    if ($TestOnly) {
        Write-Host "`n[Test Only Mode] Stopping here. Use without -TestOnly to continue." -ForegroundColor Yellow
        exit 0
    }
    
    # Step 4: Download Applications
    if (Test-Path ".\AppsDownloadList.json") {
        Write-Host "`n[Step 4] Downloading application installers..." -ForegroundColor Green
        
        # Move AppsDownloadList.json to expected location
        if (-not (Test-Path ".\AppsDownloadList")) {
            New-Item -ItemType Directory -Path ".\AppsDownloadList" -Force | Out-Null
        }
        Copy-Item -Path ".\AppsDownloadList.json" -Destination ".\AppsDownloadList\AppsDownloadList.json" -Force
        
        # Run the download script once (it processes all apps)
        & ".\Scripts\Save-Installer.ps1"
    }
    
    # Step 5: Prepare Application Packages  
    if (Test-Path ".\AppsPrepareList.json") {
        Write-Host "`n[Step 5] Preparing application packages..." -ForegroundColor Green
        
        # Move AppsPrepareList.json to expected location if needed
        if (-not (Test-Path ".\AppsPrepareList")) {
            New-Item -ItemType Directory -Path ".\AppsPrepareList" -Force | Out-Null
        }
        Move-Item -Path ".\AppsPrepareList.json" -Destination ".\AppsPrepareList\AppsPrepareList.json" -Force
        
        # Run the prepare script once (it processes all apps)
        & ".\Scripts\Prepare-AppPackageFolder.ps1"
    }
    
    # Step 6: Publish to Intune
    if (Test-Path ".\AppsPublishList.json") {
        Write-Host "`n[Step 6] Publishing applications to Intune..." -ForegroundColor Green
        
        # Set dummy values for optional parameters if not provided
        $workspaceId = if ($env:LOG_ANALYTICS_WORKSPACE_ID) { $env:LOG_ANALYTICS_WORKSPACE_ID } else { "dummy" }
        $sharedKey = if ($env:LOG_ANALYTICS_SHARED_KEY) { $env:LOG_ANALYTICS_SHARED_KEY } else { "dummy" }
        
        & ".\Scripts\New-Win32App-GraphSDK.ps1" `
            -TenantID $env:TENANT_ID `
            -ClientID $env:CLIENT_ID `
            -ClientSecret $env:CLIENT_SECRET `
            -WorkspaceID $workspaceId `
            -SharedKey $sharedKey `
            -Verbose
    }
    
    # Step 7: Assign Applications
    if (Test-Path ".\AppsAssignmentList.json") {
        Write-Host "`n[Step 7] Assigning applications..." -ForegroundColor Green
        
        $workspaceId = if ($env:LOG_ANALYTICS_WORKSPACE_ID) { $env:LOG_ANALYTICS_WORKSPACE_ID } else { "dummy" }
        $sharedKey = if ($env:LOG_ANALYTICS_SHARED_KEY) { $env:LOG_ANALYTICS_SHARED_KEY } else { "dummy" }
        
        & ".\Scripts\New-AppAssignment-GraphSDK.ps1" `
            -TenantID $env:TENANT_ID `
            -ClientID $env:CLIENT_ID `
            -ClientSecret $env:CLIENT_SECRET `
            -WorkspaceID $workspaceId `
            -SharedKey $sharedKey `
            -Verbose
    }
    
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  Pipeline completed successfully!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Green
    
} catch {
    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "  Pipeline failed!" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
    
} finally {
    # Cleanup
    Write-Host "`n[Cleanup] Cleaning up temporary files..." -ForegroundColor Gray
    
    $tempFiles = @(
        ".\AppsDownloadList.json",
        ".\AppsPublishList.json",
        ".\AppsAssignmentList.json",
        ".\AppsProcessList.json"
    )
    
    foreach ($file in $tempFiles) {
        if (Test-Path $file) {
            Remove-Item $file -Force -ErrorAction SilentlyContinue
            Write-Host "  Removed: $file" -ForegroundColor Gray
        }
    }
    
    if (Test-Path ".\Downloads") {
        Remove-Item ".\Downloads" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed Downloads folder" -ForegroundColor Gray
    }
    
    if (Test-Path ".\Output") {
        Remove-Item ".\Output" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed Output folder" -ForegroundColor Gray
    }
    
    if (Test-Path ".\AppsProcessList") {
        Remove-Item ".\AppsProcessList" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed AppsProcessList folder" -ForegroundColor Gray
    }
    
    if (Test-Path ".\AppsDownloadList") {
        Remove-Item ".\AppsDownloadList" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed AppsDownloadList folder" -ForegroundColor Gray
    }
    
    if (Test-Path ".\AppsPrepareList") {
        Remove-Item ".\AppsPrepareList" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed AppsPrepareList folder" -ForegroundColor Gray
    }
    
    if (Test-Path ".\Installers") {
        Remove-Item ".\Installers" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed Installers folder" -ForegroundColor Gray
    }
    
    if (Test-Path ".\Publish") {
        Remove-Item ".\Publish" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed Publish folder" -ForegroundColor Gray
    }
}