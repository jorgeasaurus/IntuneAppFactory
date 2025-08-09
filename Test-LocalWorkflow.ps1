#Requires -Version 5.1
<#
.SYNOPSIS
    Test Intune App Factory workflows locally
.DESCRIPTION
    This script helps test the Intune App Factory GitHub Actions workflows locally using act.
.PARAMETER Workflow
    The workflow to test. Default is 'test-local'
.PARAMETER Job
    Specific job to run. If not specified, runs all jobs.
.PARAMETER SecretsFile
    Path to the secrets file. Default is '.secrets.local'
.EXAMPLE
    .\Test-LocalWorkflow.ps1
    Tests the default test-local workflow
.EXAMPLE
    .\Test-LocalWorkflow.ps1 -Workflow publish -Job test_apps
    Tests only the test_apps job from the publish workflow
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('publish')]
    [string]$Workflow = 'publish',
    
    [Parameter()]
    [string]$Job,
    
    [Parameter()]
    [string]$SecretsFile = '.secrets.local'
)

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
if ($Workflow -eq 'publish') {
    $actArgs += 'workflow_dispatch'
} else {
    $actArgs += 'workflow_dispatch'
}

# Add workflow file
$actArgs += '-W', ".github/workflows/$Workflow.yml"

# Add job if specified
if ($Job) {
    $actArgs += '-j', $Job
}

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