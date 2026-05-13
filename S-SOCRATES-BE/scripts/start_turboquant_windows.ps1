param(
    [string]$BackendRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Read .env into a hashtable for the standalone TurboQuant launcher.
function Get-DotEnvMap([string]$EnvFile) {
    $map = @{}
    if (-not (Test-Path $EnvFile)) {
        throw ".env file was not found at $EnvFile"
    }

    foreach ($line in Get-Content $EnvFile) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.TrimStart().StartsWith("#")) { continue }
        $parts = $line -split "=", 2
        if ($parts.Count -eq 2) {
            $map[$parts[0].Trim()] = $parts[1].Trim()
        }
    }

    return $map
}

$BackendRoot = (Resolve-Path $BackendRoot).Path
$envMap = Get-DotEnvMap (Join-Path $BackendRoot ".env")

$serverBin = if ($envMap["LOCAL_SERVER_BIN"]) { $envMap["LOCAL_SERVER_BIN"] } else { $envMap["TURBOQUANT_SERVER_BIN"] }
$modelPath = if ($envMap["LOCAL_GGUF_PATH"]) { $envMap["LOCAL_GGUF_PATH"] } else { $envMap["LOCAL_LLM_GGUF_PATH"] }
$listenHost = if ($envMap["LOCAL_HOST"]) { $envMap["LOCAL_HOST"] } elseif ($envMap["LOCAL_LLM_HOST"]) { $envMap["LOCAL_LLM_HOST"] } else { "127.0.0.1" }
$port = if ($envMap["LOCAL_LLM_PORT"]) { $envMap["LOCAL_LLM_PORT"] } else { "8011" }
$ctx = if ($envMap["LOCAL_CTX"]) { $envMap["LOCAL_CTX"] } elseif ($envMap["TURBOQUANT_CTX"]) { $envMap["TURBOQUANT_CTX"] } else { "8192" }
$cacheType = if ($envMap["LOCAL_CACHE_TYPE"]) { $envMap["LOCAL_CACHE_TYPE"] } elseif ($envMap["TURBOQUANT_CACHE_TYPE"]) { $envMap["TURBOQUANT_CACHE_TYPE"] } else { "turbo2" }
$ngl = if ($envMap["LOCAL_NGL"]) { $envMap["LOCAL_NGL"] } elseif ($envMap["TURBOQUANT_NGL"]) { $envMap["TURBOQUANT_NGL"] } else { "99" }
$reasoningBudget = if ($envMap["LOCAL_REASONING_BUDGET"]) { $envMap["LOCAL_REASONING_BUDGET"] } elseif ($envMap["TURBOQUANT_REASONING_BUDGET"]) { $envMap["TURBOQUANT_REASONING_BUDGET"] } else { "0" }

if (-not $serverBin -or -not (Test-Path $serverBin)) {
    throw "A valid LOCAL_SERVER_BIN was not found in .env"
}
if (-not $modelPath -or -not (Test-Path $modelPath)) {
    throw "A valid LOCAL_GGUF_PATH was not found in .env"
}

& $serverBin `
    --host $listenHost `
    --port $port `
    -m $modelPath `
    -ngl $ngl `
    -c $ctx `
    --flash-attn on `
    --cache-type-k $cacheType `
    --cache-type-v $cacheType `
    --reasoning-budget $reasoningBudget `
    --jinja
