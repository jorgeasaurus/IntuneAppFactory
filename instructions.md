# IntuneAppFactory: Azure DevOps to GitHub Actions Migration Guide

## Overview

This guide provides instructions for adapting the IntuneAppFactory from Azure DevOps pipelines to GitHub Actions. The IntuneAppFactory automates Win32 application packaging and deployment to Microsoft Intune.

**This implementation uses GitHub Releases instead of Azure Storage Account for storing custom application installers, making the solution more cost-effective and easier to manage.**

## Key Components to Migrate

### 1. Pipeline Configuration
- **Azure DevOps**: Uses `publish.yml` in the repository root
- **GitHub Actions**: Will use `.github/workflows/publish.yml`

### 2. Required Secrets
The following secrets need to be migrated from Azure DevOps variable groups to GitHub Secrets:

#### App Registration/Service Principal
- `TENANT_ID` - Azure AD Tenant ID
- `CLIENT_ID` - App Registration Client ID  
- `CLIENT_SECRET` - App Registration Client Secret

#### Optional Secrets (if using certain features)
- `KEY_VAULT_NAME` - Azure Key Vault name (only if using Key Vault)

**Note:** This implementation does not require Azure Storage Account secrets as we're using GitHub Releases for file storage.

### 3. Self-Hosted Runner Setup
IntuneAppFactory requires a self-hosted runner (agent) because it needs to:
- Run PowerShell scripts
- Access local tools like IntuneWinAppUtil.exe
- Handle file packaging operations

## GitHub Actions Workflow Structure

Create `.github/workflows/publish.yml`:

```yaml
name: Intune App Factory

on:
  schedule:
    # Run every 6 hours
    - cron: '0 */6 * * *'
  workflow_dispatch:

env:
  # Release tag for custom apps
  CUSTOM_APPS_RELEASE_TAG: 'custom-apps-latest'

jobs:
  # Phase 1: Test Applications
  test_apps:
    name: Test Applications
    runs-on: [self-hosted, Windows]
    outputs:
      apps_to_process: ${{ steps.test_apps.outputs.apps_to_process }}
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install PowerShell Modules
        shell: pwsh
        run: |
          Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
          Install-Module -Name IntuneWin32App -RequiredVersion 1.4.0 -Force -AllowClobber
          Install-Module -Name Evergreen -Force -AllowClobber
          Install-Module -Name MSAL.PS -Force -AllowClobber

      - name: Test Application List
        id: test_apps
        shell: pwsh
        env:
          TENANT_ID: ${{ secrets.TENANT_ID }}
          CLIENT_ID: ${{ secrets.CLIENT_ID }}
          CLIENT_SECRET: ${{ secrets.CLIENT_SECRET }}
        run: |
          # Connect to Microsoft Graph
          $authParams = @{
            TenantId = $env:TENANT_ID
            ClientId = $env:CLIENT_ID
            ClientSecret = ($env:CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force)
          }
          
          $tokenResponse = Get-MsalToken @authParams -Scopes "https://graph.microsoft.com/.default"
          $headers = @{
            Authorization = "Bearer $($tokenResponse.AccessToken)"
          }
          
          # Load app list
          $appList = Get-Content -Path "./appList.json" | ConvertFrom-Json
          $appsToProcess = @()
          
          foreach ($app in $appList.Apps) {
            Write-Host "Checking: $($app.IntuneAppName)"
            
            # Check if update is needed (simplified - expand based on your logic)
            $needsUpdate = $true
            
            if ($app.AppSource -eq "Evergreen") {
              # Check Evergreen for latest version
              try {
                $evergreenApp = Get-EvergreenApp -Name $app.AppID | 
                  Where-Object { $_.Architecture -eq "x64" -and $_.Type -eq ($app.FilterOptions[0].Type) } | 
                  Select-Object -First 1
                
                if ($evergreenApp) {
                  $app | Add-Member -NotePropertyName "LatestVersion" -NotePropertyValue $evergreenApp.Version -Force
                  $app | Add-Member -NotePropertyName "DownloadUrl" -NotePropertyValue $evergreenApp.Uri -Force
                  $appsToProcess += $app
                }
              } catch {
                Write-Warning "Failed to get Evergreen info for $($app.IntuneAppName): $_"
              }
            }
            elseif ($app.AppSource -eq "GitHubRelease") {
              # For GitHub Release apps, we'll handle in package phase
              $appsToProcess += $app
            }
          }
          
          # Output apps to process as JSON
          $appsJson = $appsToProcess | ConvertTo-Json -Compress
          echo "apps_to_process=$appsJson" >> $env:GITHUB_OUTPUT

  # Phase 2: Package Applications
  package_apps:
    name: Package Applications
    needs: test_apps
    runs-on: [self-hosted, Windows]
    if: success() && needs.test_apps.outputs.apps_to_process != '[]'
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Download IntuneWinAppUtil
        shell: pwsh
        run: |
          $ProgressPreference = 'SilentlyContinue'
          $url = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe"
          $output = "${{ github.workspace }}\Tools\IntuneWinAppUtil.exe"
          
          New-Item -ItemType Directory -Path "${{ github.workspace }}\Tools" -Force
          Invoke-WebRequest -Uri $url -OutFile $output
          Write-Host "Downloaded IntuneWinAppUtil.exe"

      - name: Process and Package Applications
        shell: pwsh
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          $apps = '${{ needs.test_apps.outputs.apps_to_process }}' | ConvertFrom-Json
          
          foreach ($app in $apps) {
            Write-Host "Processing $($app.IntuneAppName)" -ForegroundColor Green
            
            # Create app directories
            $downloadPath = "${{ github.workspace }}\Downloads\$($app.AppFolderName)"
            $outputPath = "${{ github.workspace }}\Output"
            New-Item -ItemType Directory -Path $downloadPath -Force
            New-Item -ItemType Directory -Path $outputPath -Force
            
            # Download installer based on source
            switch ($app.AppSource) {
              "Evergreen" {
                if ($app.DownloadUrl) {
                  Write-Host "Downloading from: $($app.DownloadUrl)"
                  $fileName = Split-Path $app.DownloadUrl -Leaf
                  $setupFile = Join-Path $downloadPath $fileName
                  Invoke-WebRequest -Uri $app.DownloadUrl -OutFile $setupFile -UseBasicParsing
                }
              }
              
              "GitHubRelease" {
                # Download from GitHub Release
                Write-Host "Downloading from GitHub Release: $($app.ReleaseTag)"
                $headers = @{
                  Authorization = "token $env:GITHUB_TOKEN"
                  Accept = "application/octet-stream"
                }
                
                # Get release info
                $releaseUrl = "https://api.github.com/repos/${{ github.repository }}/releases/tags/$($app.ReleaseTag)"
                $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers
                
                # Find the asset
                $asset = $release.assets | Where-Object { $_.name -eq $app.SetupFile }
                if ($asset) {
                  $downloadUrl = $asset.url
                  $setupFile = Join-Path $downloadPath $app.SetupFile
                  
                  # Download the asset
                  Invoke-WebRequest -Uri $downloadUrl -Headers $headers -OutFile $setupFile
                  Write-Host "Downloaded: $($app.SetupFile)"
                } else {
                  Write-Error "Asset $($app.SetupFile) not found in release $($app.ReleaseTag)"
                  continue
                }
              }
              
              "DirectUrl" {
                Write-Host "Downloading from direct URL: $($app.DownloadUrl)"
                $fileName = Split-Path $app.DownloadUrl -Leaf
                $setupFile = Join-Path $downloadPath $fileName
                Invoke-WebRequest -Uri $app.DownloadUrl -OutFile $setupFile -UseBasicParsing
              }
            }
            
            # Copy app manifest and scripts
            $appFolder = "${{ github.workspace }}\Apps\$($app.AppFolderName)"
            if (Test-Path $appFolder) {
              Copy-Item -Path "$appFolder\*" -Destination $downloadPath -Recurse -Force
            }
            
            # Package the application
            $setupFileName = Split-Path $setupFile -Leaf
            Write-Host "Packaging application with IntuneWinAppUtil..."
            
            $intuneWinAppUtil = "${{ github.workspace }}\Tools\IntuneWinAppUtil.exe"
            & $intuneWinAppUtil -c $downloadPath -s $setupFileName -o $outputPath -q
            
            Write-Host "Successfully packaged: $($app.IntuneAppName)"
          }

      - name: Upload Packages as Artifacts
        uses: actions/upload-artifact@v3
        with:
          name: intune-packages
          path: ${{ github.workspace }}\Output\*.intunewin
          retention-days: 7

  # Phase 3: Publish Applications
  publish_apps:
    name: Publish Applications to Intune
    needs: [test_apps, package_apps]
    runs-on: [self-hosted, Windows]
    if: success()
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Download Package Artifacts
        uses: actions/download-artifact@v3
        with:
          name: intune-packages
          path: ${{ github.workspace }}\Output

      - name: Install PowerShell Modules
        shell: pwsh
        run: |
          Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
          Install-Module -Name IntuneWin32App -RequiredVersion 1.4.0 -Force -AllowClobber
          Install-Module -Name MSAL.PS -Force -AllowClobber

      - name: Publish Win32 Apps to Intune
        shell: pwsh
        env:
          TENANT_ID: ${{ secrets.TENANT_ID }}
          CLIENT_ID: ${{ secrets.CLIENT_ID }}
          CLIENT_SECRET: ${{ secrets.CLIENT_SECRET }}
        run: |
          # Connect to Intune
          Connect-MSIntuneGraph -TenantID $env:TENANT_ID -ClientID $env:CLIENT_ID -ClientSecret ($env:CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force)
          
          $apps = '${{ needs.test_apps.outputs.apps_to_process }}' | ConvertFrom-Json
          $packages = Get-ChildItem -Path "${{ github.workspace }}\Output" -Filter "*.intunewin"
          
          foreach ($package in $packages) {
            # Match package to app config
            $appName = $package.BaseName
            $appConfig = $apps | Where-Object { $_.AppFolderName -eq $appName }
            
            if (-not $appConfig) {
              Write-Warning "No config found for package: $($package.Name)"
              continue
            }
            
            Write-Host "Publishing: $($appConfig.IntuneAppName)" -ForegroundColor Green
            
            # Load app manifest
            $manifestPath = "${{ github.workspace }}\Apps\$($appConfig.AppFolderName)\App.json"
            if (Test-Path $manifestPath) {
              $manifest = Get-Content -Path $manifestPath | ConvertFrom-Json
              
              # Create requirement rule
              $requirementRule = New-IntuneWin32AppRequirementRule `
                -Architecture $manifest.RequirementRule.Architecture `
                -MinimumSupportedWindowsRelease $manifest.RequirementRule.MinimumSupportedWindowsRelease
              
              # Create detection rule
              $detectionRule = switch ($manifest.DetectionRule.Type) {
                "MSI" {
                  New-IntuneWin32AppDetectionRuleMSI -ProductCode $manifest.DetectionRule.ProductCode
                }
                "File" {
                  New-IntuneWin32AppDetectionRuleFile `
                    -Path $manifest.DetectionRule.Path `
                    -FileOrFolder $manifest.DetectionRule.FileOrFolder `
                    -DetectionType $manifest.DetectionRule.DetectionType `
                    -Check32BitOn64System $manifest.DetectionRule.Check32BitOn64System
                }
                "Registry" {
                  New-IntuneWin32AppDetectionRuleRegistry `
                    -RegistryKeyPath $manifest.DetectionRule.KeyPath `
                    -RegistryDetectionType $manifest.DetectionRule.DetectionType `
                    -Check32BitOn64System $manifest.DetectionRule.Check32BitOn64System
                }
              }
              
              # Prepare app parameters
              $appParams = @{
                FilePath = $package.FullName
                DisplayName = $appConfig.IntuneAppName
                Description = $manifest.Information.Description
                Publisher = $manifest.Information.Publisher
                InstallExperience = $manifest.ProgramInformation.InstallExperience
                RestartBehavior = $manifest.ProgramInformation.RestartBehavior
                DetectionRule = $detectionRule
                RequirementRule = $requirementRule
              }
              
              # Add install/uninstall commands
              if ($manifest.ProgramInformation.InstallCommand) {
                $appParams.InstallCommandLine = $manifest.ProgramInformation.InstallCommand
              }
              if ($manifest.ProgramInformation.UninstallCommand) {
                $appParams.UninstallCommandLine = $manifest.ProgramInformation.UninstallCommand
              }
              
              # Add icon if exists
              $iconPath = "${{ github.workspace }}\Apps\$($appConfig.AppFolderName)\Icon.png"
              if (Test-Path $iconPath) {
                $appParams.Icon = New-IntuneWin32AppIcon -FilePath $iconPath
              }
              
              # Publish to Intune
              $win32App = Add-IntuneWin32App @appParams
              
              if ($win32App) {
                Write-Host "Successfully published: $($appConfig.IntuneAppName) (ID: $($win32App.id))"
              }
            }
          }

  # Phase 4: Assign Applications
  assign_apps:
    name: Assign Applications
    needs: publish_apps
    runs-on: [self-hosted, Windows]
    if: success()
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install PowerShell Modules
        shell: pwsh
        run: |
          Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
          Install-Module -Name IntuneWin32App -RequiredVersion 1.4.0 -Force -AllowClobber
          Install-Module -Name MSAL.PS -Force -AllowClobber

      - name: Assign Win32 Apps
        shell: pwsh
        env:
          TENANT_ID: ${{ secrets.TENANT_ID }}
          CLIENT_ID: ${{ secrets.CLIENT_ID }}
          CLIENT_SECRET: ${{ secrets.CLIENT_SECRET }}
        run: |
          # Connect to Intune
          Connect-MSIntuneGraph -TenantID $env:TENANT_ID -ClientID $env:CLIENT_ID -ClientSecret ($env:CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force)
          
          # Process assignments based on App.json manifests
          $appFolders = Get-ChildItem -Path "${{ github.workspace }}\Apps" -Directory
          
          foreach ($folder in $appFolders) {
            $manifestPath = Join-Path $folder.FullName "App.json"
            if (Test-Path $manifestPath) {
              $manifest = Get-Content -Path $manifestPath | ConvertFrom-Json
              
              if ($manifest.Assignments) {
                Write-Host "Processing assignments for: $($manifest.Information.DisplayName)"
                
                # Get the app from Intune
                $intuneApp = Get-IntuneWin32App -DisplayName $manifest.Information.DisplayName | 
                  Sort-Object -Property CreateDateTime -Descending | 
                  Select-Object -First 1
                
                if ($intuneApp) {
                  foreach ($assignment in $manifest.Assignments) {
                    $assignmentParams = @{
                      ID = $intuneApp.id
                      Target = $assignment.Target
                      Intent = $assignment.Intent
                      Notification = $assignment.Notification
                    }
                    
                    if ($assignment.GroupID) {
                      $assignmentParams.GroupID = $assignment.GroupID
                    }
                    
                    Add-IntuneWin32AppAssignmentGroup @assignmentParams
                    Write-Host "Added assignment: $($assignment.Target) - $($assignment.Intent)"
                  }
                }
              }
            }
          }
```

## Repository Structure

Your GitHub repository should be organized as follows:

```
/
├── .github/
│   └── workflows/
│       └── publish.yml
├── Apps/
│   ├── 7zip/
│   │   ├── App.json
│   │   ├── Icon.png
│   │   └── Scripts/
│   │       └── detection.ps1
│   └── NotepadPlusPlus/
│       ├── App.json
│       ├── Icon.png
│       └── Scripts/
├── Tools/
├── Downloads/
├── Output/
└── appList.json
```

### appList.json Structure

```json
{
  "Apps": [
    {
      "IntuneAppName": "7-Zip",
      "IntuneAppNamingConvention": "PublisherAppNameAppVersion",
      "AppPublisher": "Igor Pavlov",
      "AppSource": "Evergreen",
      "AppID": "7zip",
      "AppFolderName": "7zip",
      "FilterOptions": [
        {
          "Architecture": "x64",
          "Type": "msi"
        }
      ]
    },
    {
      "IntuneAppName": "Custom Internal App",
      "IntuneAppNamingConvention": "AppName",
      "AppPublisher": "Contoso",
      "AppSource": "GitHubRelease",
      "AppFolderName": "CustomApp",
      "ReleaseTag": "v1.0.0",
      "SetupFile": "CustomApp.msi"
    }
  ]
}
```

### App.json Structure (per application)

```json
{
  "Information": {
    "DisplayName": "7-Zip 23.01",
    "Description": "7-Zip is a file archiver with a high compression ratio",
    "Publisher": "Igor Pavlov",
    "Notes": "Free and open-source file archiver"
  },
  "ProgramInformation": {
    "InstallCommand": "msiexec /i \"7z2301-x64.msi\" /qn",
    "UninstallCommand": "msiexec /x \"{23170F69-40C1-2702-2301-000001000000}\" /qn",
    "InstallExperience": "system",
    "RestartBehavior": "suppress"
  },
  "RequirementRule": {
    "Architecture": "x64",
    "MinimumSupportedWindowsRelease": "20H2"
  },
  "DetectionRule": {
    "Type": "MSI",
    "ProductCode": "{23170F69-40C1-2702-2301-000001000000}"
  },
  "Assignments": [
    {
      "Target": "AllDevices",
      "Intent": "available",
      "Notification": "showAll"
    }
  ]
}
```

## Using GitHub Releases for Custom Applications

### Step 1: Create a Release for Custom Apps

1. Go to your repository on GitHub
2. Click on "Releases" → "Create a new release"
3. Create a tag (e.g., `custom-apps-latest` or `v1.0.0`)
4. Upload your custom application installers as release assets
5. Publish the release

### Step 2: Reference in appList.json

```json
{
  "IntuneAppName": "Custom Application",
  "AppSource": "GitHubRelease",
  "ReleaseTag": "custom-apps-latest",
  "SetupFile": "CustomApp.msi",
  "AppFolderName": "CustomApp"
}
```

### Benefits of Using GitHub Releases

1. **Free Storage**: Up to 2GB per file
2. **Version Control**: Each release is tagged and versioned
3. **Download Statistics**: Track how often files are downloaded
4. **API Access**: Programmatic access via GitHub API
5. **CDN Distribution**: GitHub uses CDN for fast downloads
6. **No Additional Authentication**: Uses existing GitHub token

## Key Differences from Azure DevOps

### Storage Solution
- **Azure DevOps**: Uses Azure Storage Account for custom apps
- **GitHub Actions**: Uses GitHub Releases for custom apps (free, integrated, version-controlled)

### Authentication
- **Azure DevOps**: Uses Service Connections with Azure
- **GitHub Actions**: Uses Repository Secrets directly

### Pipeline Structure
- **Azure DevOps**: Uses YAML with Azure-specific tasks
- **GitHub Actions**: Uses YAML with Actions-specific syntax

### Artifacts
- **Azure DevOps**: Uses Pipeline Artifacts
- **GitHub Actions**: Uses Actions Artifacts for temporary storage

## Advanced Configuration

### Using Multiple Release Tags
For better version management, use specific release tags:

```json
{
  "Apps": [
    {
      "IntuneAppName": "HR Application",
      "AppSource": "GitHubRelease",
      "ReleaseTag": "hr-app-v2.1.0",
      "SetupFile": "HRApp-2.1.0.msi"
    },
    {
      "IntuneAppName": "Finance Tool",
      "AppSource": "GitHubRelease", 
      "ReleaseTag": "finance-tool-v1.5.0",
      "SetupFile": "FinanceTool.exe"
    }
  ]
}
```

### Environments for Approval Workflows
```yaml
jobs:
  publish_apps:
    environment: production  # Requires approval if configured
    # ... rest of job configuration
```

Configure environment protection rules:
1. Go to Settings → Environments
2. Create "production" environment
3. Add required reviewers
4. Set deployment branches (e.g., only from main)

### Caching for Performance
Add caching to speed up module installation:

```yaml
- name: Cache PowerShell Modules
  uses: actions/cache@v3
  with:
    path: |
      ~\Documents\PowerShell\Modules
      ~\Documents\WindowsPowerShell\Modules
    key: ${{ runner.os }}-posh-${{ hashFiles('**/RequiredModules.psd1') }}
    restore-keys: |
      ${{ runner.os }}-posh-
```

### Matrix Strategy for Multiple Configurations
```yaml
strategy:
  matrix:
    config:
      - { name: "Production", tenant: "prod", tag: "stable" }
      - { name: "Testing", tenant: "test", tag: "beta" }
```

### Using OIDC Authentication (More Secure)
Instead of client secrets, use OIDC:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - name: Azure Login via OIDC
    uses: azure/login@v1
    with:
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      client-id: ${{ secrets.AZURE_CLIENT_ID }}
      allow-no-subscriptions: true
```

## Troubleshooting

### Common Issues

1. **Module Installation Failures**
   - Ensure runner has internet access
   - Check PowerShell execution policy
   - Verify PSGallery is accessible

2. **Authentication Errors**
   - Verify App Registration permissions:
     - `DeviceManagementApps.ReadWrite.All`
     - `DeviceManagementConfiguration.ReadWrite.All`
     - `DeviceManagementRBAC.ReadWrite.All`
   - Check secret expiration dates
   - Ensure correct tenant ID

3. **GitHub Release Download Issues**
   - Verify release tag exists
   - Check file names match exactly
   - Ensure GITHUB_TOKEN has appropriate permissions

4. **IntuneWinAppUtil.exe Errors**
   - Verify .NET Framework 4.7.2+ is installed
   - Check source folder contains setup file
   - Ensure runner has write permissions

### Debug Tips
- Add `-Verbose` to PowerShell commands for detailed output
- Use `Write-Host` statements for debugging
- Check GitHub Actions logs for detailed error messages
- Enable debug logging: Add `ACTIONS_STEP_DEBUG: true` secret

### Testing Individual Components
```powershell
# Test Evergreen module
Get-EvergreenApp -Name "7zip"

# Test GitHub Release access
$headers = @{ Authorization = "token $env:GITHUB_TOKEN" }
Invoke-RestMethod -Uri "https://api.github.com/repos/OWNER/REPO/releases" -Headers $headers

# Test Intune connection
Connect-MSIntuneGraph -TenantID $TenantID -ClientID $ClientID -ClientSecret $ClientSecret
Get-IntuneWin32App
```

## Additional Considerations

### Security Best Practices
1. **App Registration Permissions**: Use least-privilege principle
   - Only grant required Graph API permissions
   - Consider using application permissions vs delegated
2. **Secret Management**:
   - Rotate client secrets regularly (set calendar reminders)
   - Use GitHub's secret scanning features
   - Consider using Azure Key Vault for central secret management
3. **Repository Security**:
   - Enable branch protection on main
   - Require PR reviews for workflow changes
   - Use CODEOWNERS file for sensitive paths
4. **Release Security**:
   - Keep releases private if containing proprietary software
   - Use release signing where possible

### Performance Optimization
1. **Parallel Processing**: Run independent app packaging in parallel
2. **Conditional Execution**: Only process apps that need updates
3. **Artifact Retention**: Set appropriate retention periods
4. **Runner Specifications**: Ensure adequate CPU/RAM for packaging

### Cost Considerations
- **GitHub Actions**: Free for public repos, included minutes for private
- **Self-Hosted Runners**: No GitHub costs, but infrastructure costs
- **GitHub Releases**: Free storage, bandwidth limits apply
- **No Azure Storage costs**: Significant savings for large deployments

### Monitoring and Alerting
1. **Workflow Notifications**:
   ```yaml
   - name: Send Notification on Failure
     if: failure()
     uses: 8398a7/action-slack@v3
     with:
       status: ${{ job.status }}
       text: 'Intune App Factory workflow failed!'
   ```

2. **Status Badges**: Add to README.md
   ```markdown
   ![Intune App Factory](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/publish.yml/badge.svg)
   ```

3. **Workflow Insights**: Use GitHub's built-in analytics

## Next Steps

1. **Initial Setup**
   - Create App Registration in Azure AD
   - Configure required API permissions
   - Set up GitHub repository with proper structure

2. **Test Phase**
   - Start with one or two applications
   - Verify packaging and deployment works
   - Test both Evergreen and GitHub Release sources

3. **Production Rollout**
   - Migrate all applications incrementally
   - Set up monitoring and notifications
   - Document any customizations

4. **Maintenance**
   - Schedule regular secret rotation
   - Review and update app configurations
   - Monitor GitHub Release storage usage

## Example: Complete Setup for Mixed Sources

Here's a practical example with both Evergreen and custom apps:

### appList.json
```json
{
  "Apps": [
    {
      "IntuneAppName": "7-Zip",
      "AppSource": "Evergreen",
      "AppID": "7zip",
      "AppFolderName": "7zip",
      "FilterOptions": [{"Architecture": "x64", "Type": "msi"}]
    },
    {
      "IntuneAppName": "Company Portal Helper",
      "AppSource": "GitHubRelease",
      "ReleaseTag": "portal-helper-v1.0",
      "SetupFile": "PortalHelper.msi",
      "AppFolderName": "PortalHelper"
    },
    {
      "IntuneAppName": "Adobe Reader DC",
      "AppSource": "DirectUrl",
      "DownloadUrl": "https://ardownload2.adobe.com/pub/adobe/reader/win/AcrobatDC/2300120064/AcroRdrDC2300120064_en_US.exe",
      "AppFolderName": "AdobeReader"
    }
  ]
}
```

This configuration demonstrates the flexibility of using GitHub Releases alongside other sources, eliminating the need for Azure Storage Account while maintaining full functionality.

## Resources
- [GitHub Actions Documentation](https://docs.github.com/actions)
- [GitHub Releases API](https://docs.github.com/rest/releases)
- [IntuneWin32App PowerShell Module](https://github.com/MSEndpointMgr/IntuneWin32App)
- [Evergreen PowerShell Module](https://github.com/aaronparker/evergreen)
- [Microsoft Graph API Reference](https://docs.microsoft.com/graph/api/resources/intune-graph-overview)