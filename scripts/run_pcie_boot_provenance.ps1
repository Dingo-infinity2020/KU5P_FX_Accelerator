param([Parameter(Mandatory=$true)][string]$VivadoBin,[Parameter(Mandatory=$true)][string]$BuildDir)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$out=[IO.Path]::GetFullPath($BuildDir)
if($out.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase) -or $out.Equals($repo,[StringComparison]::OrdinalIgnoreCase)) {throw 'External directory required'}
if(Test-Path -LiteralPath $out) {throw 'Use a fresh simulation directory'}
New-Item -ItemType Directory -Path $out | Out-Null
Push-Location $out
try {
    & (Join-Path $VivadoBin xvlog.bat) --sv (Join-Path $repo rtl/pcie_boot_diagnostics.sv) (Join-Path $repo sim/tb_pcie_boot_provenance.sv) (Join-Path $VivadoBin ../data/verilog/src/glbl.v)
    if($LASTEXITCODE -ne 0) {throw 'Provenance compile failed'}
    & (Join-Path $VivadoBin xelab.bat) -L xpm -L unisims_ver tb_pcie_boot_provenance glbl -s boot_provenance
    if($LASTEXITCODE -ne 0) {throw 'Provenance elaboration failed'}
    & (Join-Path $VivadoBin xsim.bat) boot_provenance -runall -log provenance_runtime.log
    if($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath simulation_pass.txt)) {throw 'Provenance simulation failed'}
    if(Select-String -LiteralPath provenance_runtime.log -Pattern '(^|\s)(Fatal:|Error:|ERROR:)' -Quiet) {throw 'Runtime diagnostic error despite simulator exit status'}
    $result=Get-Content -LiteralPath simulation_pass.txt
    if($result -ne 'PASS boot_provenance_checks=15 events=8') {throw "Incomplete provenance result: $result"}
    $result
} finally {Pop-Location}
