<#
.SYNOPSIS
    Publishes a Win32 app (.intunewin) to Microsoft Intune via raw Graph REST API.
.DESCRIPTION
    Self-contained script with zero module dependencies. Handles authentication,
    app creation/update, .intunewin file upload, and group assignments.
.PARAMETER TenantId
    Azure AD tenant ID.
.PARAMETER ClientId
    App registration client ID.
.PARAMETER ClientSecret
    App registration client secret.
.PARAMETER AppFolder
    Path to the app folder containing App.json.
.PARAMETER IntuneWinPath
    Path to the .intunewin file to upload.
.EXAMPLE
    .\Publish-Win32App.ps1 -TenantId $tid -ClientId $cid -ClientSecret $cs `
        -AppFolder "Apps\7Zip" -IntuneWinPath "output\Deploy-Application.intunewin"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $TenantId,
    [Parameter(Mandatory)] [string] $ClientId,
    [Parameter(Mandatory)] [string] $ClientSecret,
    [Parameter(Mandatory)] [string] $AppFolder,
    [Parameter(Mandatory)] [string] $IntuneWinPath,
    [string] $AppVersion
)

$ErrorActionPreference = 'Stop'
$script:GraphBase = 'https://graph.microsoft.com/beta'

#region Helper Functions

function Get-GraphToken {
    param([string] $TenantId, [string] $ClientId, [string] $ClientSecret)

    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = 'https://graph.microsoft.com/.default'
    }
    $uri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    try {
        return (Invoke-RestMethod -Method POST -Uri $uri -Body $body -ContentType 'application/x-www-form-urlencoded').access_token
    }
    catch {
        $msg = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        $hint = switch ($msg.error) {
            'invalid_client'      { 'Check CLIENT_SECRET — use the secret value, not the secret ID. It may also be expired.' }
            'unauthorized_client' { 'Check CLIENT_ID and verify the app registration has the correct API permissions.' }
            'invalid_request'     { 'Check TENANT_ID format (must be a GUID).' }
            default               { $msg.error_description ?? $_.Exception.Message }
        }
        throw "Authentication failed: $hint"
    }
}

function Invoke-Graph {
    param(
        [hashtable] $Headers,
        [string] $Method = 'GET',
        [string] $Uri,
        [object] $Body,
        [int] $MaxRetries = 3
    )

    $params = @{ Method = $Method; Uri = $Uri; Headers = $Headers; ContentType = 'application/json' }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10) }

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            return Invoke-RestMethod @params
        }
        catch {
            $status = $_.Exception.Response.StatusCode.value__
            $retryable = $status -in @(429, 500, 502, 503, 504)
            if (-not $retryable -or $attempt -eq $MaxRetries) { throw }

            $delay = [math]::Pow(2, $attempt)
            Write-Host "    Graph API returned $status — retrying in ${delay}s (attempt $attempt/$MaxRetries)"
            Start-Sleep -Seconds $delay
        }
    }
}

function Get-IntuneWinMetadata {
    param([string] $IntuneWinPath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($IntuneWinPath)
    try {
        $metaEntry = $zip.Entries | Where-Object { $_.FullName -match 'Detection\.xml$' } | Select-Object -First 1
        if (-not $metaEntry) { throw "No Detection.xml found in $IntuneWinPath" }

        $stream = $metaEntry.Open()
        $reader = [System.IO.StreamReader]::new($stream)
        [xml]$xml = $reader.ReadToEnd()
        $reader.Dispose()

        $enc = $xml.ApplicationInfo.EncryptionInfo
        return @{
            FileName            = $xml.ApplicationInfo.FileName
            SetupFile           = $xml.ApplicationInfo.SetupFile
            UnencryptedSize     = [int64]$xml.ApplicationInfo.UnencryptedContentSize
            EncryptionKey       = $enc.EncryptionKey
            MacKey              = $enc.MacKey
            InitializationVector = $enc.InitializationVector
            Mac                 = $enc.Mac
            ProfileIdentifier   = $enc.ProfileIdentifier
            FileDigest          = $enc.FileDigest
            FileDigestAlgorithm = $enc.FileDigestAlgorithm
        }
    }
    finally { $zip.Dispose() }
}

function ConvertTo-BoolFromString ([string] $Value) {
    return ($Value -eq 'true')
}

function Build-SingleDetectionRule {
    param([object] $Rule, [string] $AppFolder)

    $type = $Rule.DetectionType ?? $Rule.Type

    switch ($type) {
        'MSI' {
            return @{
                '@odata.type'          = '#microsoft.graph.win32LobAppProductCodeRule'
                ruleType               = 'detection'
                productCode            = $Rule.ProductCode
                productVersionOperator = $Rule.ProductVersionOperator ?? 'notConfigured'
                productVersion         = $Rule.ProductVersion ?? ''
            }
        }
        'Registry' {
            $method = ($Rule.RegistryDetectionType ?? $Rule.DetectionMethod ?? 'existence').ToLower()
            $regRule = @{
                '@odata.type'        = '#microsoft.graph.win32LobAppRegistryRule'
                ruleType             = 'detection'
                keyPath              = $Rule.KeyPath
                valueName            = $Rule.ValueName
                check32BitOn64System = ConvertTo-BoolFromString ($Rule.Check32BitOn64System ?? $Rule.check32BitOn64System)
            }
            $operationMap = @{
                'versioncomparison' = @{ operationType = 'version'; operator = $Rule.Operator ?? 'greaterThanOrEqual'; comparisonValue = $Rule.Value ?? '' }
                'stringcomparison'  = @{ operationType = 'string';  operator = $Rule.Operator ?? 'equal';              comparisonValue = $Rule.Value ?? '' }
                'integercomparison' = @{ operationType = 'integer'; operator = $Rule.Operator ?? 'greaterThanOrEqual'; comparisonValue = $Rule.Value ?? '' }
            }
            $mapped = $operationMap[$method]
            if ($mapped) { $regRule += $mapped }
            else         { $regRule += @{ operationType = 'exists'; operator = 'notConfigured' } }
            return $regRule
        }
        'File' {
            $method = ($Rule.FileDetectionType ?? $Rule.DetectionMethod ?? 'exists').ToLower()
            $fileRule = @{
                '@odata.type'        = '#microsoft.graph.win32LobAppFileSystemRule'
                ruleType             = 'detection'
                path                 = $Rule.Path
                fileOrFolderName     = $Rule.FileOrFolderName ?? $Rule.FileOrFolder
                check32BitOn64System = ConvertTo-BoolFromString ($Rule.Check32BitOn64System ?? $Rule.check32BitOn64System)
                operationType        = $method
                operator             = $Rule.Operator ?? 'notConfigured'
            }
            if ($method -eq 'version') {
                $fileRule.comparisonValue = $Rule.VersionValue ?? $Rule.Value ?? ''
                $fileRule.operator = $Rule.Operator ?? 'greaterThanOrEqual'
            }
            return $fileRule
        }
        'Script' {
            $scriptPath = Join-Path $AppFolder $Rule.ScriptFile
            return @{
                '@odata.type'         = '#microsoft.graph.win32LobAppPowerShellScriptRule'
                ruleType              = 'detection'
                scriptContent         = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((Get-Content -Raw -Path $scriptPath)))
                enforceSignatureCheck = ConvertTo-BoolFromString $Rule.EnforceSignatureCheck
                runAs32Bit            = ConvertTo-BoolFromString $Rule.RunAs32Bit
            }
        }
        default { throw "Unsupported detection rule type: $type" }
    }
}

function Build-DetectionRules {
    param([array] $Rules, [string] $AppFolder)
    return @($Rules | ForEach-Object { Build-SingleDetectionRule -Rule $_ -AppFolder $AppFolder })
}

function Build-OsRequirement {
    param([string] $MinOs)

    # Valid Graph API windowsMinimumOperatingSystem properties (queried from live API)
    # Note: v10_2H20 not v10_20H2, and v10_21H1 is the ceiling
    $map = @{
        'W10_1607' = 'v10_1607'; 'W10_1703' = 'v10_1703'; 'W10_1709' = 'v10_1709'
        'W10_1803' = 'v10_1803'; 'W10_1809' = 'v10_1809'; 'W10_1903' = 'v10_1903'
        'W10_1909' = 'v10_1909'; 'W10_2004' = 'v10_2004'; 'W10_20H2' = 'v10_2H20'
        'W10_21H1' = 'v10_21H1'; 'W10_21H2' = 'v10_21H1'; 'W10_22H2' = 'v10_21H1'
        'W11_21H2' = 'v10_21H1'; 'W11_22H2' = 'v10_21H1'; 'W11_23H2' = 'v10_21H1'
        'W11_24H2' = 'v10_21H1'
    }
    return $map[$MinOs] ?? 'v10_1607'
}

function Build-AppPayload {
    param([hashtable] $Config, [array] $DetectionRules, [string] $IconBase64, [string] $SetupFileName, [string] $IntuneWinFileName)

    $info = $Config.Information
    $prog = $Config.Program
    $req  = $Config.RequirementRule
    $osKey = Build-OsRequirement ($req.MinimumSupportedWindowsRelease ?? $req.MinimumRequiredOperatingSystem ?? 'W10_22H2')

    $payload = @{
        '@odata.type'                   = '#microsoft.graph.win32LobApp'
        displayName                     = $info.DisplayName
        description                     = $info.Description ?? ''
        publisher                       = $info.Publisher ?? ''
        developer                       = $info.Developer ?? ''
        informationUrl                  = $info.InformationURL ?? $null
        privacyInformationUrl           = $info.PrivacyURL ?? $null
        notes                           = $info.Notes ?? ''
        fileName                        = $IntuneWinFileName
        setupFilePath                   = $SetupFileName
        installCommandLine              = $prog.InstallCommand
        uninstallCommandLine            = $prog.UninstallCommand
        installExperience               = @{ runAsAccount = $prog.InstallExperience ?? 'system' }
        returnCodes                     = @(
            @{ returnCode = 0;    type = 'success' }
            @{ returnCode = 1707; type = 'success' }
            @{ returnCode = 3010; type = 'softReboot' }
            @{ returnCode = 1641; type = 'hardReboot' }
            @{ returnCode = 1618; type = 'retry' }
        )
        rules                           = $DetectionRules
        minimumSupportedOperatingSystem = @{ $osKey = $true }
    }

    if ($prog.DeviceRestartBehavior) {
        $payload.deviceRestartBehavior = $prog.DeviceRestartBehavior
    }

    if ($IconBase64) {
        $payload.largeIcon = @{
            '@odata.type' = '#microsoft.graph.mimeContent'
            type          = 'image/png'
            value         = $IconBase64
        }
    }

    return $payload
}

function Resolve-IconBase64 {
    param([string] $AppFolder, [string] $IconRef)

    $iconPath = if ($IconRef -match '^https?://') {
        $tempIcon = Join-Path ([System.IO.Path]::GetTempPath()) 'icon.png'
        Invoke-WebRequest -Uri $IconRef -OutFile $tempIcon -UseBasicParsing
        $tempIcon
    } else {
        Join-Path $AppFolder ($IconRef ?? 'Icon.png')
    }

    if (-not $iconPath -or -not (Test-Path $iconPath)) { return $null }

    $bytes = [System.IO.File]::ReadAllBytes($iconPath)
    # Detect if file is base64 text (not binary PNG) — avoid double-encoding
    if ($bytes[0] -ne 0x89 -and $bytes.Length -lt 500000) {
        $text = [System.Text.Encoding]::ASCII.GetString($bytes).Trim()
        if ($text -match '^[A-Za-z0-9+/=]+$') { return $text }
    }
    return [Convert]::ToBase64String($bytes)
}

function Find-ExistingApp {
    param([hashtable] $Headers, [string] $DisplayName)

    $escapedName = $DisplayName.Replace("'", "''")
    $filter = "isof('microsoft.graph.win32LobApp') and displayName eq '$escapedName'"
    $uri = "$script:GraphBase/deviceAppManagement/mobileApps?`$filter=$([uri]::EscapeDataString($filter))"
    return (Invoke-Graph -Headers $Headers -Uri $uri).value | Select-Object -First 1
}

function New-OrUpdateApp {
    param([hashtable] $Headers, [hashtable] $Payload)

    $existing = Find-ExistingApp -Headers $Headers -DisplayName $Payload.displayName
    if ($existing) {
        Write-Host "  Updating existing app: $($existing.id)"
        Invoke-Graph -Headers $Headers -Method PATCH `
            -Uri "$script:GraphBase/deviceAppManagement/mobileApps/$($existing.id)" `
            -Body $Payload | Out-Null
        return $existing.id
    }

    Write-Host "  Creating new app..."
    $created = Invoke-Graph -Headers $Headers -Method POST `
        -Uri "$script:GraphBase/deviceAppManagement/mobileApps" `
        -Body $Payload
    return $created.id
}

function Wait-ForFileState {
    param(
        [hashtable] $Headers, [string] $AppId, [string] $ContentVersionId,
        [string] $FileId, [string] $DesiredState, [int] $MaxWait = 120
    )

    $uri = "$script:GraphBase/deviceAppManagement/mobileApps/$AppId/microsoft.graph.win32LobApp/contentVersions/$ContentVersionId/files/$FileId"
    for ($elapsed = 0; $elapsed -lt $MaxWait; $elapsed += 5) {
        Start-Sleep -Seconds 5
        $file = Invoke-Graph -Headers $Headers -Uri $uri
        Write-Host "    File state: $($file.uploadState) (waited $($elapsed + 5)s)"
        if ($file.uploadState -eq $DesiredState) { return $file }
        if ($file.uploadState -eq 'commitFileFailed') { throw "File commit failed for file $FileId" }
    }
    throw "Timed out waiting for file state '$DesiredState' (waited ${MaxWait}s)"
}

function Send-FileContent {
    param([string] $FilePath, [string] $UploadUri)

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    Write-Host "    Uploading file ($($bytes.Length) bytes)..."
    Invoke-WebRequest -Method PUT -Uri $UploadUri -Body $bytes `
        -Headers @{ 'x-ms-blob-type' = 'BlockBlob'; 'Content-Type' = 'application/octet-stream' } | Out-Null
    Write-Host "    Upload complete."
}

function Upload-IntuneWinFile {
    param([hashtable] $Headers, [string] $AppId, [string] $IntuneWinPath, [hashtable] $Metadata)

    $cvUri = "$script:GraphBase/deviceAppManagement/mobileApps/$AppId/microsoft.graph.win32LobApp/contentVersions"

    Write-Host "  Creating content version..."
    $cvId = (Invoke-Graph -Headers $Headers -Method POST -Uri $cvUri -Body @{}).id

    $fileSize = (Get-Item $IntuneWinPath).Length
    Write-Host "  Registering file (size: $fileSize bytes)..."
    $regBody = @{
        '@odata.type' = '#microsoft.graph.mobileAppContentFile'
        name          = [System.IO.Path]::GetFileName($IntuneWinPath)
        size          = [int64]$Metadata.UnencryptedSize
        sizeEncrypted = [int64]$fileSize
        manifest      = $null
        isDependency  = $false
    }
    $fileId = (Invoke-Graph -Headers $Headers -Method POST -Uri "$cvUri/$cvId/files" -Body $regBody).id

    Write-Host "  Waiting for Azure Storage URI..."
    $fileInfo = Wait-ForFileState -Headers $Headers -AppId $AppId -ContentVersionId $cvId `
        -FileId $fileId -DesiredState 'azureStorageUriRequestSuccess'

    Send-FileContent -FilePath $IntuneWinPath -UploadUri $fileInfo.azureStorageUri

    Write-Host "  Committing file with encryption info..."
    $commitBody = @{
        fileEncryptionInfo = @{
            encryptionKey        = $Metadata.EncryptionKey
            macKey               = $Metadata.MacKey
            initializationVector = $Metadata.InitializationVector
            mac                  = $Metadata.Mac
            profileIdentifier    = $Metadata.ProfileIdentifier
            fileDigest           = $Metadata.FileDigest
            fileDigestAlgorithm  = $Metadata.FileDigestAlgorithm
        }
    }
    Invoke-Graph -Headers $Headers -Method POST -Uri "$cvUri/$cvId/files/$fileId/commit" -Body $commitBody | Out-Null

    Write-Host "  Waiting for commit to complete..."
    Wait-ForFileState -Headers $Headers -AppId $AppId -ContentVersionId $cvId `
        -FileId $fileId -DesiredState 'commitFileSuccess' -MaxWait 180 | Out-Null

    Write-Host "  Setting committed content version..."
    Invoke-Graph -Headers $Headers -Method PATCH `
        -Uri "$script:GraphBase/deviceAppManagement/mobileApps/$AppId" `
        -Body @{ '@odata.type' = '#microsoft.graph.win32LobApp'; committedContentVersion = $cvId } | Out-Null

    return $cvId
}

function Resolve-AssignmentTarget {
    param([object] $Assignment)

    $target = $Assignment.Target ?? $Assignment.GroupName
    switch ($target) {
        'AllUsers'   { return @{ '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget' } }
        'AllDevices' { return @{ '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget' } }
        default {
            if ($Assignment.GroupID) {
                return @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $Assignment.GroupID }
            }
            Write-Warning "No GroupID for target '$target' — defaulting to AllUsers"
            return @{ '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget' }
        }
    }
}

function Set-AppAssignments {
    param([hashtable] $Headers, [string] $AppId, [array] $Assignments)

    if (-not $Assignments -or $Assignments.Count -eq 0) { return }

    $graphAssignments = @($Assignments | ForEach-Object {
        @{
            '@odata.type' = '#microsoft.graph.mobileAppAssignment'
            intent        = ($_.Intent ?? 'available').ToLower()
            target        = (Resolve-AssignmentTarget $_)
            settings      = @{
                '@odata.type'                = '#microsoft.graph.win32LobAppAssignmentSettings'
                notifications                = $_.Notification ?? 'showAll'
                deliveryOptimizationPriority = $_.DeliveryOptimizationPriority ?? 'notConfigured'
                restartSettings              = $null
                installTimeSettings          = $null
            }
        }
    })

    Write-Host "  Assigning app to $($graphAssignments.Count) target(s)..."
    Invoke-Graph -Headers $Headers -Method POST `
        -Uri "$script:GraphBase/deviceAppManagement/mobileApps/$AppId/assign" `
        -Body @{ mobileAppAssignments = $graphAssignments } | Out-Null
}

#endregion

#region Main

Write-Host "`n=== Intune Win32 App Publisher ===" -ForegroundColor Cyan
Write-Host "App folder: $AppFolder"
Write-Host "Package:    $IntuneWinPath`n"

$appJsonPath = Join-Path $AppFolder 'App.json'
if (-not (Test-Path $appJsonPath)) { throw "App.json not found at $appJsonPath" }
$config = Get-Content -Raw $appJsonPath | ConvertFrom-Json -AsHashtable

if ($AppVersion) {
    $config.Information.AppVersion = $AppVersion
    $config.Information.DisplayName = "$($config.Information.DisplayName) $AppVersion"
}
Write-Host "[1/5] Loaded App.json: $($config.Information.DisplayName)"

Write-Host "[2/5] Authenticating..."
$token = Get-GraphToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
$headers = @{ Authorization = "Bearer $token" }
Write-Host "  Token acquired."

Write-Host "[3/5] Creating/updating app..."
$metadata = Get-IntuneWinMetadata -IntuneWinPath $IntuneWinPath
$detectionRules = Build-DetectionRules -Rules $config.DetectionRule -AppFolder $AppFolder
$iconBase64 = Resolve-IconBase64 -AppFolder $AppFolder -IconRef ($config.PackageInformation.IconFile ?? $config.PackageInformation.IconURL)
$setupFileName = $config.PackageInformation.SetupFile ?? $metadata.SetupFile ?? 'Deploy-Application.exe'
$intuneWinFileName = $metadata.FileName ?? (Split-Path $IntuneWinPath -Leaf)
$payload = Build-AppPayload -Config $config -DetectionRules $detectionRules -IconBase64 $iconBase64 -SetupFileName $setupFileName -IntuneWinFileName $intuneWinFileName
$appId = New-OrUpdateApp -Headers $headers -Payload $payload
Write-Host "  App ID: $appId"

Write-Host "[4/5] Uploading package..."
Upload-IntuneWinFile -Headers $headers -AppId $appId -IntuneWinPath $IntuneWinPath -Metadata $metadata | Out-Null
Write-Host "  Upload complete."

Write-Host "[5/5] Configuring assignments..."
Set-AppAssignments -Headers $headers -AppId $appId -Assignments $config.Assignment
Write-Host "`nDone! App '$($config.Information.DisplayName)' published to Intune (ID: $appId)" -ForegroundColor Green

#endregion
