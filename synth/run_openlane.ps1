# Script to run OpenLane physical design flow using Docker on Windows

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Resolve absolute path for repository root
$RepoRoot = (Get-Item $ScriptDir).Parent.FullName

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Microscaled Attention Core OpenLane ASIC Layout Flow" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "Repository Root: $RepoRoot" -ForegroundColor Yellow

# Check if Docker is running
Write-Host "Checking if Docker is running..." -ForegroundColor Yellow
& docker info > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker is not running or not in PATH. Please start Docker Desktop and try again."
    Exit 1
}

# Image name
$DockerImage = "efabless/openlane:2023.11.23"

# Run OpenLane container mounting the repository root
Write-Host "Running OpenLane flow inside Docker container ($DockerImage)..." -ForegroundColor Yellow
Write-Host "Mounting $RepoRoot to /work inside container..." -ForegroundColor Yellow

docker run --rm `
  -v "${RepoRoot}:/work" `
  -w /work `
  $DockerImage `
  /openlane/flow.tcl -design /work/openlane/mx_attention_core -tag run_sky130 -overwrite

if ($LASTEXITCODE -eq 0) {
    Write-Host "====================================================" -ForegroundColor Green
    Write-Host "OpenLane flow completed successfully!" -ForegroundColor Green
    Write-Host "GDSII layout and reports are located in:" -ForegroundColor Green
    Write-Host "openlane/mx_attention_core/runs/run_sky130/" -ForegroundColor Green
    Write-Host "====================================================" -ForegroundColor Green
} else {
    Write-Error "OpenLane flow failed. Check the logs above or in openlane/mx_attention_core/runs/run_sky130/logs/synthesis/"
}
