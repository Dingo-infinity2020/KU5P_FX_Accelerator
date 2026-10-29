param([Parameter(Mandatory=$true)][string]$VivadoBin,[Parameter(Mandatory=$true)][string]$BuildDir)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$out=[IO.Path]::GetFullPath($BuildDir).TrimEnd('\','/')
if($out.Equals($repo,[StringComparison]::OrdinalIgnoreCase) -or $out.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Use external directory.'}
New-Item -ItemType Directory -Path $out -Force | Out-Null
Push-Location $out
try {
    if(Test-Path -LiteralPath simulation_pass.txt) {Remove-Item -LiteralPath simulation_pass.txt}
    & (Join-Path $VivadoBin xvlog.bat) --sv (Join-Path $repo rtl/pcie_training_monitor.sv) (Join-Path $repo sim/tb_pcie_training_monitor.sv) (Join-Path $VivadoBin ../data/verilog/src/glbl.v)
    if($LASTEXITCODE -ne 0) {throw 'Training monitor compile failed.'}
    & (Join-Path $VivadoBin xelab.bat) -L xpm -L unisims_ver tb_pcie_training_monitor glbl -s pcie_training_monitor_test
    if($LASTEXITCODE -ne 0) {throw 'Training monitor elaboration failed.'}
    & (Join-Path $VivadoBin xsim.bat) pcie_training_monitor_test -runall
    if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath simulation_pass.txt)) {throw 'Training monitor simulation failed.'}
    Get-Content simulation_pass.txt
} finally {Pop-Location}
