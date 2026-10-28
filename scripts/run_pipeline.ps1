param(
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$VivadoBin,
    [string]$BuildDir,
    [switch]$Synthesize,
    [switch]$Route,
    [switch]$PrepareOnly,
    [string]$Part='xcku5p-ffvb676-1-i'
)
$ErrorActionPreference='Stop'
$repoDir=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
if(-not $BuildDir) { $BuildDir=Join-Path (Split-Path $repoDir -Parent) 'build\KU5P_FX_Accelerator\lesson05c_pipeline' }
$buildPath=[IO.Path]::GetFullPath($BuildDir).TrimEnd('\','/')
if($buildPath.Equals($repoDir,[StringComparison]::OrdinalIgnoreCase) -or
    $buildPath.StartsWith($repoDir+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Build outside repository.' }
$vivado=Join-Path $VivadoBin 'vivado.bat'
if(-not (Test-Path -LiteralPath $vivado)) { throw 'Vivado not found.' }
$vivadoRoot=Split-Path ([IO.Path]::GetFullPath($VivadoBin).TrimEnd('\','/')) -Parent
New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
& $Python -B (Join-Path $PSScriptRoot 'generate_pipeline_vectors.py') --output-dir $buildPath --vivado-root $vivadoRoot
if($LASTEXITCODE -ne 0) { throw 'Reference failed.' }
& $Python -B (Join-Path $PSScriptRoot 'pipeline_manifest.py') begin --build-dir $buildPath
if($LASTEXITCODE -ne 0) { throw 'Input freeze failed.' }
& (Join-Path $PSScriptRoot 'run_fft_elastic_test.ps1') -VivadoBin $VivadoBin -BuildDir (Join-Path $buildPath 'elastic_test')
if($PrepareOnly) { Write-Output 'References and hashes prepared; drive tcl/run_pipeline.tcl with MCP.'; return }
Push-Location $buildPath
try {
    $action=if($Route) { 'route' } elseif($Synthesize) { 'all' } else { 'simulate' }
    & $vivado -mode batch -notrace -log pipeline_flow.log -journal pipeline_flow.jou `
        -source (Join-Path $repoDir 'tcl/run_pipeline.tcl') -tclargs $buildPath $Part $action
    if($LASTEXITCODE -ne 0) { throw 'Vivado pipeline flow failed.' }
    $proofArgs=@('finish','--build-dir',$buildPath)
    if($Synthesize -or $Route) { $proofArgs+='--synthesized' }
    if($Route) { $proofArgs+='--routed' }
    & $Python -B (Join-Path $PSScriptRoot 'pipeline_manifest.py') @proofArgs
    if($LASTEXITCODE -ne 0) { throw 'Pipeline evidence verification failed.' }
} finally { Pop-Location }
