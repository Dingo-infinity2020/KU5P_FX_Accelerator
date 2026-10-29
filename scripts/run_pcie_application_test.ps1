param([Parameter(Mandatory=$true)][string]$VivadoBin,[Parameter(Mandatory=$true)][string]$BuildDir)
$ErrorActionPreference='Stop'
$repoDir=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$out=[IO.Path]::GetFullPath($BuildDir).TrimEnd('\','/')
if($out.Equals($repoDir,[StringComparison]::OrdinalIgnoreCase) -or $out.StartsWith($repoDir+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Use external directory.' }
New-Item -ItemType Directory -Path $out -Force | Out-Null
Push-Location $out
try {
    if(Test-Path -LiteralPath simulation_pass.txt) { Remove-Item -LiteralPath simulation_pass.txt }
    & (Join-Path $VivadoBin xvlog.bat) --sv (Join-Path $repoDir rtl/dma_pattern_source.sv) (Join-Path $repoDir rtl/pcie_test_endpoint.sv) (Join-Path $repoDir sim/tb_pcie_test_endpoint.sv)
    if($LASTEXITCODE -ne 0) { throw 'Application compile failed.' }
    & (Join-Path $VivadoBin xelab.bat) tb_pcie_test_endpoint -s pcie_application
    if($LASTEXITCODE -ne 0) { throw 'Application elaboration failed.' }
    & (Join-Path $VivadoBin xsim.bat) pcie_application -runall
    if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath simulation_pass.txt)) { throw 'Application simulation failed.' }
    Get-Content simulation_pass.txt
} finally { Pop-Location }
