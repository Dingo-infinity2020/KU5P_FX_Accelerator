param([Parameter(Mandatory=$true)][string]$VivadoBin,[Parameter(Mandatory=$true)][string]$BuildDir)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$out=[IO.Path]::GetFullPath($BuildDir).TrimEnd('\','/')
if($out.Equals($repo,[StringComparison]::OrdinalIgnoreCase) -or $out.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'External directory required.'}
New-Item -ItemType Directory -Path $out -Force | Out-Null
Push-Location $out
try {
    if(Test-Path -LiteralPath simulation_pass.txt) {Remove-Item -LiteralPath simulation_pass.txt}
    & (Join-Path $VivadoBin xvlog.bat) --sv (Join-Path $repo rtl/i2c_register_readonly.sv) (Join-Path $repo sim/tb_i2c_register_readonly.sv)
    if($LASTEXITCODE -ne 0) {throw 'I2C compile failed.'}
    & (Join-Path $VivadoBin xelab.bat) tb_i2c_register_readonly -s i2c_readonly_test
    if($LASTEXITCODE -ne 0) {throw 'I2C elaboration failed.'}
    & (Join-Path $VivadoBin xsim.bat) i2c_readonly_test -runall
    if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath simulation_pass.txt)) {throw 'I2C simulation failed.'}
    Get-Content simulation_pass.txt
} finally {Pop-Location}
