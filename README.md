# IntuneAppFactory

IntuneAppFactory automates deploying Win32 applications to Microsoft Intune. A single GitHub Actions workflow detects the latest version of each app via [Evergreen](https://stealthpuppy.com/evergreen/) or [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/), downloads it, wraps it in a [PSADT](https://psappdeploytoolkit.com/) package, and publishes it to Intune — no Azure Storage required.

## How It Works

```
appList.json ──► GitHub Actions workflow
                   │
                   ├─ Plan job: reads appList.json, validates configs, builds dynamic matrix
                   │
                   └─ Deploy jobs (parallel, one per app):
                        1. Download installer (Evergreen module or winget, per AppSource)
                        2. Download app icon from CDN (if IconUrl configured)
                        3. Copy PSADT framework into app folder
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

#### Evergreen source

```json
{
    "IntuneAppName": "7-Zip",
    "AppPublisher": "Igor Pavlov",
    "AppSource": "Evergreen",
    "AppID": "7zip",
    "AppFolderName": "7zip",
    "IconUrl": "https://cdn.jsdelivr.net/gh/selfhst/icons/png/7-zip.png",
    "FilterOptions": [
        { "Architecture": "x64", "Type": "msi" }
    ]
}
```

#### Winget source

```json
{
    "IntuneAppName": "7-Zip",
    "AppPublisher": "Igor Pavlov",
    "AppSource": "Winget",
    "AppID": "7zip.7zip",
    "AppFolderName": "7zip",
    "IconUrl": "https://cdn.jsdelivr.net/gh/selfhst/icons/png/7-zip.png",
    "FilterOptions": [
        { "Architecture": "x64", "Type": "msi", "Scope": "machine" }
    ]
}
```

#### `appList.json` Fields

| Field | Description |
|---|---|
| `IntuneAppName` | Display name shown in Intune |
| `AppPublisher` | Publisher name shown in Intune |
| `AppSource` | `Evergreen` or `Winget` — determines how the installer is downloaded |
| `AppID` | Source-specific identifier. Evergreen: run `Find-EvergreenApp`. Winget: run `winget search <name>` |
| `AppFolderName` | Must match the folder name under `Apps/` |
| `IconUrl` | *(Optional)* URL to download an app icon PNG for Company Portal |
| `FilterOptions` | Filter download results — see table below |

#### FilterOptions by Source

| Option | Evergreen | Winget | Example Values |
|---|---|---|---|
| `Architecture` | ✅ | ✅ | `x64`, `x86` |
| `Type` | ✅ | ✅ | `msi`, `exe` |
| `Channel` | ✅ | — | `Stable`, `LATEST_FIREFOX_VERSION` |
| `Language` | ✅ | — | `en-US` |
| `Stream` | ✅ | — | `Current` |
| `Scope` | — | ✅ | `machine`, `user` |

### 2. Create the app folder

```
Apps/
└── 7zip/
    ├── App.json               # Intune app configuration (required)
    ├── Deploy-Application.ps1 # PSADT install/uninstall logic (required)
    ├── Icon.png               # App icon for Company Portal (optional)
    └── Files/                 # Created at runtime — installer downloaded here
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
| **Registry** | `KeyPath`, `ValueName`, `RegistryDetectionType` (`versionComparison`, `stringComparison`, `existence`), `Operator`, `Value` |
| **MSI** | `ProductCode`, `ProductVersionOperator`, `ProductVersion` |
| **Script** | `ScriptFile` (path to a `.ps1` in the app folder) |

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
├── Apps/                            # One subfolder per app (12 included)
│   ├── 7zip/
│   ├── CitrixWorkspace/
│   ├── Git/
│   ├── GoogleChrome/
│   ├── KeePassXC/
│   ├── MicrosoftEdge/
│   ├── MozillaFirefox/
│   ├── NotepadPlusPlus/
│   ├── PuTTY/
│   ├── VLC/
│   ├── VSCode/
│   └── Zoom/
├── Scripts/
│   └── Publish-Win32App.ps1         # Graph API publishing script (zero dependencies)
├── Templates/
│   ├── Application/                 # App.json + PSADT template for new apps
│   └── Framework/Source/            # PSADT framework files (shared)
├── Tests/
│   └── Publish-Win32App.Tests.ps1   # Pester unit tests
├── Tools/
│   └── IntuneWinAppUtil.exe         # Win32 content prep tool
└── appList.json                     # Master app registry
```

## Publish Script

`Scripts/Publish-Win32App.ps1` is a self-contained PowerShell script with no module dependencies. It handles:

- **Authentication** — Client credentials OAuth2 flow via raw REST (no SDK/MSAL dependency)
- **App creation** — Creates or replaces Win32LobApp via Graph API with detection rules, OS requirements, and icons
- **File upload** — Extracts encrypted content from `.intunewin`, uploads via Azure Storage chunked block blobs (6 MB chunks)
- **Assignments** — Configures user/device/group assignments
- **Retry logic** — Exponential backoff for throttled (429) or transient (5xx) Graph API errors

### Local Usage

```powershell
.\Scripts\Publish-Win32App.ps1 `
    -TenantId     "your-tenant-id" `
    -ClientId     "your-client-id" `
    -ClientSecret "your-client-secret" `
    -AppFolder    "Apps/7zip" `
    -IntuneWinPath "output/Deploy-Application.intunewin" `
    -AppVersion   "25.01"
```

## Running Tests

```powershell
# Requires Pester v5+
Invoke-Pester -Path ./Tests -Output Detailed
```

## Included Apps

| App | Source | App ID | Type | Detection | Assignment |
|---|---|---|---|---|---|
| 7-Zip | Evergreen | `7zip` | MSI | File exists (`7z.exe`) | All Users — Available |
| Citrix Workspace | Evergreen | `CitrixWorkspaceApp` | EXE | File exists (`wfica32.exe`) | All Users — Available |
| Git for Windows | Evergreen | `GitForWindows` | EXE | File exists (`git.exe`) | All Users — Available |
| Google Chrome | Evergreen | `GoogleChrome` | MSI | File exists (`chrome.exe`) | All Users — Available |
| KeePassXC | Evergreen | `KeePassXCTeamKeePassXC` | MSI | File exists (`KeePassXC.exe`) | All Users — Available |
| Microsoft Edge | Evergreen | `MicrosoftEdge` | MSI | File exists (`msedge.exe`) | All Users — Available |
| Mozilla Firefox | Evergreen | `MozillaFirefox` | MSI | File exists (`firefox.exe`) | All Users — Available |
| Notepad++ | Evergreen | `NotepadPlusPlus` | EXE | Registry version check | All Users — Available |
| PuTTY | Evergreen | `PuTTY` | MSI | File exists (`putty.exe`) | All Users — Available |
| VLC Media Player | Evergreen | `VideoLanVlcPlayer` | MSI | MSI product code | All Users — Available |
| Visual Studio Code | Evergreen | `MicrosoftVisualStudioCode` | EXE | File exists (`Code.exe`) | All Users — Available |
| Zoom | Evergreen | `Zoom` | MSI | File exists (`Zoom.exe`) | All Users — Available |

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.
