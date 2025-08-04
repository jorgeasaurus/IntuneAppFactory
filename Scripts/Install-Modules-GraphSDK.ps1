<#
.SYNOPSIS
    This script is responsible for installing the required PowerShell modules for the pipeline to function using Microsoft Graph SDK.

.DESCRIPTION
    This script is responsible for installing the required PowerShell modules for the pipeline to function.
    This version installs Microsoft Graph SDK modules instead of the deprecated IntuneWin32App module.

.EXAMPLE
    .\Install-Modules-GraphSDK.ps1

.NOTES
    FileName:    Install-Modules-GraphSDK.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2022-04-04
    Updated:     2025-01-02

    Version history:
    1.0.0 - (2022-04-04) Script created
    1.0.1 - (2024-03-04) Improved module installation logic
    2.0.0 - (2025-01-02) Migrated to Microsoft Graph SDK modules
#>
Process {
    # Ensure package provider is installed
    $PackageProvider = Install-PackageProvider -Name "NuGet" -Force

    # Updated module list with Microsoft Graph SDK modules replacing IntuneWin32App
    $Modules = @(
        "Evergreen",
        "Microsoft.Graph.Authentication",
        "Microsoft.Graph.DeviceManagement",
        "Microsoft.Graph.DeviceManagement.Actions",
        "Microsoft.Graph.Groups",
        "Az.Storage",
        "Az.Resources"
    )
    
    foreach ($Module in $Modules) {
        try {
            Write-Output -InputObject "Attempting to locate module: $($Module)"
            $ModuleItem = Get-InstalledModule -Name $Module -ErrorAction "SilentlyContinue" -Verbose:$false
            if ($ModuleItem -ne $null) {
                Write-Output -InputObject "$($Module) module detected, checking for latest version"
                $LatestModuleItemVersion = (Find-Module -Name $Module -ErrorAction "Stop" -Verbose:$false).Version
                if ($LatestModuleItemVersion -ne $null) {
                    if ($LatestModuleItemVersion -gt $ModuleItem.Version) {
                        Write-Output -InputObject "Latest version of $($Module) module is not installed, attempting to install: $($LatestModuleItemVersion.ToString())"
                        $UpdateModuleInvocation = Update-Module -Name $Module -Force -ErrorAction "Stop" -Confirm:$false -Verbose:$false
                    }
                    else {
                        Write-Output -InputObject "Latest version of $($Module) is already installed: $($ModuleItem.Version.ToString())"
                    }
                }
                else {
                    Write-Output -InputObject "Could not determine if module update is required, skipping update for $($Module) module"
                }
            }
            else {
                Write-Output -InputObject "Attempting to install module: $($Module)"
                $InstallModuleInvocation = Install-Module -Name $Module -Force -AllowClobber -ErrorAction "Stop" -Confirm:$false -Verbose:$false
                Write-Output -InputObject "Module $($Module) installed successfully"
            }
        }
        catch [System.Exception] {
            Write-Warning -Message "An error occurred while attempting to install $($Module) module. Error message: $($_.Exception.Message)"
        }
    }

    # Special handling for Microsoft Graph modules to ensure compatibility
    Write-Output -InputObject "Verifying Microsoft Graph module compatibility"
    try {
        # Import the authentication module to verify installation
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        $GraphModuleVersion = (Get-Module Microsoft.Graph.Authentication).Version
        Write-Output -InputObject "Microsoft Graph Authentication module version $($GraphModuleVersion) loaded successfully"
    }
    catch {
        Write-Warning -Message "Failed to load Microsoft Graph Authentication module. Error: $($_.Exception.Message)"
    }
}