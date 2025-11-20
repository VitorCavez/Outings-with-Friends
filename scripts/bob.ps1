if (-not $env:API_BASE_URL) { $env:API_BASE_URL = "https://outings-with-friends-api.onrender.com" }

$email = $env:BOB_EMAIL
if (-not $email -and (Test-Path -Path ".\backend\.env.local")) {
  $lines = Get-Content ".\backend\.env.local"
  $email = ($lines | Where-Object { $_ -match "^BOB_EMAIL=" }) -replace "^BOB_EMAIL=", ""
}
if (-not $email) { $email = "bob@example.com" }

& "$PSScriptRoot\get-jwt.ps1" -email $email
