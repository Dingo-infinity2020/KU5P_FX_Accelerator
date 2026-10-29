param([Parameter(Mandatory=$true)][string]$VivadoBin,[Parameter(Mandatory=$true)][string]$BuildDir)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$out=[IO.Path]::GetFullPath($BuildDir)
if($out.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase) -or $out.Equals($repo,[StringComparison]::OrdinalIgnoreCase)) {throw 'External directory required'}
if(Test-Path -LiteralPath $out) {throw 'Use a new diagnostic simulation directory'}
New-Item -ItemType Directory -Path $out | Out-Null
Push-Location $out
try {
    & (Join-Path $VivadoBin xvlog.bat) --sv (Join-Path $repo rtl/pcie_boot_diagnostics.sv) (Join-Path $repo sim/tb_pcie_boot_diagnostics.sv) (Join-Path $VivadoBin ../data/verilog/src/glbl.v)
    if($LASTEXITCODE -ne 0) {throw 'Boot diagnostics compile failed'}
    & (Join-Path $VivadoBin xelab.bat) -L xpm -L unisims_ver tb_pcie_boot_diagnostics glbl -s boot_diagnostics
    if($LASTEXITCODE -ne 0) {throw 'Boot diagnostics elaborate failed'}
    & (Join-Path $VivadoBin xsim.bat) boot_diagnostics -runall -log boot_runtime.log
    if($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath simulation_pass.txt)) {throw 'Boot diagnostics simulation failed'}
    if(Select-String -LiteralPath boot_runtime.log -Pattern '(^|\s)(Fatal:|Error:|ERROR:)' -Quiet) {throw 'Runtime diagnostics reported an error despite simulator exit status'}
    $result=Get-Content -LiteralPath simulation_pass.txt
    if($result -ne 'PASS boot_diagnostics_checks=14') {throw 'Incomplete diagnostic test result'}
    $result
} finally {Pop-Location}
