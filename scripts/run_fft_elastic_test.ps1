param(
    [Parameter(Mandatory=$true)][string]$VivadoBin,
    [Parameter(Mandatory=$true)][string]$BuildDir
)
$ErrorActionPreference='Stop'
$repoDir=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
$outputDir=[IO.Path]::GetFullPath($BuildDir).TrimEnd('\','/')
if($outputDir.Equals($repoDir,[StringComparison]::OrdinalIgnoreCase) -or
    $outputDir.StartsWith($repoDir+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Build outside repository.' }
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
Push-Location $outputDir
try {
    if(Test-Path -LiteralPath 'elastic_pass.txt') { Remove-Item -LiteralPath 'elastic_pass.txt' }
    & (Join-Path $VivadoBin 'xvlog.bat') --sv (Join-Path $repoDir 'rtl/fft_pair_512_pipeline.sv') (Join-Path $repoDir 'sim/tb_fft_pair_elastic.sv')
    if($LASTEXITCODE -ne 0) { throw 'Elastic compile failed.' }
    & (Join-Path $VivadoBin 'xelab.bat') tb_fft_pair_elastic -s elastic_test
    if($LASTEXITCODE -ne 0) { throw 'Elastic elaboration failed.' }
    & (Join-Path $VivadoBin 'xsim.bat') elastic_test -runall
    if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath 'elastic_pass.txt')) { throw 'Elastic test failed.' }
    Get-Content -LiteralPath 'elastic_pass.txt'
} finally { Pop-Location }
