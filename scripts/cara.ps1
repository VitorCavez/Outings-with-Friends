if (-not $env:API_BASE_URL) { $env:API_BASE_URL = "https://outings-with-friends-api.onrender.com" }

$email = $env:CARA_EMAIL
if (-not $email -and (Test-Path -Path ".\backend\.env.local")) {
  $lines = Get-Content ".\backend\.env.local"
  $email = ($lines | Where-Object { $_ -match "^CARA_EMAIL=" }) -replace "^CARA_EMAIL=", ""
}
if (-not $email) { $email = "cara@example.com" }

& "$PSScriptRoot\get-jwt.ps1" -email $email
