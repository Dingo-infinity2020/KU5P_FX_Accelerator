param(
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$VivadoBin,
    [string]$BuildDir,
    [switch]$Implement,
    [switch]$PrepareOnly
)
$ErrorActionPreference='Stop'
$repoDir=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\','/')
if(-not $BuildDir) { $BuildDir=Join-Path (Split-Path $repoDir -Parent) 'build\KU5P_FX_Accelerator\lesson05_board' }
$buildPath=[IO.Path]::GetFullPath($BuildDir).TrimEnd('\','/')
if($buildPath.Equals($repoDir,[StringComparison]::OrdinalIgnoreCase) -or
    $buildPath.StartsWith($repoDir+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Build outside the repository.' }
$vivado=Join-Path $VivadoBin 'vivado.bat'
if(-not (Test-Path -LiteralPath $vivado)) { throw 'Vivado not found.' }
$vivadoRoot=Split-Path ([IO.Path]::GetFullPath($VivadoBin).TrimEnd('\','/')) -Parent
New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
& $Python -B (Join-Path $PSScriptRoot 'generate_lesson05_vectors.py') --output-dir $buildPath --vivado-root $vivadoRoot
if($LASTEXITCODE -ne 0) { throw 'Reference generation failed.' }
& $Python -B (Join-Path $PSScriptRoot 'lesson05_manifest.py') begin --build-dir $buildPath
if($LASTEXITCODE -ne 0) { throw 'Input freeze failed.' }
if($PrepareOnly) { Write-Output 'Ready for MCP-driven lesson05 build.'; return }
Push-Location $buildPath
try {
    $action=if($Implement) { 'all' } else { 'simulate' }
    & $vivado -mode batch -notrace -log lesson05_flow.log -journal lesson05_flow.jou `
        -source (Join-Path $repoDir 'tcl\build.tcl') -tclargs xcku5p-ffvb676-1-i lesson05_board_top $buildPath $action
    if($LASTEXITCODE -ne 0) { throw 'Lesson05 build failed.' }
    $argsProof=@('finish','--build-dir',$buildPath)
    if($Implement) { $argsProof+='--implemented' }
    & $Python -B (Join-Path $PSScriptRoot 'lesson05_manifest.py') @argsProof
    if($LASTEXITCODE -ne 0) { throw 'Output verification failed.' }
} finally { Pop-Location }
