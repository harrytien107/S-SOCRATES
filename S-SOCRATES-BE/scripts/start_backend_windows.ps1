param(
    [string]$BackendRoot = "",
    [string]$PythonExe = "G:\Software\S-SOCRATES\venvs\backend\Scripts\python.exe",
    [string]$ListenHost = "0.0.0.0",
    [int]$Port = 8000,
    [switch]$NoReload
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

$args = @(
    "-m",
    "uvicorn",
    "main:app",
    "--host",
    $ListenHost,
    "--port",
    "$Port",
    "--no-access-log"
)

if (-not $NoReload) {
    $args += "--reload"
}

Push-Location $BackendRoot
try {
    & $PythonExe @args
}
finally {
    Pop-Location
}
