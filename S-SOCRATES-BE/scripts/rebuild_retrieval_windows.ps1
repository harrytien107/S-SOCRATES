param(
    [string]$BackendRoot = "",
    [string]$PythonExe = "G:\Software\S-SOCRATES\venvs\backend\Scripts\python.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $BackendRoot) {
    if ($PSScriptRoot) {
        $BackendRoot = Split-Path -Parent $PSScriptRoot
    } else {
        $BackendRoot = (Get-Location).Path
    }
}

$BackendRoot = (Resolve-Path $BackendRoot).Path

if (-not (Test-Path $PythonExe)) {
    throw "Python executable not found at $PythonExe"
}

$scriptPath = Join-Path $BackendRoot "scripts\build_quantized_index.py"
if (-not (Test-Path $scriptPath)) {
    throw "Could not find build_quantized_index.py at $scriptPath"
}

Push-Location $BackendRoot
try {
    & $PythonExe $scriptPath
}
finally {
    Pop-Location
}
