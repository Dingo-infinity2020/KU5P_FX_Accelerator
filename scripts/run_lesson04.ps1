param(
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$VivadoBin,
    [string]$BuildDir,
    [switch]$Synthesize,
    [switch]$PrepareOnly,
    [string]$Part='xcku5p-ffvb676-1-i'
)
$ErrorActionPreference='Stop'
$repoDir=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
if(-not $BuildDir) { $BuildDir=Join-Path (Split-Path $repoDir -Parent) 'build\KU5P_FX_Accelerator\lesson04_pfb' }
$buildPath=[IO.Path]::GetFullPath($BuildDir).TrimEnd('\','/')
if($buildPath.Equals($repoDir,[StringComparison]::OrdinalIgnoreCase) -or
    $buildPath.StartsWith($repoDir+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Build outside the repository.' }
$vivado=Join-Path $VivadoBin 'vivado.bat'
if(-not (Test-Path -LiteralPath $vivado)) { throw 'Vivado not found.' }
$vivadoRoot=Split-Path ([IO.Path]::GetFullPath($VivadoBin).TrimEnd('\','/')) -Parent
New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
& $Python -B (Join-Path $PSScriptRoot 'generate_lesson04_vectors.py') --output-dir $buildPath --vivado-root $vivadoRoot
if($LASTEXITCODE -ne 0) { throw 'Reference checks failed.' }
& $Python -B (Join-Path $PSScriptRoot 'lesson04_manifest.py') begin --build-dir $buildPath
if($LASTEXITCODE -ne 0) { throw 'Failed to freeze build inputs.' }
if($PrepareOnly) { Write-Output 'Prepared references and input hashes; drive Vivado with MCP next.'; return }
Push-Location $buildPath
try {
    $action=if($Synthesize) { 'all' } else { 'simulate' }
    & $vivado -mode batch -notrace -log lesson04_flow.log -journal lesson04_flow.jou `
        -source (Join-Path $repoDir 'tcl\run_lesson04.tcl') -tclargs $buildPath $Part $action
    if($LASTEXITCODE -ne 0) { throw 'Lesson04 Vivado flow failed.' }
    $proofArgs=@('finish','--build-dir',$buildPath)
    if($Synthesize) { $proofArgs+='--synthesized' }
    & $Python -B (Join-Path $PSScriptRoot 'lesson04_manifest.py') @proofArgs
    if($LASTEXITCODE -ne 0) { throw 'Artifact verification failed.' }
} finally { Pop-Location }
