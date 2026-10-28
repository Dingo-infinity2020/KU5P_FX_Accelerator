param(
    [Parameter(Mandatory=$true)][string]$Python,[Parameter(Mandatory=$true)][string]$VivadoBin,
    [string]$BuildDir,[switch]$PrepareOnly,[string]$Part='xcku5p-ffvb676-1-i',[ValidateSet(4,8)][int]$Lanes=8,
    [switch]$TrainingDebug,[switch]$PhyDebug
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
if($PhyDebug) {$TrainingDebug=$true}
if($TrainingDebug -and $Lanes -ne 4) {throw 'Training diagnostic requires x4.'}
[string[]]$profileArgs=@()
if($TrainingDebug) {$profileArgs=@('--training-debug')}
if($PhyDebug) {$profileArgs+=@('--phy-debug')}
if(-not $BuildDir) {
    $name=if($Lanes -eq 4) {'lesson05d_pcie_x4'} else {'lesson05d_pcie'}
    if($TrainingDebug) {$name='lesson05d_pcie_training'}
    if($PhyDebug) {$name='lesson05d_pcie_phy'}
    $BuildDir=Join-Path (Split-Path $repo -Parent) ('build/KU5P_FX_Accelerator/'+$name)
}
$out=[IO.Path]::GetFullPath($BuildDir).TrimEnd('\','/')
if($out.Equals($repo,[StringComparison]::OrdinalIgnoreCase) -or $out.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Build outside repository.'}
$previous=Join-Path $out build_inputs.json
if(Test-Path -LiteralPath $previous) {
    $saved=Get-Content -LiteralPath $previous -Raw | ConvertFrom-Json
    $previousLanes=if($saved.lanes) {[int]$saved.lanes} else {8}
    if($previousLanes -ne $Lanes) {throw 'Use a separate build directory for each PCIe width.'}
    if([bool]$saved.training_debug -ne [bool]$TrainingDebug) {throw 'Use a separate build directory for each diagnostic profile.'}
    if([bool]$saved.phy_debug -ne [bool]$PhyDebug) {throw 'Use a separate build directory for each PHY profile.'}
}
& $Python -B (Join-Path $PSScriptRoot generate_pcie_vectors.py) --output-dir (Join-Path $out application_test)
if($LASTEXITCODE -ne 0) {throw 'Vector preparation failed.'}
& $Python -B (Join-Path $PSScriptRoot lesson05d_manifest.py) begin --build-dir $out --lanes $Lanes @profileArgs
if($LASTEXITCODE -ne 0) {throw 'Input freeze failed.'}
& (Join-Path $PSScriptRoot run_pcie_application_test.ps1) -VivadoBin $VivadoBin -BuildDir (Join-Path $out application_test)
& (Join-Path $PSScriptRoot run_pcie_clock_monitor_test.ps1) -VivadoBin $VivadoBin -BuildDir (Join-Path $out clock_monitor_test)
if($TrainingDebug) {
    & (Join-Path $PSScriptRoot run_pcie_training_monitor_test.ps1) -VivadoBin $VivadoBin -BuildDir (Join-Path $out training_monitor_test)
}
if($PhyDebug) {
    & (Join-Path $PSScriptRoot run_pcie_phy_monitor_test.ps1) -VivadoBin $VivadoBin -BuildDir (Join-Path $out phy_monitor_test)
}
& $Python -B (Join-Path $PSScriptRoot lesson05d_manifest.py) finish --build-dir $out --lanes $Lanes @profileArgs
if($LASTEXITCODE -ne 0) {throw 'Application verification failed.'}
if($PrepareOnly) {Write-Output 'Application verified; prepare the board project through tcl/build.tcl.';return}
Push-Location $out
try {
    $top=if($Lanes -eq 4) {'lesson05d_pcie_x4_top'} else {'lesson05d_pcie_top'}
    if($TrainingDebug) {$top='lesson05d_pcie_training_top'}
    if($PhyDebug) {$top='lesson05d_pcie_phy_top'}
    & (Join-Path $VivadoBin vivado.bat) -mode batch -notrace -log board_flow.log -journal board_flow.jou `
        -source (Join-Path $repo tcl/build.tcl) -tclargs $Part $top $out all
    if($LASTEXITCODE -ne 0) {throw 'Board implementation failed.'}
    & $Python -B (Join-Path $PSScriptRoot lesson05d_manifest.py) finish --build-dir $out --implemented --lanes $Lanes @profileArgs
    if($LASTEXITCODE -ne 0) {throw 'Board evidence verification failed.'}
} finally {Pop-Location}
