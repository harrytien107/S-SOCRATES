param(
    [string]$BackendRoot = "",
    [string]$PythonExe = "",
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
$EnvFile = Join-Path $BackendRoot ".env"

# Read .env and publish its values to the current PowerShell process.
function Import-DotEnvValues {
    param([string]$EnvFilePath)
    $values = @{}
    if (-not (Test-Path $EnvFilePath)) {
        return $values
    }
    foreach ($line in Get-Content -Path $EnvFilePath) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#") -or $trimmed -notmatch "=") {
            continue
        }
        $parts = $trimmed.Split("=", 2)
        $key = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        $values[$key] = $value
        [Environment]::SetEnvironmentVariable($key, $value, "Process")
    }
    return $values
}

# Resolve a string setting from .env, process env, or a fallback value.
function Get-SettingOrDefault {
    param([hashtable]$EnvMap, [string]$Name, [string]$DefaultValue = "")
    if ($EnvMap.ContainsKey($Name) -and -not [string]::IsNullOrWhiteSpace($EnvMap[$Name])) {
        return [string]$EnvMap[$Name]
    }
    $fromEnv = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
        return $fromEnv
    }
    return $DefaultValue
}

# Check whether an executable path or command name can be used.
function Test-ExecutableAvailable {
    param([string]$Command)
    if (Test-Path $Command) {
        return $true
    }
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

# Add or replace multiple .env keys and mirror them into this process.
function Set-DotEnvValues {
    param([string]$EnvFilePath, [hashtable]$Values)
    if (-not (Test-Path $EnvFilePath)) {
        throw ".env file not found at $EnvFilePath"
    }
    $content = Get-Content -Path $EnvFilePath -Raw
    foreach ($key in $Values.Keys) {
        $value = [string]$Values[$key]
        $pattern = "(?m)^" + [regex]::Escape($key) + "=.*$"
        $replacement = "$key=$value"
        if ($content -match $pattern) {
            $content = [regex]::Replace($content, $pattern, $replacement)
        } else {
            if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) {
                $content += "`r`n"
            }
            $content += "$replacement`r`n"
        }
        [Environment]::SetEnvironmentVariable($key, $value, "Process")
    }
    Set-Content -Path $EnvFilePath -Value $content -Encoding UTF8
}

# Stop any process currently listening on a local port.
function Stop-ListeningProcessIfAny {
    param([int]$TargetPort)
    try {
        $conns = Get-NetTCPConnection -LocalPort $TargetPort -State Listen -ErrorAction Stop
    } catch {
        return
    }
    foreach ($conn in $conns) {
        try {
            Stop-Process -Id $conn.OwningProcess -Force -ErrorAction Stop
        } catch {
            # Ignore stale processes that disappear between lookup and stop.
        }
    }
}

# Resolve an integer setting from .env or return a default value.
function Get-EnvIntOrDefault {
    param([hashtable]$EnvMap, [string]$Name, [int]$DefaultValue)
    $raw = Get-SettingOrDefault -EnvMap $EnvMap -Name $Name
    $parsed = 0
    if ([int]::TryParse($raw, [ref]$parsed)) {
        return $parsed
    }
    return $DefaultValue
}

$envMap = Import-DotEnvValues -EnvFilePath $EnvFile
if (-not $PythonExe) {
    $PythonExe = Get-SettingOrDefault -EnvMap $envMap -Name "BACKEND_PYTHON_EXE" -DefaultValue "python"
}
if ($PythonExe -eq "python") {
    $venvRoot = Get-SettingOrDefault -EnvMap $envMap -Name "BACKEND_VENV_ROOT"
    if ($venvRoot) {
        $venvPython = Join-Path $venvRoot "Scripts\python.exe"
        if (Test-Path $venvPython) {
            $PythonExe = $venvPython
        }
    }
}
if (-not (Test-ExecutableAvailable -Command $PythonExe)) {
    throw "Python executable not found. Set BACKEND_PYTHON_EXE in .env or pass -PythonExe."
}

Set-DotEnvValues -EnvFilePath $EnvFile -Values @{
    DEPLOYMENT_MODE = "local"
    LOCAL_LLM_AUTOSTART = "1"
    LOCAL_BASELINE_AUTOSTART = "0"
    LOCAL_CACHE_TYPE = "turbo2"
}

$turboPort = Get-EnvIntOrDefault -EnvMap $envMap -Name "LOCAL_LLM_PORT" -DefaultValue 8011
$baselinePort = Get-EnvIntOrDefault -EnvMap $envMap -Name "LOCAL_BASELINE_PORT" -DefaultValue 8012
Stop-ListeningProcessIfAny -TargetPort $turboPort
Stop-ListeningProcessIfAny -TargetPort $baselinePort

$args = @("-m", "uvicorn", "main:app", "--host", $ListenHost, "--port", "$Port", "--no-access-log")
if (-not $NoReload) {
    $args += "--reload"
}

Push-Location $BackendRoot
try {
    & $PythonExe @args
} finally {
    Pop-Location
}
