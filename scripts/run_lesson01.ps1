param(
    [Parameter(Mandatory = $true)][string]$Python,
    [Parameter(Mandatory = $true)][string]$VivadoBin,
    [string]$BuildDir,
    [switch]$Synthesize,
    [string]$Part
)

$ErrorActionPreference = 'Stop'
$repoDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
if (-not $BuildDir) {
    $BuildDir = Join-Path (Split-Path $repoDir -Parent) 'build\KU5P_FX_Accelerator\lesson01_power'
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
if (Test-Path -LiteralPath $passPath) { Remove-Item -LiteralPath $passPath }

& $Python (Join-Path $PSScriptRoot 'generate_lesson01_vectors.py') --output-dir $buildPath
if ($LASTEXITCODE -ne 0) { throw 'Reference-vector generation failed.' }
[IO.File]::WriteAllText((Join-Path $buildPath 'run_sim.tcl'), "log_wave -r /tb_complex_power_accumulator/dut/*`nrun all`nquit`n", [Text.UTF8Encoding]::new($false))

Push-Location $buildPath
try {
    & (Join-Path $VivadoBin 'xvlog.bat') --sv (Join-Path $repoDir 'rtl\complex_power_accumulator.sv') (Join-Path $repoDir 'sim\tb_complex_power_accumulator.sv')
    if ($LASTEXITCODE -ne 0) { throw 'xvlog compilation failed.' }
    & (Join-Path $VivadoBin 'xelab.bat') -debug typical -s lesson01_sim tb_complex_power_accumulator
    if ($LASTEXITCODE -ne 0) { throw 'xelab elaboration failed.' }
    & (Join-Path $VivadoBin 'xsim.bat') lesson01_sim -wdb lesson01_power.wdb -tclbatch run_sim.tcl
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $passPath)) {
        throw 'Simulation failed or did not reach its verified pass marker.'
    }
    Get-Content -LiteralPath $passPath

    if ($Synthesize) {
        $synthesisArgs = @('-mode', 'batch', '-nolog', '-nojournal', '-notrace',
            '-source', (Join-Path $repoDir 'tcl\synth_lesson01.tcl'), '-tclargs', $buildPath)
        if ($Part) { $synthesisArgs += $Part }
        & (Join-Path $VivadoBin 'vivado.bat') @synthesisArgs
        if ($LASTEXITCODE -ne 0) { throw 'Out-of-context synthesis failed.' }
    }
} finally {
    Pop-Location
}
