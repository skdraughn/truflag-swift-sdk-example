$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$vendor = Join-Path $root 'vendor'
$archive = Join-Path $vendor 'TruflagSDK.tar.gz'
$checksumFile = Join-Path $vendor 'TruflagSDK.tar.gz.sha256'
$target = Join-Path $vendor 'TruflagSDK'

if (-not (Test-Path $archive)) {
  throw "Missing archive: $archive"
}
if (-not (Test-Path $checksumFile)) {
  throw "Missing checksum: $checksumFile"
}

$expected = (Get-Content $checksumFile).Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)[0].Trim()
$actual = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()

if ($expected.ToLowerInvariant() -ne $actual) {
  throw "Checksum mismatch for TruflagSDK.tar.gz`nExpected: $expected`nActual:   $actual"
}

if (Test-Path $target) {
  Remove-Item $target -Recurse -Force
}

tar -xzf $archive -C $vendor
Write-Host "SDK extracted to $target"
