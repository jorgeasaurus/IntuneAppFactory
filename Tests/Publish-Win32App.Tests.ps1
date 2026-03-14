<#
.SYNOPSIS
    Pester tests for Publish-Win32App.ps1 helper functions.
.DESCRIPTION
    Unit tests covering detection rules, OS mapping, payload construction,
    icon resolution, assignment targeting, and version passthrough.
    All Graph/network calls are mocked — no live API needed.
#>

BeforeAll {
    # Dot-source the script to load functions without executing Main
    # We need to supply mandatory params, then mock everything the Main region calls.
    $script:GraphBase = 'https://graph.microsoft.com/beta'

    # Extract just the function definitions from the script
    $scriptPath = Join-Path $PSScriptRoot '..' 'Scripts' 'Publish-Win32App.ps1'
    $scriptContent = Get-Content -Raw $scriptPath

    # Pull the functions region only (between #region Helper Functions and #endregion)
    $functionsBlock = [regex]::Match($scriptContent, '(?s)#region Helper Functions(.+?)#endregion').Groups[1].Value
    if (-not $functionsBlock) { throw 'Could not extract functions from Publish-Win32App.ps1' }

    # Execute the function definitions in current scope
    Invoke-Expression $functionsBlock
}

Describe 'ConvertTo-BoolFromString' {
    It 'returns $true for "true"' {
        ConvertTo-BoolFromString 'true' | Should -Be $true
    }
    It 'returns $false for "false"' {
        ConvertTo-BoolFromString 'false' | Should -Be $false
    }
    It 'returns $false for empty string' {
        ConvertTo-BoolFromString '' | Should -Be $false
    }
    It 'returns $false for null' {
        ConvertTo-BoolFromString $null | Should -Be $false
    }
    It 'is case-insensitive (True == true in PowerShell)' {
        ConvertTo-BoolFromString 'True' | Should -Be $true
    }
}

Describe 'Build-OsRequirement' {
    It 'maps W10_22H2 to highest valid Graph API property v10_21H1' {
        Build-OsRequirement 'W10_22H2' | Should -Be 'v10_21H1'
    }
    It 'maps W11_24H2 to v10_21H1 (Graph API ceiling)' {
        Build-OsRequirement 'W11_24H2' | Should -Be 'v10_21H1'
    }
    It 'returns default v10_1607 for unknown input' {
        Build-OsRequirement 'UNKNOWN' | Should -Be 'v10_1607'
    }
    It 'returns default v10_1607 for empty string' {
        Build-OsRequirement '' | Should -Be 'v10_1607'
    }
    It 'maps all supported Windows 10 versions to v10_ prefixed values' {
        $w10Versions = @('W10_1607','W10_1703','W10_1709','W10_1809','W10_1903','W10_1909','W10_2004','W10_20H2','W10_21H1','W10_21H2','W10_22H2')
        foreach ($v in $w10Versions) {
            $result = Build-OsRequirement $v
            $result | Should -Match '^v10_' -Because "$v should map to a v10_ value"
        }
    }
    It 'maps W10_20H2 to v10_2H20 (Graph API uses swapped format)' {
        Build-OsRequirement 'W10_20H2' | Should -Be 'v10_2H20'
    }
    It 'maps all Windows 11 versions to v10_21H1 (Graph API ceiling)' {
        $w11Versions = @('W11_21H2','W11_22H2','W11_23H2','W11_24H2')
        foreach ($v in $w11Versions) {
            $result = Build-OsRequirement $v
            $result | Should -Be 'v10_21H1' -Because "$v should map to Graph API ceiling v10_21H1"
        }
    }
}

Describe 'Build-SingleDetectionRule' {
    Context 'MSI detection' {
        It 'builds MSI rule with product code' {
            $rule = [PSCustomObject]@{
                DetectionType          = 'MSI'
                ProductCode            = '{12345-ABCDE}'
                ProductVersionOperator = 'greaterThanOrEqual'
                ProductVersion         = '1.0.0'
            }
            $result = Build-SingleDetectionRule -Rule $rule -AppFolder 'test'
            $result.'@odata.type' | Should -Be '#microsoft.graph.win32LobAppProductCodeRule'
            $result.ruleType | Should -Be 'detection'
            $result.productCode | Should -Be '{12345-ABCDE}'
            $result.productVersionOperator | Should -Be 'greaterThanOrEqual'
            $result.productVersion | Should -Be '1.0.0'
        }
        It 'defaults productVersionOperator to notConfigured' {
            $rule = [PSCustomObject]@{ DetectionType = 'MSI'; ProductCode = '{X}' }
            $result = Build-SingleDetectionRule -Rule $rule -AppFolder 'test'
            $result.productVersionOperator | Should -Be 'notConfigured'
        }
    }

    Context 'Registry detection' {
        It 'builds version comparison rule' {
            $rule = [PSCustomObject]@{
                DetectionType          = 'Registry'
                RegistryDetectionType  = 'versionComparison'
                KeyPath                = 'HKLM\SOFTWARE\Test'
                ValueName              = 'DisplayVersion'
                Operator               = 'greaterThanOrEqual'
                Value                  = '2.0'
                Check32BitOn64System   = 'true'
            }
            $result = Build-SingleDetectionRule -Rule $rule -AppFolder 'test'
            $result.'@odata.type' | Should -Be '#microsoft.graph.win32LobAppRegistryRule'
            $result.ruleType | Should -Be 'detection'
            $result.operationType | Should -Be 'version'
            $result.operator | Should -Be 'greaterThanOrEqual'
            $result.comparisonValue | Should -Be '2.0'
            $result.check32BitOn64System | Should -Be $true
        }
        It 'builds string comparison rule' {
            $rule = [PSCustomObject]@{
                DetectionType          = 'Registry'
                RegistryDetectionType  = 'stringComparison'
                KeyPath                = 'HKLM\SOFTWARE\Test'
                ValueName              = 'InstallPath'
                Operator               = 'equal'
                Value                  = 'C:\Program Files'
                Check32BitOn64System   = 'false'
            }
            $result = Build-SingleDetectionRule -Rule $rule -AppFolder 'test'
            $result.operationType | Should -Be 'string'
            $result.check32BitOn64System | Should -Be $false
        }
        It 'defaults to existence detection when no method specified' {
            $rule = [PSCustomObject]@{
                DetectionType = 'Registry'
                KeyPath       = 'HKLM\SOFTWARE\Test'
                ValueName     = 'Installed'
            }
            $result = Build-SingleDetectionRule -Rule $rule -AppFolder 'test'
            $result.operationType | Should -Be 'exists'
            $result.operator | Should -Be 'notConfigured'
        }
    }

    Context 'File detection' {
        It 'builds file existence rule' {
            $rule = [PSCustomObject]@{
                DetectionType      = 'File'
                Path               = 'C:\Program Files\7-Zip'
                FileOrFolderName   = '7z.exe'
                FileDetectionType  = 'exists'
                check32BitOn64System = 'false'
            }
            $result = Build-SingleDetectionRule -Rule $rule -AppFolder 'test'
            $result.'@odata.type' | Should -Be '#microsoft.graph.win32LobAppFileSystemRule'
            $result.ruleType | Should -Be 'detection'
            $result.path | Should -Be 'C:\Program Files\7-Zip'
            $result.fileOrFolderName | Should -Be '7z.exe'
            $result.operationType | Should -Be 'exists'
        }
        It 'builds file version rule with operator' {
            $rule = [PSCustomObject]@{
                DetectionType     = 'File'
                Path              = 'C:\Program Files\App'
                FileOrFolderName  = 'app.exe'
                FileDetectionType = 'version'
                Operator          = 'greaterThanOrEqual'
                VersionValue      = '3.0.0'
            }
            $result = Build-SingleDetectionRule -Rule $rule -AppFolder 'test'
            $result.operationType | Should -Be 'version'
            $result.operator | Should -Be 'greaterThanOrEqual'
            $result.comparisonValue | Should -Be '3.0.0'
        }
    }

    Context 'Unsupported type' {
        It 'throws for unknown detection type' {
            $rule = [PSCustomObject]@{ DetectionType = 'Magic' }
            { Build-SingleDetectionRule -Rule $rule -AppFolder 'test' } | Should -Throw '*Unsupported detection rule type*'
        }
    }
}

Describe 'Build-DetectionRules' {
    It 'processes an array of rules' {
        $rules = @(
            [PSCustomObject]@{ DetectionType = 'MSI'; ProductCode = '{A}' },
            [PSCustomObject]@{ DetectionType = 'File'; Path = 'C:\'; FileOrFolderName = 'x.exe' }
        )
        $results = Build-DetectionRules -Rules $rules -AppFolder 'test'
        $results.Count | Should -Be 2
        $results[0].'@odata.type' | Should -Be '#microsoft.graph.win32LobAppProductCodeRule'
        $results[1].'@odata.type' | Should -Be '#microsoft.graph.win32LobAppFileSystemRule'
    }
}

Describe 'Build-AppPayload' {
    BeforeAll {
        $testConfig = @{
            Information = @{
                DisplayName    = 'Test App'
                Description    = 'A test application'
                Publisher      = 'Test Publisher'
                Developer      = 'Test Dev'
                InformationURL = 'https://example.com'
                PrivacyURL     = 'https://example.com/privacy'
                Notes          = 'Test notes'
            }
            Program = @{
                InstallCommand        = 'install.exe /s'
                UninstallCommand      = 'uninstall.exe /s'
                InstallExperience     = 'system'
                DeviceRestartBehavior = 'suppress'
            }
            RequirementRule = @{
                MinimumRequiredOperatingSystem = 'W10_22H2'
            }
        }
        $testRules = @(@{ '@odata.type' = '#microsoft.graph.win32LobAppProductCodeRule'; ruleType = 'detection' })
    }

    It 'builds correct odata type' {
        $result = Build-AppPayload -Config $testConfig -DetectionRules $testRules -SetupFileName "Deploy-Application.exe" -IntuneWinFileName "Deploy-Application.intunewin"
        $result.'@odata.type' | Should -Be '#microsoft.graph.win32LobApp'
    }
    It 'sets display name from config' {
        $result = Build-AppPayload -Config $testConfig -DetectionRules $testRules -SetupFileName "Deploy-Application.exe" -IntuneWinFileName "Deploy-Application.intunewin"
        $result.displayName | Should -Be 'Test App'
    }
    It 'maps install experience' {
        $result = Build-AppPayload -Config $testConfig -DetectionRules $testRules -SetupFileName "Deploy-Application.exe" -IntuneWinFileName "Deploy-Application.intunewin"
        $result.installExperience.runAsAccount | Should -Be 'system'
    }
    It 'includes standard return codes' {
        $result = Build-AppPayload -Config $testConfig -DetectionRules $testRules -SetupFileName "Deploy-Application.exe" -IntuneWinFileName "Deploy-Application.intunewin"
        $result.returnCodes.Count | Should -Be 5
        ($result.returnCodes | Where-Object { $_.returnCode -eq 0 }).type | Should -Be 'success'
        ($result.returnCodes | Where-Object { $_.returnCode -eq 3010 }).type | Should -Be 'softReboot'
    }
    It 'sets OS requirement to Graph API ceiling for W10_22H2' {
        $result = Build-AppPayload -Config $testConfig -DetectionRules $testRules -SetupFileName "Deploy-Application.exe" -IntuneWinFileName "Deploy-Application.intunewin"
        $result.minimumSupportedOperatingSystem.v10_21H1 | Should -Be $true
    }
    It 'sets deviceRestartBehavior when provided' {
        $result = Build-AppPayload -Config $testConfig -DetectionRules $testRules -SetupFileName "Deploy-Application.exe" -IntuneWinFileName "Deploy-Application.intunewin"
        $result.deviceRestartBehavior | Should -Be 'suppress'
    }
    It 'excludes icon when not provided' {
        $result = Build-AppPayload -Config $testConfig -DetectionRules $testRules -SetupFileName "Deploy-Application.exe" -IntuneWinFileName "Deploy-Application.intunewin"
        $result.ContainsKey('largeIcon') | Should -Be $false
    }
    It 'includes icon when base64 is provided' {
        $result = Build-AppPayload -Config $testConfig -DetectionRules $testRules -SetupFileName 'Deploy-Application.exe' -IntuneWinFileName 'Deploy-Application.intunewin' -IconBase64 'AAAA'
        $result.largeIcon.value | Should -Be 'AAAA'
        $result.largeIcon.type | Should -Be 'image/png'
    }
    It 'passes detection rules through' {
        $result = Build-AppPayload -Config $testConfig -DetectionRules $testRules -SetupFileName "Deploy-Application.exe" -IntuneWinFileName "Deploy-Application.intunewin"
        $result.rules.Count | Should -Be 1
    }
    It 'includes setupFilePath from parameter' {
        $result = Build-AppPayload -Config $testConfig -DetectionRules $testRules -SetupFileName "Deploy-Application.exe" -IntuneWinFileName "Deploy-Application.intunewin"
        $result.setupFilePath | Should -Be 'Deploy-Application.exe'
    }
}

Describe 'Resolve-IconBase64' {
    It 'reads local icon file and returns base64' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester_icon_$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        $iconBytes = [byte[]](0x89, 0x50, 0x4E, 0x47)  # PNG magic bytes
        [System.IO.File]::WriteAllBytes("$tempDir/Icon.png", $iconBytes)

        $result = Resolve-IconBase64 -AppFolder $tempDir -IconRef 'Icon.png'
        $result | Should -Not -BeNullOrEmpty
        $decoded = [Convert]::FromBase64String($result)
        $decoded[0] | Should -Be 0x89

        Remove-Item $tempDir -Recurse -Force
    }
    It 'returns null when icon file does not exist' {
        $result = Resolve-IconBase64 -AppFolder '/nonexistent/path' -IconRef 'Icon.png'
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-AssignmentTarget' {
    It 'maps AllUsers to allLicensedUsersAssignmentTarget' {
        $assignment = [PSCustomObject]@{ Target = 'AllUsers' }
        $result = Resolve-AssignmentTarget -Assignment $assignment
        $result.'@odata.type' | Should -Be '#microsoft.graph.allLicensedUsersAssignmentTarget'
    }
    It 'maps AllDevices to allDevicesAssignmentTarget' {
        $assignment = [PSCustomObject]@{ Target = 'AllDevices' }
        $result = Resolve-AssignmentTarget -Assignment $assignment
        $result.'@odata.type' | Should -Be '#microsoft.graph.allDevicesAssignmentTarget'
    }
    It 'maps group with GroupID to groupAssignmentTarget' {
        $assignment = [PSCustomObject]@{ Target = 'MyGroup'; GroupID = 'abc-123' }
        $result = Resolve-AssignmentTarget -Assignment $assignment
        $result.'@odata.type' | Should -Be '#microsoft.graph.groupAssignmentTarget'
        $result.groupId | Should -Be 'abc-123'
    }
    It 'returns null when group has no GroupID' {
        $assignment = [PSCustomObject]@{ Target = 'MyGroup' }
        $result = Resolve-AssignmentTarget -Assignment $assignment 3>$null
        $result | Should -BeNullOrEmpty
    }
}

Describe 'App.json validation' {
    BeforeAll {
        $appFolders = Get-ChildItem -Path (Join-Path $PSScriptRoot '..' 'Apps') -Directory
    }

    It 'every app folder has App.json' {
        foreach ($folder in $appFolders) {
            $appJson = Join-Path $folder.FullName 'App.json'
            Test-Path $appJson | Should -Be $true -Because "$($folder.Name) must have App.json"
        }
    }

    It 'every App.json has required top-level keys' {
        $requiredKeys = @('PackageInformation', 'Information', 'Program', 'RequirementRule', 'DetectionRule', 'Assignment')
        foreach ($folder in $appFolders) {
            $config = Get-Content -Raw (Join-Path $folder.FullName 'App.json') | ConvertFrom-Json
            foreach ($key in $requiredKeys) {
                $config.PSObject.Properties.Name | Should -Contain $key -Because "$($folder.Name)/App.json must have '$key'"
            }
        }
    }

    It 'every App.json has valid DetectionRule with DetectionType' {
        foreach ($folder in $appFolders) {
            $config = Get-Content -Raw (Join-Path $folder.FullName 'App.json') | ConvertFrom-Json
            foreach ($rule in $config.DetectionRule) {
                $type = $rule.DetectionType ?? $rule.Type
                $type | Should -Not -BeNullOrEmpty -Because "$($folder.Name) detection rule must specify DetectionType"
                $type | Should -BeIn @('MSI', 'Registry', 'File', 'Script') -Because "$($folder.Name) has invalid DetectionType '$type'"
            }
        }
    }

    It 'every App.json has non-empty DisplayName' {
        foreach ($folder in $appFolders) {
            $config = Get-Content -Raw (Join-Path $folder.FullName 'App.json') | ConvertFrom-Json
            $config.Information.DisplayName | Should -Not -BeNullOrEmpty -Because "$($folder.Name) must have a DisplayName"
        }
    }

    It 'every App.json has install and uninstall commands' {
        foreach ($folder in $appFolders) {
            $config = Get-Content -Raw (Join-Path $folder.FullName 'App.json') | ConvertFrom-Json
            $config.Program.InstallCommand | Should -Not -BeNullOrEmpty -Because "$($folder.Name) must have InstallCommand"
            $config.Program.UninstallCommand | Should -Not -BeNullOrEmpty -Because "$($folder.Name) must have UninstallCommand"
        }
    }
}

Describe 'appList.json validation' {
    BeforeAll {
        $appList = Get-Content -Raw (Join-Path $PSScriptRoot '..' 'appList.json') | ConvertFrom-Json
    }

    It 'is a non-empty array' {
        @($appList).Count | Should -BeGreaterThan 0
    }

    It 'each entry has required fields' {
        $required = @('IntuneAppName', 'AppPublisher', 'AppSource', 'AppID', 'AppFolderName', 'FilterOptions')
        foreach ($app in @($appList)) {
            foreach ($field in $required) {
                $app.PSObject.Properties.Name | Should -Contain $field -Because "$($app.IntuneAppName) must have '$field'"
            }
        }
    }

    It 'each AppFolderName maps to an existing Apps/ directory' {
        foreach ($app in @($appList)) {
            $folder = Join-Path $PSScriptRoot '..' 'Apps' $app.AppFolderName
            Test-Path $folder | Should -Be $true -Because "Apps/$($app.AppFolderName) must exist for $($app.IntuneAppName)"
        }
    }

    It 'each FilterOptions has Architecture and Type' {
        foreach ($app in @($appList)) {
            foreach ($filter in $app.FilterOptions) {
                $filter.Architecture | Should -Not -BeNullOrEmpty
                $filter.Type | Should -Not -BeNullOrEmpty
            }
        }
    }
}

Describe 'Invoke-Graph retry logic' {
    It 'retries on 429 and eventually succeeds' {
        $script:retryCallCount = 0
        Mock Invoke-RestMethod {
            $script:retryCallCount++
            if ($script:retryCallCount -lt 3) {
                $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new("429", $response)
                throw $exception
            }
            return @{ id = 'success' }
        }
        Mock Start-Sleep {}

        $result = Invoke-Graph -Headers @{ Authorization = 'Bearer test' } -Uri 'https://graph.microsoft.com/test'
        $result.id | Should -Be 'success'
        $script:retryCallCount | Should -Be 3
    }

    It 'throws on non-retryable errors immediately' {
        Mock Invoke-RestMethod {
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::BadRequest)
            $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new("400", $response)
            throw $exception
        }

        { Invoke-Graph -Headers @{ Authorization = 'Bearer test' } -Uri 'https://graph.microsoft.com/test' } | Should -Throw
    }
}
