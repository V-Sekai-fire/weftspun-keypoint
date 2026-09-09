# Installs the pinned repo launcher and the pinned pixi into ~\.local\bin and
# ~\.pixi\bin on Windows. Run it after `repo init`, from any directory.
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$pins = Join-Path $here 'bootstrap-pins.txt'
$bin = if ($env:LOCAL_BIN) { $env:LOCAL_BIN } else { Join-Path $HOME '.local\bin' }
$pixiRoot = if ($env:PIXI_HOME) { $env:PIXI_HOME } else { Join-Path $HOME '.pixi' }
$pixiBin = Join-Path $pixiRoot 'bin'

$rows = Get-Content $pins | ForEach-Object { , ($_ -split '\s+') }
function Pin($tool, $key) { ($rows | Where-Object { $_[0] -eq $tool -and $_[1] -eq $key })[0][2] }
function ShaOf($path) { (Get-FileHash -Algorithm SHA256 $path).Hash.ToLowerInvariant() }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $work | Out-Null
try {
  # repo first. The pins live in the manifest repository, which only exists once
  # repo has fetched it, so the launcher that did the fetching is checked here
  # against the pin rather than before it -- the one link no pin can cover.
  $repoVersion = Pin 'repo' 'version'
  $repoSource = Pin 'repo' 'source'
  $repoSha = Pin 'repo' 'sha256'
  $staged = Join-Path $work 'repo'
  Invoke-WebRequest -UseBasicParsing -Uri $repoSource -OutFile $staged
  $got = ShaOf $staged
  if ($got -ne $repoSha) { throw "checksum mismatch for the repo launcher: got $got, pinned $repoSha" }

  $existing = (Get-Command repo -ErrorAction SilentlyContinue).Source
  if ($existing -and (ShaOf $existing) -ne $repoSha) {
    Write-Warning "$existing is not the pinned launcher $repoVersion; $bin\repo will be"
  }
  New-Item -ItemType Directory -Path $bin -Force | Out-Null
  Move-Item -Path $staged -Destination (Join-Path $bin 'repo') -Force
  Write-Output "repo launcher $repoVersion installed to $bin\repo (it needs python3 on PATH)"

  # pixi second, because nothing above it needs pixi and the manifest that pins
  # it is already on disk by now.
  $want = switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { 'win-64' }
    'ARM64' { 'win-arm64' }
    default { throw "no bootstrap row for $($env:PROCESSOR_ARCHITECTURE); add one to bootstrap-pins.txt" }
  }

  $pixiVersion = Pin 'pixi' 'version'
  $pixiSource = Pin 'pixi' 'source'
  $row = $rows | Where-Object { $_[0] -eq 'pixi' -and $_[1] -eq 'platform' -and $_[2] -eq $want } | Select-Object -First 1
  if ($null -eq $row -or $row.Count -lt 6) { throw "bootstrap-pins.txt has no complete pixi row for $want" }
  $asset = $row[3]; $sha = $row[4]; $member = $row[5]

  $exe = Join-Path $pixiBin 'pixi.exe'
  if ((Test-Path $exe) -and ((& $exe --version) -eq "pixi $pixiVersion")) {
    Write-Output "pixi $pixiVersion already at $exe"
    exit 0
  }

  $archive = Join-Path $work $asset
  Invoke-WebRequest -UseBasicParsing -Uri "$pixiSource$asset" -OutFile $archive
  $got = ShaOf $archive
  if ($got -ne $sha) { throw "checksum mismatch for ${asset}: got $got, pinned $sha" }

  Expand-Archive -Path $archive -DestinationPath $work -Force
  New-Item -ItemType Directory -Path $pixiBin -Force | Out-Null
  Move-Item -Path (Join-Path $work $member) -Destination $exe -Force
  Write-Output "pixi $pixiVersion installed to $exe; put $bin and $pixiBin on PATH"
}
finally { Remove-Item -Recurse -Force $work }
