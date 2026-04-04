param(
    [string]$BackendRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$WorkspaceRoot = "",
    [string]$VsBuildToolsRoot = "D:\CODE\Visual Studio Build Tools",
    [switch]$RemoveWorkspace,
    [switch]$RemoveVenv,
    [switch]$RestoreEnv,
    [switch]$RemoveVisualStudioBuildTools,
    [switch]$RemoveCudaToolkit,
    [switch]$RemoveScoopPackages,
    [switch]$Purge
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-CommandAvailable([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Remove-PathIfExists {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if (Test-Path $Path) {
        Write-Host "Xóa $Path"
        Remove-Item -Recurse -Force $Path
    }
}

function Read-SetupState {
    param(
        [Parameter(Mandatory = $true)][string]$StateFile
    )

    if (-not (Test-Path $StateFile)) {
        return $null
    }

    try {
        return Get-Content $StateFile -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "⚠ Không đọc được state file: $StateFile"
        return $null
    }
}

function Remove-TurboQuantEnvKeys {
    param(
        [Parameter(Mandatory = $true)][string]$EnvFile
    )

    if (-not (Test-Path $EnvFile)) {
        return
    }

    $keysToRemove = @(
        "LOCAL_LLM_BACKEND",
        "LOCAL_LLM_AUTOSTART",
        "LOCAL_LLM_HOST",
        "LOCAL_LLM_PORT",
        "LOCAL_LLM_TIMEOUT_S",
        "LOCAL_LLM_MODEL_NAME",
        "LOCAL_LLM_GGUF_PATH",
        "TURBOQUANT_SERVER_BIN",
        "TURBOQUANT_CACHE_TYPE",
        "TURBOQUANT_NGL",
        "TURBOQUANT_CTX"
    )

    $lines = Get-Content $EnvFile -ErrorAction SilentlyContinue
    if ($null -eq $lines) {
        return
    }

    $filteredLines = foreach ($line in $lines) {
        $shouldRemove = $false
        foreach ($key in $keysToRemove) {
            if ($line -match "^\Q$key\E=") {
                $shouldRemove = $true
                break
            }
        }

        if (-not $shouldRemove) {
            $line
        }
    }

    Set-Content -Path $EnvFile -Value $filteredLines -Encoding UTF8
}

function Restore-Or-PruneEnvFile {
    param(
        [Parameter(Mandatory = $true)][string]$EnvFile,
        [string]$BackupFile = "",
        [bool]$CreatedEnvFile = $false
    )

    if ($BackupFile -and (Test-Path $BackupFile)) {
        Write-Host "Khôi phục .env từ backup"
        Copy-Item $BackupFile $EnvFile -Force
        Remove-Item $BackupFile -Force
        return
    }

    if (Test-Path $EnvFile) {
        Write-Host "Gỡ các biến TurboQuant khỏi .env"
        Remove-TurboQuantEnvKeys -EnvFile $EnvFile

        if ($CreatedEnvFile) {
            Write-Host "ℹ .env được tạo bởi setup, nhưng chỉ xóa các dòng TurboQuant để giữ lại cấu hình khác."
        }
    }
}

function Remove-ScoopPackage {
    param(
        [Parameter(Mandatory = $true)][string]$PackageName
    )

    if (-not (Test-CommandAvailable scoop)) {
        Write-Host "⚠ Không có scoop, bỏ qua gỡ $PackageName"
        return
    }

    Write-Host "Gỡ $PackageName qua scoop..."
    & scoop uninstall $PackageName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠ Gỡ $PackageName không thành công hoặc package chưa được cài."
    }
}

if (-not $PSBoundParameters.ContainsKey("RemoveWorkspace")) {
    $RemoveWorkspace = $true
}
if (-not $PSBoundParameters.ContainsKey("RemoveVenv")) {
    $RemoveVenv = $true
}
if (-not $PSBoundParameters.ContainsKey("RestoreEnv")) {
    $RestoreEnv = $true
}

if ($Purge) {
    $RemoveVisualStudioBuildTools = $true
    $RemoveCudaToolkit = $true
    $RemoveScoopPackages = $true
}

$BackendRoot = (Resolve-Path $BackendRoot).Path
if (-not $WorkspaceRoot) {
    $WorkspaceRoot = Join-Path $BackendRoot ".local-llm"
}
$WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)
$StateFile = Join-Path $WorkspaceRoot "turboquant-setup-state.json"
$EnvFile = Join-Path $BackendRoot ".env"
$EnvBackupFile = Join-Path $BackendRoot ".env.turboquant.backup"

$state = Read-SetupState -StateFile $StateFile
if ($state) {
    if ($state.workspaceRoot) {
        $WorkspaceRoot = [System.IO.Path]::GetFullPath([string]$state.workspaceRoot)
        $StateFile = Join-Path $WorkspaceRoot "turboquant-setup-state.json"
    }
    if ($state.envFile) {
        $EnvFile = [System.IO.Path]::GetFullPath([string]$state.envFile)
    }
    if ($state.envBackupFile) {
        $EnvBackupFile = [System.IO.Path]::GetFullPath([string]$state.envBackupFile)
    }
    if ($state.vsBuildToolsRoot) {
        $VsBuildToolsRoot = [System.IO.Path]::GetFullPath([string]$state.vsBuildToolsRoot)
    }
}

$RepoDir = if ($state -and $state.repoDir) {
    [System.IO.Path]::GetFullPath([string]$state.repoDir)
} else {
    Join-Path $WorkspaceRoot "llama-cpp-turboquant-cuda"
}

$BuildDir = if ($state -and $state.buildDir) {
    [System.IO.Path]::GetFullPath([string]$state.buildDir)
} else {
    Join-Path $RepoDir "build-win-cuda"
}

$DownloadsDir = if ($state -and $state.downloadsDir) {
    [System.IO.Path]::GetFullPath([string]$state.downloadsDir)
} else {
    Join-Path $WorkspaceRoot "downloads"
}

$VenvDir = if ($state -and $state.venvDir) {
    [System.IO.Path]::GetFullPath([string]$state.venvDir)
} else {
    Join-Path $BackendRoot ".venv"
}

Write-Step "Hoàn tác cấu hình TurboQuant"

if ($RestoreEnv) {
    Restore-Or-PruneEnvFile -EnvFile $EnvFile -BackupFile $EnvBackupFile -CreatedEnvFile ([bool]($state -and $state.createdEnvFile))
}

if ($RemoveVenv) {
    Remove-PathIfExists -Path $VenvDir
}

if ($RemoveWorkspace) {
    Remove-PathIfExists -Path $BuildDir
    Remove-PathIfExists -Path $RepoDir
    Remove-PathIfExists -Path $DownloadsDir
    if (Test-Path $StateFile) {
        Remove-Item $StateFile -Force
    }
    if ($WorkspaceRoot -and (Test-Path $WorkspaceRoot)) {
        $remainingItems = Get-ChildItem -Path $WorkspaceRoot -Force -ErrorAction SilentlyContinue
        if (-not $remainingItems) {
            Remove-PathIfExists -Path $WorkspaceRoot
        }
    }
}

if ($RemoveVisualStudioBuildTools) {
    Remove-PathIfExists -Path $VsBuildToolsRoot
}

if ($RemoveCudaToolkit) {
    if (Test-CommandAvailable scoop) {
        Remove-ScoopPackage -PackageName "cuda"
    }
    else {
        Write-Host "⚠ Không có scoop nên không thể gỡ CUDA Toolkit đã cài qua scoop."
    }
}

if ($RemoveScoopPackages) {
    foreach ($packageName in @("git", "cmake", "ninja", "python")) {
        Remove-ScoopPackage -PackageName $packageName
    }
}

Write-Step "Hoàn tất"
Write-Host "Backend root : $BackendRoot"
Write-Host "Workspace    : $WorkspaceRoot"
Write-Host "VS BuildTools : $VsBuildToolsRoot"
Write-Host "Env file     : $EnvFile"