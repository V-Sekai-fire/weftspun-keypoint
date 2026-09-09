# Installs the pinned pixi into $PIXI_HOME\bin (default ~\.pixi\bin) on Windows.
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$pin = Join-Path $here 'pixi-release.txt'
$root = if ($env:PIXI_HOME) { $env:PIXI_HOME } else { Join-Path $HOME '.pixi' }
$dest = Join-Path $root 'bin'

$want = switch ($env:PROCESSOR_ARCHITECTURE) {
  'AMD64' { 'win-64' }
  'ARM64' { 'win-arm64' }
  default { throw "no bootstrap row for $($env:PROCESSOR_ARCHITECTURE); add one to pixi-release.txt" }
}

$rows = Get-Content $pin | ForEach-Object { , ($_ -split '\s+') }
$version = ($rows | Where-Object { $_[0] -eq 'version' })[0][1]
$sourceUrl = ($rows | Where-Object { $_[0] -eq 'source' })[0][1]
$row = $rows | Where-Object { $_[0] -eq 'platform' -and $_[1] -eq $want } | Select-Object -First 1
if ($null -eq $row -or $row.Count -lt 5) { throw "pixi-release.txt has no complete row for $want" }
$asset = $row[2]; $sha = $row[3]; $member = $row[4]

$exe = Join-Path $dest 'pixi.exe'
if ((Test-Path $exe) -and ((& $exe --version) -eq "pixi $version")) {
  Write-Output "pixi $version already at $exe"
  exit 0
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $work | Out-Null
try {
  $archive = Join-Path $work $asset
  Invoke-WebRequest -UseBasicParsing -Uri "$sourceUrl$asset" -OutFile $archive
  $got = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant()
  if ($got -ne $sha) { throw "checksum mismatch for ${asset}: got $got, pinned $sha" }

  Expand-Archive -Path $archive -DestinationPath $work -Force
  New-Item -ItemType Directory -Path $dest -Force | Out-Null
  Move-Item -Path (Join-Path $work $member) -Destination $exe -Force
  Write-Output "pixi $version installed to $exe; put $dest on PATH"
}
finally { Remove-Item -Recurse -Force $work }
