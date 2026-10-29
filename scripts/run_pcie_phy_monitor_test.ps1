param([Parameter(Mandatory=$true)][string]$VivadoBin,[Parameter(Mandatory=$true)][string]$BuildDir)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$out=[IO.Path]::GetFullPath($BuildDir).TrimEnd('\','/')
if($out.Equals($repo,[StringComparison]::OrdinalIgnoreCase) -or $out.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Use external directory.'}
New-Item -ItemType Directory -Path $out -Force | Out-Null
Push-Location $out
try {
    if(Test-Path -LiteralPath simulation_pass.txt) {Remove-Item -LiteralPath simulation_pass.txt}
    & (Join-Path $VivadoBin xvlog.bat) --sv (Join-Path $repo rtl/pcie_phy_monitor.sv) (Join-Path $repo sim/tb_pcie_phy_monitor.sv)
    if($LASTEXITCODE -ne 0) {throw 'PHY monitor compile failed.'}
    & (Join-Path $VivadoBin xelab.bat) tb_pcie_phy_monitor -s pcie_phy_monitor_test
    if($LASTEXITCODE -ne 0) {throw 'PHY monitor elaboration failed.'}
    & (Join-Path $VivadoBin xsim.bat) pcie_phy_monitor_test -runall
    if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath simulation_pass.txt)) {throw 'PHY monitor simulation failed.'}
    Get-Content simulation_pass.txt
} finally {Pop-Location}
