# Optional: custom base
if (-not $env:API_BASE_URL) { $env:API_BASE_URL = "http://localhost:4000" }

# Pull email from .env.local if present
$email = $env:ALICE_EMAIL
if (-not $email -and (Test-Path -Path ".\backend\.env.local")) {
  $lines = Get-Content ".\backend\.env.local"
  $email = ($lines | Where-Object { $_ -match "^ALICE_EMAIL=" }) -replace "^ALICE_EMAIL=", ""
}
if (-not $email) { $email = "alice@example.com" }

& "$PSScriptRoot\get-jwt.ps1" -email $email
