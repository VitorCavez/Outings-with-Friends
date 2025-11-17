param([string]$email)

# Base URL
$base = $env:API_BASE_URL
if (-not $base) {
  if (Test-Path -Path ".\backend\.env.local") {
    $lines = Get-Content ".\backend\.env.local"
    $apiLine = $lines | Where-Object { $_ -match "^API_BASE_URL=" }
    if ($apiLine) {
      $base = $apiLine -replace "^API_BASE_URL=", ""
    }
  }
}
if (-not $base) { $base = "http://localhost:4000" }

if (-not $email) {
  # Try to read from .env.local if not provided
  if (Test-Path -Path ".\backend\.env.local") {
    $lines = Get-Content ".\backend\.env.local"
    $email = ($lines | Where-Object { $_ -match "^ALICE_EMAIL=" }) -replace "^ALICE_EMAIL=", ""
  }
}

if (-not $email) { Write-Error "No email specified."; exit 1 }

Write-Host "Fetching JWT for $email from $base/dev/jwt ..."
try {
  $res = Invoke-RestMethod -Uri "$base/dev/jwt?email=$([Uri]::EscapeDataString($email))" -Method GET
  $token = $res.token
  if (-not $token) { throw "No token returned" }
  $env:JWT = $token
  Write-Output $token
} catch {
  Write-Error $_
  exit 1
}
