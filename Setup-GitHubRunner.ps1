#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Setup GitHub Actions self-hosted runner for IntuneAppFactory
.DESCRIPTION
    This script helps you set up a self-hosted GitHub Actions runner on Windows
.EXAMPLE
    .\Setup-GitHubRunner.ps1
#>

Write-Host @"
========================================
GitHub Actions Self-Hosted Runner Setup
========================================

To set up a self-hosted runner:

1. Go to your repository on GitHub:
   https://github.com/jorgeasaurus/IntuneAppFactory

2. Navigate to:
   Settings > Actions > Runners > New self-hosted runner

3. Select 'Windows' as the operating system

4. Follow the instructions provided, which will look like:

   # Create a folder for the runner
   mkdir actions-runner; cd actions-runner
   
   # Download the latest runner package
   Invoke-WebRequest -Uri https://github.com/actions/runner/releases/download/v2.XXX.X/actions-runner-win-x64-2.XXX.X.zip -OutFile actions-runner-win-x64-2.XXX.X.zip
   
   # Extract the installer
   Add-Type -AssemblyName System.IO.Compression.FileSystem
   [System.IO.Compression.ZipFile]::ExtractToDirectory("`$PWD/actions-runner-win-x64-2.XXX.X.zip", "`$PWD")
   
   # Configure the runner
   ./config.cmd --url https://github.com/jorgeasaurus/IntuneAppFactory --token YOUR_TOKEN_HERE
   
   # Run it!
   ./run.cmd

5. For automatic startup, install as a Windows service:
   ./svc.sh install
   ./svc.sh start

"@ -ForegroundColor Cyan

Write-Host "Alternative: Use GitHub-hosted runners instead" -ForegroundColor Yellow
Write-Host @"

To use GitHub-hosted runners instead of self-hosted:

1. Edit .github/workflows/publish.yml
2. Change: runs-on: [self-hosted, Windows]
3. To:     runs-on: windows-latest

Note: GitHub-hosted runners are free for public repos (2000 minutes/month)
      For private repos, you get 2000 minutes/month on the free plan

"@ -ForegroundColor Gray

$choice = Read-Host "`nWould you like to use GitHub-hosted runners instead? (Y/N)"

if ($choice -eq 'Y') {
    Write-Host "`nUpdating workflow to use GitHub-hosted runners..." -ForegroundColor Green
    
    $workflowPath = Join-Path $PSScriptRoot ".github\workflows\publish.yml"
    if (Test-Path $workflowPath) {
        $content = Get-Content $workflowPath -Raw
        $content = $content -replace 'runs-on:\s*\[self-hosted,\s*Windows\]', 'runs-on: windows-latest'
        Set-Content -Path $workflowPath -Value $content -NoNewline
        Write-Host "Updated workflow to use GitHub-hosted runners!" -ForegroundColor Green
        Write-Host "Commit and push this change to use GitHub-hosted runners." -ForegroundColor Yellow
    } else {
        Write-Error "Workflow file not found at: $workflowPath"
    }
}