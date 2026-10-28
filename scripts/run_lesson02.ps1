param(
    [Parameter(Mandatory = $true)][string]$Python,
    [Parameter(Mandatory = $true)][string]$VivadoBin,
    [string]$BuildDir,
    [switch]$Synthesize,
    [switch]$CreateProject,
    [string]$Part = 'xcku5p-ffvb676-1-i'
)

$ErrorActionPreference = 'Stop'
$repoDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
if (-not $BuildDir) {
    $BuildDir = Join-Path (Split-Path $repoDir -Parent) 'build\KU5P_FX_Accelerator\lesson02_x'
}
$buildPath = [IO.Path]::GetFullPath($BuildDir).TrimEnd('\', '/')
if ($buildPath.Equals($repoDir, [StringComparison]::OrdinalIgnoreCase) -or
    $buildPath.StartsWith($repoDir + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Build output must be outside the source repository.'
}
foreach ($toolName in @('xvlog.bat', 'xelab.bat', 'xsim.bat', 'vivado.bat')) {
    if (-not (Test-Path -LiteralPath (Join-Path $VivadoBin $toolName))) {
        throw "Missing Vivado tool: $toolName"
    }
}
New-Item -ItemType Directory -Path $buildPath -Force | Out-Null
$passPath = Join-Path $buildPath 'simulation_pass.txt'
$verificationPath = Join-Path $buildPath 'verification.json'
foreach ($markerPath in @($passPath, $verificationPath)) {
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath }
}

& $Python (Join-Path $PSScriptRoot 'generate_lesson02_vectors.py') --output-dir $buildPath
if ($LASTEXITCODE -ne 0) { throw 'Reference-vector generation failed.' }
[IO.File]::WriteAllText((Join-Path $buildPath 'run_sim.tcl'),
    "log_wave -r /tb_two_channel_correlator/dut/*`nrun all`nquit`n", [Text.UTF8Encoding]::new($false))

Push-Location $buildPath
try {
    & (Join-Path $VivadoBin 'xvlog.bat') --sv (Join-Path $repoDir 'rtl\two_channel_correlator.sv') (Join-Path $repoDir 'sim\tb_two_channel_correlator.sv')
    if ($LASTEXITCODE -ne 0) { throw 'xvlog compilation failed.' }
    & (Join-Path $VivadoBin 'xelab.bat') -debug typical -s lesson02_sim tb_two_channel_correlator
    if ($LASTEXITCODE -ne 0) { throw 'xelab elaboration failed.' }
    & (Join-Path $VivadoBin 'xsim.bat') lesson02_sim -wdb lesson02_x.wdb -tclbatch run_sim.tcl
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $passPath)) {
        throw 'Simulation failed or did not reach its verified pass marker.'
    }
    $passText = (Get-Content -LiteralPath $passPath -Raw).Trim()
    if (-not $passText.StartsWith('PASS ')) { throw 'Invalid simulation pass marker.' }
    Write-Output $passText

    if ($Synthesize) {
        & (Join-Path $VivadoBin 'vivado.bat') -mode batch -nolog -nojournal -notrace `
            -source (Join-Path $repoDir 'tcl\synth_lesson02.tcl') -tclargs $buildPath $Part
        if ($LASTEXITCODE -ne 0) { throw 'Out-of-context synthesis failed.' }
    }
    if ($CreateProject) {
        & (Join-Path $VivadoBin 'vivado.bat') -mode batch -nolog -nojournal -notrace `
            -source (Join-Path $repoDir 'tcl\create_lesson02_project.tcl') -tclargs $buildPath $Part
        if ($LASTEXITCODE -ne 0) { throw 'GUI project creation failed.' }
    }

    $sourceHashes = [ordered]@{}
    foreach ($relativePath in @('rtl/two_channel_correlator.sv', 'sim/tb_two_channel_correlator.sv',
        'scripts/generate_lesson02_vectors.py', 'scripts/run_lesson02.ps1',
        'constraints/lesson02_ooc.xdc', 'tcl/synth_lesson02.tcl', 'tcl/create_lesson02_project.tcl')) {
        $sourceHashes[$relativePath] = (Get-FileHash -LiteralPath (Join-Path $repoDir $relativePath) -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $vectors = Get-Content -LiteralPath (Join-Path $buildPath 'vectors.json') -Raw | ConvertFrom-Json
    $verification = [ordered]@{
        verified_at = (Get-Date).ToString('o')
        simulation = $passText
        vector_windows = $vectors.windows
        vector_sample_pairs = $vectors.sample_pairs
        sources = $sourceHashes
        synthesis_run_this_invocation = [bool]$Synthesize
        project_requested = [bool]$CreateProject
        hardware_tested = $false
        physical_timing_closed = $false
    }
    if ($Synthesize) {
        $verification.synthesis_scope = @(Get-Content -LiteralPath (Join-Path $buildPath 'synthesis_scope.txt'))
    }
    $verification | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $verificationPath -Encoding utf8
} finally {
    Pop-Location
}
