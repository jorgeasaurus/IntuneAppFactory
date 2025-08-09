#Requires -Version 5.1
<#
.SYNOPSIS
    Trigger the GitHub Actions workflow for IntuneAppFactory
.DESCRIPTION
    This script triggers the workflow manually using GitHub CLI or opens the browser
.EXAMPLE
    .\Trigger-Workflow.ps1
#>

Write-Host "Triggering IntuneAppFactory GitHub Actions Workflow" -ForegroundColor Cyan
Write-Host "====================================================`n" -ForegroundColor Cyan

# Check if gh CLI is installed and authenticated
$ghInstalled = Get-Command gh -ErrorAction SilentlyContinue

if ($ghInstalled) {
    Write-Host "GitHub CLI detected. Checking authentication..." -ForegroundColor Yellow
    
    try {
        $authStatus = gh auth status 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Authenticated! Triggering workflow..." -ForegroundColor Green
            gh workflow run publish.yml --repo jorgeasaurus/IntuneAppFactory
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "`nWorkflow triggered successfully!" -ForegroundColor Green
                Write-Host "View runs at: https://github.com/jorgeasaurus/IntuneAppFactory/actions" -ForegroundColor Cyan
                
                # Show recent runs
                Write-Host "`nRecent workflow runs:" -ForegroundColor Yellow
                gh run list --workflow=publish.yml --repo jorgeasaurus/IntuneAppFactory --limit 5
            }
        } else {
            Write-Host "Not authenticated. Please run: gh auth login" -ForegroundColor Red
            Write-Host "`nOpening GitHub Actions page in browser instead..." -ForegroundColor Yellow
            Start-Process "https://github.com/jorgeasaurus/IntuneAppFactory/actions/workflows/publish.yml"
        }
    } catch {
        Write-Host "Error checking auth status. Opening browser..." -ForegroundColor Yellow
        Start-Process "https://github.com/jorgeasaurus/IntuneAppFactory/actions/workflows/publish.yml"
    }
} else {
    Write-Host "GitHub CLI not installed." -ForegroundColor Yellow
    Write-Host "Opening GitHub Actions page in browser..." -ForegroundColor Yellow
    Write-Host "`nYou can trigger the workflow manually by:" -ForegroundColor Cyan
    Write-Host "1. Click 'Run workflow'" -ForegroundColor Gray
    Write-Host "2. Select the branch (main)" -ForegroundColor Gray
    Write-Host "3. Click the green 'Run workflow' button" -ForegroundColor Gray
    
    Start-Process "https://github.com/jorgeasaurus/IntuneAppFactory/actions/workflows/publish.yml"
    
    Write-Host "`nTo install GitHub CLI for future use:" -ForegroundColor Yellow
    Write-Host "  winget install GitHub.cli" -ForegroundColor Gray
    Write-Host "  OR" -ForegroundColor Gray
    Write-Host "  choco install gh" -ForegroundColor Gray
}

Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")