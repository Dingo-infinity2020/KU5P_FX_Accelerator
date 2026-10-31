param([Parameter(Mandatory=$true)][string]$VivadoBin,[Parameter(Mandatory=$true)][string]$BuildDir)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$out=[IO.Path]::GetFullPath($BuildDir)
if($out.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase) -or $out.Equals($repo,[StringComparison]::OrdinalIgnoreCase)) {throw 'External directory required'}
if(Test-Path -LiteralPath $out) {throw 'Use a fresh simulation directory'}
New-Item -ItemType Directory -Path $out | Out-Null
Push-Location $out
try {
    & (Join-Path $VivadoBin xvlog.bat) --sv (Join-Path $repo rtl/pcie_reference_reset.sv) (Join-Path $repo sim/tb_pcie_reference_reset.sv) (Join-Path $VivadoBin ../data/verilog/src/glbl.v)
    if($LASTEXITCODE -ne 0) {throw 'Reference reset compile failed'}
    & (Join-Path $VivadoBin xelab.bat) -L unisims_ver tb_pcie_reference_reset glbl -s reference_reset
    if($LASTEXITCODE -ne 0) {throw 'Reference reset elaborate failed'}
    & (Join-Path $VivadoBin xsim.bat) reference_reset -runall -log reset_runtime.log
    if($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath simulation_pass.txt)) {throw 'Reference reset simulation failed'}
    if(Select-String -LiteralPath reset_runtime.log -Pattern '(^|\s)(Fatal:|Error:|ERROR:)' -Quiet) {throw 'Reference reset runtime error'}
    $result=Get-Content -LiteralPath simulation_pass.txt
    if($result -ne 'PASS reference_reset_checks=10') {throw "Incomplete reference reset result: $result"}
    $result
} finally {Pop-Location}
