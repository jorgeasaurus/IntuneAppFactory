# Migration to Microsoft Graph SDK - Summary

This document summarizes the migration from the deprecated IntuneWin32App module to the Microsoft Graph SDK for the IntuneAppFactory project.

## Overview

The IntuneAppFactory has been successfully migrated to use Microsoft Graph SDK instead of the legacy IntuneWin32App module. This ensures continued compatibility and support as Microsoft transitions to modern authentication methods.

## Files Created/Modified

### New PowerShell Scripts (Graph SDK Versions)

1. **`Scripts/New-Win32App-GraphSDK.ps1`**
   - Replaces: `Scripts/New-Win32App.ps1`
   - Purpose: Creates and publishes Win32 applications to Intune using Graph SDK
   - Key changes:
     - Uses `Connect-MgGraph` instead of `Connect-MSIntuneGraph`
     - Uses `New-MgDeviceAppManagementMobileApp` instead of `Add-IntuneWin32App`
     - Implements Graph API object structures for app creation

2. **`Scripts/New-AppAssignment-GraphSDK.ps1`**
   - Replaces: `Scripts/New-AppAssignment.ps1`
   - Purpose: Creates app assignments using Graph SDK
   - Key changes:
     - Uses `New-MgDeviceAppManagementMobileAppAssignment` instead of `Add-IntuneWin32AppAssignment*` cmdlets
     - Implements proper Graph API assignment target types

3. **`Scripts/Install-Modules-GraphSDK.ps1`**
   - Replaces: `Scripts/Install-Modules.ps1`
   - Purpose: Installs required PowerShell modules
   - Key changes:
     - Removes `IntuneWin32App` module
     - Adds Microsoft Graph SDK modules:
       - `Microsoft.Graph.Authentication`
       - `Microsoft.Graph.DeviceManagement`
       - `Microsoft.Graph.DeviceManagement.Actions`
       - `Microsoft.Graph.Groups`

### New GitHub Actions Workflow

4. **`.github/workflows/publish-graph-sdk.yml`**
   - Purpose: Complete GitHub Actions workflow using Graph SDK
   - Features:
     - Multi-phase pipeline (Test → Check → Package → Publish → Assign)
     - Parallel processing for application packaging
     - Uses new Graph SDK scripts throughout
     - Proper artifact handling between jobs

### Existing Files (Already Using Graph SDK)

- **`Scripts/Connect-GraphAPI.ps1`** - Already implemented with Graph SDK
- **`Scripts/Migrate-ToGraphSDK.ps1`** - Migration guide and helper functions
- **`.github/workflows/publish-v2.yml`** - Partial Graph SDK implementation (mixed approach)

## Key Migration Changes

### Authentication
**Old Method:**
```powershell
Connect-MSIntuneGraph -TenantID $TenantID -ClientID $ClientID -ClientSecret $ClientSecret
```

**New Method:**
```powershell
$SecureClientSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
$ClientSecretCredential = [PSCredential]::new($ClientID, $SecureClientSecret)
Connect-MgGraph -TenantId $TenantID -ClientSecretCredential $ClientSecretCredential -NoWelcome
```

### Module Dependencies
**Removed:**
- IntuneWin32App
- MSGraphRequest
- MSAL.PS (implicit dependency)

**Added:**
- Microsoft.Graph.Authentication
- Microsoft.Graph.DeviceManagement
- Microsoft.Graph.DeviceManagement.Actions
- Microsoft.Graph.Groups

### API Command Mappings
| Old Command | New Command |
|-------------|-------------|
| `Add-IntuneWin32App` | `New-MgDeviceAppManagementMobileApp` |
| `Get-IntuneWin32App` | `Get-MgDeviceAppManagementMobileApp -Filter "isof('microsoft.graph.win32LobApp')"` |
| `Add-IntuneWin32AppAssignmentGroup` | `New-MgDeviceAppManagementMobileAppAssignment` |
| `Add-IntuneWin32AppAssignmentAllDevices` | `New-MgDeviceAppManagementMobileAppAssignment` (with allDevicesAssignmentTarget) |
| `Add-IntuneWin32AppAssignmentAllUsers` | `New-MgDeviceAppManagementMobileAppAssignment` (with allLicensedUsersAssignmentTarget) |

## Important Notes

### File Upload Limitation
The Microsoft Graph SDK doesn't directly support .intunewin file uploads. The current implementation includes placeholders for this functionality. Full file upload requires:
1. Creating the app with `committedContentVersion`
2. Creating file upload sessions
3. Uploading file chunks
4. Committing the file

### Object Structure Changes
Graph API uses different object structures than the IntuneWin32App module:
- Detection rules require specific `@odata.type` properties
- Requirement rules have different property names
- Assignment targets use typed objects instead of parameters

### Testing Required
Before using in production:
1. Test authentication with your Azure AD app registration
2. Verify all Graph API permissions are granted
3. Test with a single application first
4. Monitor for any API changes or deprecations

## Next Steps

1. **Update Azure DevOps Pipeline**: Modify `publish.yml` to use new Graph SDK scripts
2. **Test GitHub Actions Workflow**: Run the new workflow with test applications
3. **Update Documentation**: Update README.md and other docs to reflect Graph SDK usage
4. **Remove Legacy Scripts**: Once verified, remove old IntuneWin32App-based scripts
5. **Monitor API Changes**: Stay updated with Microsoft Graph SDK releases

## Required Azure AD Permissions

Ensure your app registration has these Microsoft Graph API permissions:
- `DeviceManagementApps.ReadWrite.All`
- `DeviceManagementConfiguration.ReadWrite.All`
- `DeviceManagementRBAC.ReadWrite.All`
- `Group.Read.All` (if using group assignments)

## Troubleshooting

Common issues and solutions:
1. **Authentication failures**: Verify client secret hasn't expired
2. **Permission errors**: Check Graph API permissions in Azure AD
3. **Module conflicts**: Uninstall old modules before installing Graph SDK
4. **API limitations**: Some features may require direct API calls using `Invoke-MgGraphRequest`