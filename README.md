# IntuneAppFactory

IntuneAppFactory automates deploying Win32 applications to Microsoft Intune. A single GitHub Actions workflow detects the latest version of each app via [Evergreen](https://stealthpuppy.com/evergreen/), downloads it, wraps it in a [PSADT](https://psappdeploytoolkit.com/) package, and publishes it to Intune — no Azure Storage required.

## How It Works

```
appList.json ──► GitHub Actions workflow
                   │
                   ├─ Plan job: builds a matrix entry per app
                   │
                   └─ Deploy jobs (parallel, one per app):
                        1. Install Evergreen module
                        2. Query Evergreen for latest version & download installer
                        3. Wrap in PSADT package folder
                        4. Package with IntuneWinAppUtil.exe → .intunewin
                        5. Publish to Intune via Graph API (Scripts/Publish-Win32App.ps1)
                        6. Upload .intunewin as workflow artifact
```

## Quick Start

### 1. Create an Azure AD App Registration

Register an app in Azure AD with these **Application** permissions:

| Permission | Purpose |
|---|---|
| `DeviceManagementApps.ReadWrite.All` | Create and upload Win32 apps |
| `DeviceManagementConfiguration.ReadWrite.All` | Manage device configurations |
| `Group.Read.All` | Resolve group-based assignments |

Grant admin consent after adding permissions.

### 2. Configure GitHub Secrets

In your repository, go to **Settings → Secrets and variables → Actions** and add:

| Secret | Value |
|---|---|
| `TENANT_ID` | Azure AD Tenant ID |
| `CLIENT_ID` | App Registration Client ID |
| `CLIENT_SECRET` | App Registration Client Secret |

### 3. Run the Workflow

Go to **Actions → Deploy Win32 Apps to Intune → Run workflow**.

- Leave the `apps` input blank to deploy all apps in `appList.json`
- Enter comma-separated folder names (e.g. `7zip,VLC`) to deploy specific apps

## Adding a New App

### 1. Add an entry to `appList.json`

```json
{
    "IntuneAppName": "7-Zip",
    "AppPublisher": "Igor Pavlov",
    "AppSource": "Evergreen",
    "AppID": "7zip",
    "AppFolderName": "7zip",
    "FilterOptions": [
        { "Architecture": "x64", "Type": "msi" }
    ]
}
```

| Field | Description |
|---|---|
| `IntuneAppName` | Display name shown in Intune |
| `AppID` | Evergreen app identifier (run `Find-EvergreenApp` to discover IDs) |
| `AppFolderName` | Must match the folder name under `Apps/` |
| `FilterOptions` | Filter Evergreen results by architecture and installer type |

### 2. Create the app folder

```
Apps/
└── 7zip/
    ├── App.json          # App configuration (required)
    ├── Deploy-Application.ps1   # PSADT install/uninstall logic (required)
    ├── Icon.png          # App icon for Company Portal (optional)
    └── Files/            # Created at runtime — installer downloaded here
```

### 3. Configure `App.json`

```json
{
  "PackageInformation": {
    "SetupType": "MSI",
    "SetupFile": "Deploy-Application.exe",
    "IconFile": "Icon.png"
  },
  "Information": {
    "DisplayName": "7-Zip",
    "Description": "7-Zip is a file archiver with a high compression ratio",
    "Publisher": "Igor Pavlov"
  },
  "Program": {
    "InstallCommand": "Deploy-Application.exe install",
    "UninstallCommand": "Deploy-Application.exe uninstall",
    "InstallExperience": "system",
    "DeviceRestartBehavior": "suppress"
  },
  "RequirementRule": {
    "MinimumRequiredOperatingSystem": "W10_22H2",
    "Architecture": "x64"
  },
  "DetectionRule": [
    {
      "DetectionType": "File",
      "Path": "C:\\Program Files\\7-Zip",
      "FileOrFolderName": "7z.exe",
      "FileDetectionType": "exists"
    }
  ],
  "Assignment": [
    { "Target": "AllUsers", "Intent": "available", "Notification": "showAll" }
  ]
}
```

#### Detection Rule Types

| Type | Key Fields |
|---|---|
| **File** | `Path`, `FileOrFolderName`, `FileDetectionType` (`exists`, `version`, `dateModified`, `sizeInMB`) |
| **Registry** | `KeyPath`, `ValueName`, `DetectionType` (`exists`, `string`, `integer`, `version`) |
| **MSI** | `ProductCode` (auto-extracted from MSI at packaging time) |

#### Assignment Targets

| Target | Behavior |
|---|---|
| `AllUsers` | Deploy to all licensed users |
| `AllDevices` | Deploy to all devices |
| Group name | Requires `GroupID` field with the Azure AD group ID |

### 4. Write `Deploy-Application.ps1`

Use the standard PSADT template. The key sections are the `Install` and `Uninstall` blocks — the framework files are copied from `Templates/Framework/Source` at build time.

## Repository Structure

```
├── .github/workflows/publish.yml   # GitHub Actions workflow
├── Apps/                            # One subfolder per app
│   ├── 7zip/
│   ├── NotepadPlusPlus/
│   └── VLC/
├── Scripts/
│   └── Publish-Win32App.ps1         # Graph API publishing script (zero dependencies)
├── Templates/Framework/Source/      # PSADT framework files (shared)
├── Tests/
│   └── Publish-Win32App.Tests.ps1   # Pester tests
└── appList.json                     # Master app registry
```

## Publish Script

`Scripts/Publish-Win32App.ps1` is a self-contained PowerShell script with no module dependencies. It handles:

- **Authentication** — Client credentials OAuth2 flow via MSAL
- **App creation** — Creates Win32LobApp via Graph API with detection rules, OS requirements, and icons
- **File upload** — Extracts encrypted content from `.intunewin`, uploads via Azure Storage chunked block blobs
- **Assignments** — Configures user/device/group assignments
- **Retry logic** — Exponential backoff for throttled or transient Graph API errors

### Local Usage

```powershell
.\Scripts\Publish-Win32App.ps1 `
    -TenantId     "your-tenant-id" `
    -ClientId     "your-client-id" `
    -ClientSecret "your-client-secret" `
    -AppFolder    "Apps/7zip" `
    -IntuneWinPath "output/Deploy-Application.intunewin" `
    -AppVersion   "24.09"
```

## Running Tests

```powershell
# Requires Pester v5+
Invoke-Pester -Path ./Tests -Output Detailed
```

## Included Apps

| App | Evergreen ID | Detection | Assignment |
|---|---|---|---|
| 7-Zip | `7zip` | File exists (`7z.exe`) | All Users — Available |
| Notepad++ | `NotepadPlusPlus` | Registry version check | All Users — Available |
| VLC | `VideoLanVlcPlayer` | MSI product code | All Users — Available |

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.
