param(
    [Parameter(Mandatory=$true)][string]$VivadoBin,
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$BuildDir,
    [ValidateSet('all','simulate','implement')][string]$Action='all'
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$out=[IO.Path]::GetFullPath($BuildDir)
if(Test-Path -LiteralPath (Join-Path $out native_build.log)) {throw 'Preserve previous native logs before rerunning the build.'}
& $Python (Join-Path $PSScriptRoot cpll_board_manifest.py) --build-dir $out
if($LASTEXITCODE -ne 0) {throw 'CPLL input freeze failed.'}
Push-Location $out
try {
    & (Join-Path $VivadoBin vivado.bat) -mode batch -source (Join-Path $repo tcl/build.tcl) `
        -log (Join-Path $out native_build.log) -journal (Join-Path $out native_build.jou) `
        -tclargs xcku5p-ffvb676-1-i lesson05g_cpll_top $out $Action
    if($LASTEXITCODE -ne 0) {throw 'CPLL native flow failed; inspect complete log.'}
} finally {Pop-Location}
if($Action -ne 'simulate') {
    & $Python (Join-Path $PSScriptRoot check_cpll_board.py) --build-dir $out
    if($LASTEXITCODE -ne 0) {throw 'CPLL build acceptance failed; do not program.'}
}
# Hardware actions are explicit and are never performed by this script.
