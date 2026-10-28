param(
    [Parameter(Mandatory = $true)][string]$Python,
    [Parameter(Mandatory = $true)][string]$VivadoBin,
    [string]$BuildDir,
    [switch]$Synthesize,
    [string]$Part = 'xcku5p-ffvb676-1-i'
)
$ErrorActionPreference = 'Stop'
$repoDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
if (-not $BuildDir) {
    $BuildDir = Join-Path (Split-Path $repoDir -Parent) 'build\KU5P_FX_Accelerator\lesson03_fx'
}
$buildPath = [IO.Path]::GetFullPath($BuildDir).TrimEnd('\', '/')
if ($buildPath.Equals($repoDir, [StringComparison]::OrdinalIgnoreCase) -or
    $buildPath.StartsWith($repoDir + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Build output must be outside the source repository.'
}
$vivado = Join-Path $VivadoBin 'vivado.bat'
if (-not (Test-Path -LiteralPath $vivado)) { throw 'Vivado executable not found.' }
$vivadoRoot = Split-Path ([IO.Path]::GetFullPath($VivadoBin).TrimEnd('\','/')) -Parent
New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
$verificationPath = Join-Path $buildPath 'verification.json'
foreach ($markerPath in @($verificationPath, (Join-Path $buildPath 'simulation_pass.txt'))) {
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath }
}
& $Python -B (Join-Path $PSScriptRoot 'generate_lesson03_vectors.py') --output-dir $buildPath --vivado-root $vivadoRoot
if ($LASTEXITCODE -ne 0) { throw 'FFT reference-vector generation failed; NumPy is required.' }
Push-Location $buildPath
try {
    $synthesisFlag = if ($Synthesize) { '1' } else { '0' }
    & $vivado -mode batch -log lesson03_flow.log -journal lesson03_flow.jou -notrace `
        -source (Join-Path $repoDir 'tcl\run_lesson03.tcl') -tclargs $buildPath $Part $synthesisFlag
    if ($LASTEXITCODE -ne 0) { throw 'Lesson03 project simulation/synthesis flow failed.' }
    $passPath = Join-Path $buildPath 'simulation_pass.txt'
    if (-not (Test-Path -LiteralPath $passPath)) { throw 'Missing verified simulation marker.' }
    $passText = (Get-Content -LiteralPath $passPath -Raw).Trim()
    if (-not $passText.StartsWith('PASS ')) { throw 'Invalid pass marker.' }
    $hashes = [ordered]@{}
    foreach ($name in @('rtl/two_channel_correlator.sv', 'rtl/fft_pair_512.sv',
        'rtl/channelized_x_engine.sv', 'rtl/two_channel_fft_fx.sv', 'sim/tb_two_channel_fft_fx.sv',
        'scripts/fft512_reference.py', 'scripts/generate_lesson03_vectors.py',
        'scripts/run_lesson03.ps1', 'tcl/run_lesson03.tcl', 'constraints/lesson03_ooc.xdc')) {
        $hashes[$name] = (Get-FileHash -LiteralPath (Join-Path $repoDir $name) -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $vectors = Get-Content -LiteralPath (Join-Path $buildPath 'vectors.json') -Raw | ConvertFrom-Json
    $verification = [ordered]@{
        verified_at = (Get-Date).ToString('o')
        simulation = $passText
        windows = $vectors.windows
        frames = $vectors.frames
        numpy_max_raw_component_error = $vectors.numpy_max_raw_component_error
        numpy_max_quantized_component_error = $vectors.numpy_max_quantized_component_error
        sources = $hashes
        synthesis_run_this_invocation = [bool]$Synthesize
        hardware_tested = $false
        physical_timing_closed = $false
    }
    if ($Synthesize) {
        $verification.synthesis_scope = @(Get-Content -LiteralPath (Join-Path $buildPath 'synthesis_scope.txt'))
    }
    $verification | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $verificationPath -Encoding utf8
    Write-Output $passText
} finally { Pop-Location }
