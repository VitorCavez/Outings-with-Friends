param([string]$email)

# Prefer env; else default to your Render API; else read backend/.env.local; else localhost
$base = $env:API_BASE_URL
if (-not $base) { $base = "https://outings-with-friends-api.onrender.com" }
if ($base -and $base.Trim() -eq "") { $base = "https://outings-with-friends-api.onrender.com" }
if (-not $base -and (Test-Path -Path ".\backend\.env.local")) {
  $lines = Get-Content ".\backend\.env.local"
  $apiLine = $lines | Where-Object { $_ -match "^API_BASE_URL=" }
  if ($apiLine) { $base = $apiLine -replace "^API_BASE_URL=", "" }
}
if (-not $base) { $base = "http://localhost:4000" }

# Email resolution (param > env > .env.local > default alice)
if (-not $email) { $email = $env:ALICE_EMAIL }
if (-not $email -and (Test-Path -Path ".\backend\.env.local")) {
  $lines = Get-Content ".\backend\.env.local"
  $email = ($lines | Where-Object { $_ -match "^ALICE_EMAIL=" }) -replace "^ALICE_EMAIL=", ""
}
if (-not $email) { Write-Error "No email specified."; exit 1 }

# Try /api/dev/jwt first, then /dev/jwt
$encoded = [Uri]::EscapeDataString($email)
$endpoints = @("$base/api/dev/jwt?email=$encoded", "$base/dev/jwt?email=$encoded")

foreach ($url in $endpoints) {
  Write-Host "Fetching JWT for $email from $url ..."
  try {
    $res = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 20
    $token = $res.token
    if ($token) {
      $env:JWT = $token
      Write-Output $token
      exit 0
    }
  } catch {
    Write-Warning "Attempt failed: $($_.Exception.Message)"
  }
}

Write-Error "No token returned from any endpoint."
exit 1
