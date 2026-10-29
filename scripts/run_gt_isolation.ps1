param(
    [Parameter(Mandatory=$true)][string]$VivadoBin,
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$BuildDir,
    [ValidateSet('all','simulate','implement')][string]$Action='all'
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$out=[IO.Path]::GetFullPath($BuildDir)
& $Python (Join-Path $PSScriptRoot gt_isolation_manifest.py) --build-dir $out
if($LASTEXITCODE -ne 0) {throw 'GT input freeze failed.'}
Push-Location $out
try {
    & (Join-Path $VivadoBin vivado.bat) -mode batch -source (Join-Path $repo tcl/build.tcl) `
        -log (Join-Path $out native_build.log) -journal (Join-Path $out native_build.jou) `
        -tclargs xcku5p-ffvb676-1-i lesson05e_gt_top $out $Action
    if($LASTEXITCODE -ne 0) {throw 'Native GT flow failed; inspect the full log.'}
} finally {Pop-Location}
if($Action -ne 'simulate') {
    & $Python (Join-Path $PSScriptRoot check_gt_isolation.py) accept --build-dir $out
    if($LASTEXITCODE -ne 0) {throw 'GT acceptance failed; do not program.'}
}
