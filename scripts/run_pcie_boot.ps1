param([Parameter(Mandatory=$true)][string]$VivadoBin,[Parameter(Mandatory=$true)][string]$Python,[Parameter(Mandatory=$true)][string]$BuildDir)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$out=[IO.Path]::GetFullPath($BuildDir)
& $Python (Join-Path $PSScriptRoot pcie_boot_manifest.py) begin --build-dir $out
if($LASTEXITCODE -ne 0) {throw 'Input freeze failed'}
& (Join-Path $PSScriptRoot run_pcie_boot_test.ps1) -VivadoBin $VivadoBin -BuildDir (Join-Path $out boot_sim)
& (Join-Path $PSScriptRoot run_pcie_training_monitor_test.ps1) -VivadoBin $VivadoBin -BuildDir (Join-Path $out training_sim)
& $Python (Join-Path $PSScriptRoot generate_pcie_vectors.py) --output-dir (Join-Path $out application_test)
if($LASTEXITCODE -ne 0) {throw 'Vector generation failed'}
& (Join-Path $PSScriptRoot run_pcie_application_test.ps1) -VivadoBin $VivadoBin -BuildDir (Join-Path $out application_test)
Push-Location $out
try {
    & (Join-Path $VivadoBin vivado.bat) -mode batch -notrace -log native_build.log -journal native_build.jou `
        -source (Join-Path $repo tcl/build.tcl) -tclargs xcku5p-ffvb676-1-i lesson05i_pcie_boot_top $out
    if($LASTEXITCODE -ne 0) {throw 'Native boot build failed'}
} finally {Pop-Location}
& $Python (Join-Path $PSScriptRoot pcie_boot_manifest.py) finish --build-dir $out
if($LASTEXITCODE -ne 0) {throw 'Boot build acceptance failed; do not program'}
# Hardware programming, local reset and host restart are separate explicit steps.
