param([Parameter(Mandatory=$true)][string]$VivadoBin,[Parameter(Mandatory=$true)][string]$Python,[Parameter(Mandatory=$true)][string]$BuildDir)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$out=[IO.Path]::GetFullPath($BuildDir)
& $Python (Join-Path $PSScriptRoot pcie_boot_manifest.py) begin --profile e5 --build-dir $out
if($LASTEXITCODE -ne 0) {throw 'Reference input freeze failed'}
& (Join-Path $PSScriptRoot run_pcie_boot_test.ps1) -VivadoBin $VivadoBin -BuildDir (Join-Path $out boot_sim)
& (Join-Path $PSScriptRoot run_pcie_training_monitor_test.ps1) -VivadoBin $VivadoBin -BuildDir (Join-Path $out training_sim)
& (Join-Path $PSScriptRoot run_pcie_boot_provenance.ps1) -VivadoBin $VivadoBin -BuildDir (Join-Path $out boot_provenance_sim)
& (Join-Path $PSScriptRoot run_pcie_reference_reset.ps1) -VivadoBin $VivadoBin -BuildDir (Join-Path $out reference_reset_sim)
& $Python (Join-Path $PSScriptRoot generate_pcie_vectors.py) --output-dir (Join-Path $out application_test)
if($LASTEXITCODE -ne 0) {throw 'Application vector generation failed'}
& (Join-Path $PSScriptRoot run_pcie_application_test.ps1) -VivadoBin $VivadoBin -BuildDir (Join-Path $out application_test)
Push-Location $out
try {
    & (Join-Path $VivadoBin vivado.bat) -mode batch -notrace -log native_build.log -journal native_build.jou `
        -source (Join-Path $repo tcl/build.tcl) -tclargs xcku5p-ffvb676-1-i lesson05j_pcie_reference_top $out
    if($LASTEXITCODE -ne 0) {throw 'Reference build failed; do not program'}
} finally {Pop-Location}
& $Python (Join-Path $PSScriptRoot pcie_boot_manifest.py) finish --profile e5 --build-dir $out
if($LASTEXITCODE -ne 0) {throw 'Reference acceptance failed; do not program'}
# BUILD_ONLY: no hardware manager, programming, reset, flash or host operations.
