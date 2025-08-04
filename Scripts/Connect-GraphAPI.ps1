#Requires -Version 5.1
#Requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Helper script to connect to Microsoft Graph API using modern authentication
.DESCRIPTION
    This script demonstrates how to connect to Microsoft Graph using the Microsoft Graph PowerShell SDK
    with client credentials (app-only authentication).
.PARAMETER TenantId
    The Azure AD tenant ID
.PARAMETER ClientId
    The application (client) ID
.PARAMETER ClientSecret
    The client secret for the application
.EXAMPLE
    .\Connect-GraphAPI.ps1 -TenantId "your-tenant-id" -ClientId "your-client-id" -ClientSecret "your-secret"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,
    
    [Parameter(Mandatory = $true)]
    [string]$ClientId,
    
    [Parameter(Mandatory = $true)]
    [string]$ClientSecret
)

begin {
    # Import required modules
    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.DeviceManagement',
        'Microsoft.Graph.DeviceManagement.Actions',
        'Microsoft.Graph.Groups'
    )
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Host "Installing module: $module" -ForegroundColor Yellow
            Install-Module -Name $module -Force -AllowClobber
        }
        Import-Module $module -Force
    }
}

process {
    try {
        Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
        
        # Create credential object
        $secureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
        $credential = [PSCredential]::new($ClientId, $secureSecret)
        
        # Connect to Graph
        Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome
        
        # Get context to verify connection
        $context = Get-MgContext
        
        if ($context) {
            Write-Host "Successfully connected to Microsoft Graph!" -ForegroundColor Green
            Write-Host "Tenant ID: $($context.TenantId)" -ForegroundColor Gray
            Write-Host "Client ID: $($context.ClientId)" -ForegroundColor Gray
            Write-Host "Scopes: $($context.Scopes -join ', ')" -ForegroundColor Gray
            
            # Return the context
            return $context
        } else {
            throw "Failed to establish Graph connection"
        }
        
    } catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        throw
    }
}

end {
    Write-Host "`nTo disconnect, run: Disconnect-MgGraph" -ForegroundColor Yellow
}