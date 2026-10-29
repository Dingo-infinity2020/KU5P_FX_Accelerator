param(
    [Parameter(Mandatory=$true)][string]$VivadoBin,
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$BuildDir
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$out=[IO.Path]::GetFullPath($BuildDir).TrimEnd('\','/')
if($out.Equals($repo,[StringComparison]::OrdinalIgnoreCase) -or $out.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'External directory required.'}
foreach($name in @('native_build.log','verification.json')) {
    if(Test-Path -LiteralPath (Join-Path $out $name)) {throw 'Use a fresh output directory to preserve previous evidence.'}
}
New-Item -ItemType Directory -Path $out -Force | Out-Null
& (Join-Path $PSScriptRoot run_i2c_readonly_test.ps1) -VivadoBin $VivadoBin -BuildDir (Join-Path $out i2c_sim)
& $Python (Join-Path $PSScriptRoot si5338_manifest.py) --build-dir $out
if($LASTEXITCODE -ne 0) {throw 'Read-only input freeze failed.'}
Push-Location $out
try {
    & (Join-Path $VivadoBin vivado.bat) -mode batch -source (Join-Path $repo tcl/build.tcl) `
        -log (Join-Path $out native_build.log) -journal (Join-Path $out native_build.jou) `
        -tclargs xcku5p-ffvb676-1-i lesson05f_si5338_top $out
    if($LASTEXITCODE -ne 0) {throw 'Read-only build failed; inspect native_build.log.'}
} finally {Pop-Location}
& $Python (Join-Path $PSScriptRoot check_si5338_build.py) --build-dir $out
if($LASTEXITCODE -ne 0) {throw 'Acceptance failed; do not program.'}
# No automatic programming or clock-chip configuration writes.
