param([Parameter(Mandatory=$true)][string]$VivadoBin,[Parameter(Mandatory=$true)][string]$BuildDir)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$out=[IO.Path]::GetFullPath($BuildDir).TrimEnd('\','/')
if($out.Equals($repo,[StringComparison]::OrdinalIgnoreCase) -or $out.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Use external directory.'}
New-Item -ItemType Directory -Path $out -Force | Out-Null
Push-Location $out
try {
    if(Test-Path -LiteralPath simulation_pass.txt) {Remove-Item -LiteralPath simulation_pass.txt}
    $taskGlbl=[IO.Path]::GetFullPath((Join-Path $VivadoBin '../data/verilog/src/glbl.v'))
    & (Join-Path $VivadoBin xvlog.bat) --sv (Join-Path $repo sim/tb_pcie_monitor_pll.sv) $taskGlbl
    if($LASTEXITCODE -ne 0) {throw 'MMCM compile failed.'}
    & (Join-Path $VivadoBin xelab.bat) -L unisims_ver tb_pcie_monitor_pll glbl -s pcie_monitor_pll_test
    if($LASTEXITCODE -ne 0) {throw 'MMCM elaboration failed.'}
    & (Join-Path $VivadoBin xsim.bat) pcie_monitor_pll_test -runall
    if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath simulation_pass.txt)) {throw 'MMCM simulation failed.'}
    Get-Content simulation_pass.txt
} finally {Pop-Location}
