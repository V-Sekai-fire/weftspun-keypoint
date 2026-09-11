# One step from a bare machine to a synced, tooled workspace, on Windows:
#
#   irm https://raw.githubusercontent.com/V-Sekai-fire/manifest-weftspun/main/main/bootstrap.ps1 | iex
#
# Runs in the current directory, which becomes the repo client root.
$ErrorActionPreference = 'Stop'

$raw = if ($env:WEFTSPUN_RAW) { $env:WEFTSPUN_RAW } else { 'https://raw.githubusercontent.com/V-Sekai-fire/manifest-weftspun/main/main' }
$manifest = if ($env:WEFTSPUN_MANIFEST) { $env:WEFTSPUN_MANIFEST } else { 'https://github.com/V-Sekai-fire/manifest-weftspun.git' }
$branch = if ($env:WEFTSPUN_BRANCH) { $env:WEFTSPUN_BRANCH } else { 'main/main' }
$bin = if ($env:LOCAL_BIN) { $env:LOCAL_BIN } else { Join-Path $HOME '.local\bin' }

$pixiHome = if ($env:PIXI_HOME) { $env:PIXI_HOME } else { Join-Path $HOME '.pixi' }
$pixiBin = Join-Path $pixiHome 'bin'

$work = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $work | Out-Null

try {
    # 1. The pins, over the CDN, which is the one fetch nothing on disk can vouch for yet.
    $pins = Join-Path $work 'pins'
    Invoke-WebRequest -UseBasicParsing -Uri "$raw/bootstrap-pins.txt" -OutFile $pins
    $rows = Get-Content $pins | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { , ($_ -split '\s+') }
    $repoSource = ($rows | Where-Object { $_[0] -eq 'repo' -and $_[1] -eq 'source' })[0][2]
    $repoSha = (($rows | Where-Object { $_[0] -eq 'repo' -and $_[1] -eq 'sha256' })[0][2]).Trim().ToLowerInvariant()

    # 2. The pinned repo launcher.
    $staged = Join-Path $work 'repo'
    Invoke-WebRequest -UseBasicParsing -Uri $repoSource -OutFile $staged
    $got = (Get-FileHash -Algorithm SHA256 $staged).Hash.ToLowerInvariant()
    if ($got -ne $repoSha) { 
        throw "checksum mismatch for the repo launcher: got $got, pinned $repoSha" 
    }
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    
    $repoDest = Join-Path $bin 'repo'
    if (Test-Path $repoDest) {
        Remove-Item -Path $repoDest -Force
    }
    Move-Item -Path $staged -Destination $repoDest -Force
    $env:PATH = "$bin;$env:PATH"

    # 3. The manifest, over git, which is what makes the pins trustworthy.
    python (Join-Path $bin 'repo') init -u $manifest -b $branch

    # 4. The CDN copy against the git copy. A difference means the pins that chose the
    #    launcher in step 2 were not the pins this repository holds.
    $manifestPins = Join-Path (Get-Location) '.repo\manifests\bootstrap-pins.txt'
    if (-not (Test-Path $manifestPins)) {
        throw "Manifest file not found at $manifestPins"
    }
    
    $onDisk = (Get-FileHash -Algorithm SHA256 $manifestPins).Hash.ToLowerInvariant()
    $pinsHash = (Get-FileHash -Algorithm SHA256 $pins).Hash.ToLowerInvariant()
    if ($pinsHash -ne $onDisk) {
        throw "the pins served by $raw differ from the ones in the manifest repository"
    }

    # 5. pixi, from the pins now on disk, then the whole workspace.
    $installScript = Join-Path (Get-Location) '.repo\manifests\install.ps1'
    & powershell -ExecutionPolicy Bypass -File $installScript
    
    python (Join-Path $bin 'repo') sync
    $env:PATH = "$pixiBin;$env:PATH"
    
    $pixiExe = Join-Path $pixiBin 'pixi.exe'
    $pixiManifest = Join-Path (Get-Location) '.repo\manifests\pixi.toml'
    & $pixiExe install --manifest-path $pixiManifest --all

    Write-Output ''
    Write-Output "Workspace ready. Add these to PATH: $bin $pixiBin"
}
finally { 
    Remove-Item -Recurse -Force $work 
}
