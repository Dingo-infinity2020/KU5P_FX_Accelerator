param([Parameter(Mandatory=$true)][string]$VivadoBin,[Parameter(Mandatory=$true)][string]$BuildDir,[ValidateSet('e5','e6')][string]$Profile='e5')
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$out=[IO.Path]::GetFullPath($BuildDir)
if($out.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase) -or $out.Equals($repo,[StringComparison]::OrdinalIgnoreCase)) {throw 'External directory required'}
if(Test-Path -LiteralPath $out) {throw 'Use a fresh simulation directory'}
New-Item -ItemType Directory -Path $out | Out-Null
Push-Location $out
try {
    $name=if($Profile -eq 'e5'){'pcie_reference_reset'}else{'pcie_perst_reference_reset'}
    $expected=if($Profile -eq 'e5'){'PASS reference_reset_checks=10'}else{'PASS perst_reference_reset_checks=7'}
    & (Join-Path $VivadoBin xvlog.bat) --sv (Join-Path $repo "rtl/$name.sv") (Join-Path $repo "sim/tb_$name.sv") (Join-Path $VivadoBin ../data/verilog/src/glbl.v)
    if($LASTEXITCODE -ne 0) {throw 'Reference reset compile failed'}
    & (Join-Path $VivadoBin xelab.bat) -L unisims_ver "tb_$name" glbl -s reference_reset
    if($LASTEXITCODE -ne 0) {throw 'Reference reset elaborate failed'}
    & (Join-Path $VivadoBin xsim.bat) reference_reset -runall -log reset_runtime.log
    if($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath simulation_pass.txt)) {throw 'Reference reset simulation failed'}
    if(Select-String -LiteralPath reset_runtime.log -Pattern '(^|\s)(Fatal:|Error:|ERROR:)' -Quiet) {throw 'Reference reset runtime error'}
    $result=Get-Content -LiteralPath simulation_pass.txt
    if($result -ne $expected) {throw "Incomplete reference reset result: $result"}
    $result
} finally {Pop-Location}
