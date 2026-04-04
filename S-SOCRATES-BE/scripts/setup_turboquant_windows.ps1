param(
    [string]$BackendRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$WorkspaceRoot = "",
    [string]$TurboQuantRepo = "https://github.com/spiritbuun/llama-cpp-turboquant-cuda.git",
    [string]$TurboQuantBranch = "feature/turboquant-kv-cache",
    [string]$VsBuildToolsRoot = "D:\CODE\Visual Studio Build Tools",
    [Parameter(Mandatory = $true)]
    [string]$ModelPath,
    [string]$CudaArch = "86",
    [int]$LocalLlmPort = 8011,
    [int]$TurboQuantCtx = 8192,
    [string]$TurboQuantCacheType = "turbo2",
    [int]$TurboQuantNgl = 99,
    [switch]$SkipCudaInstall,
    [switch]$ForceReconfigure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-ScoopInstalled {
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        throw "Không tìm thấy scoop. Hãy cài Scoop trước rồi chạy lại script."
    }
}

function Test-CommandAvailable([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-ScoopPackage {
    param(
        [Parameter(Mandatory = $true)][string]$PackageSpec,
        [string]$CheckCommand = "",
        [string]$PostInstallCheck = ""
    )

    if ($CheckCommand -and (Test-CommandAvailable $CheckCommand)) {
        Write-Host "✔ Đã có $PackageSpec"
        return
    }

    Write-Host "Cài $PackageSpec qua scoop..."
    $scoopArgs = @("install", $PackageSpec)
    & scoop @scoopArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Cài $PackageSpec thất bại."
    }

    if ($PostInstallCheck -and -not (Test-CommandAvailable $PostInstallCheck)) {
        Write-Host "⚠ Cài xong nhưng chưa thấy lệnh $PostInstallCheck trong PATH ngay lúc này."
    }
}

function Get-ScoopPrefix {
    param(
        [Parameter(Mandatory = $true)][string]$AppName
    )

    try {
        $prefix = & scoop prefix $AppName 2>$null
        if ($LASTEXITCODE -eq 0 -and $prefix) {
            return $prefix.Trim()
        }
    } catch {
    }

    return $null
}

function Get-DownloadsDir {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath
    )

    $downloadsDir = Join-Path $RootPath "downloads"
    New-Item -ItemType Directory -Path $downloadsDir -Force | Out-Null
    return $downloadsDir
}

function Install-VisualStudioBuildTools {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$DownloadsDir
    )

    $vsDevCmd = Find-VsDevCmd -RootPath $InstallRoot
    if ($vsDevCmd) {
        Write-Host "✔ Đã có Visual Studio Build Tools tại $InstallRoot"
        return $vsDevCmd
    }

    $bootstrapperUrl = "https://aka.ms/vs/17/release/vs_BuildTools.exe"
    $bootstrapperPath = Join-Path $DownloadsDir "vs_BuildTools.exe"

    Write-Step "Tải Visual Studio Build Tools bootstrapper"
    Invoke-WebRequest -Uri $bootstrapperUrl -OutFile $bootstrapperPath

    if (-not (Test-Path $bootstrapperPath)) {
        throw "Không tải được vs_BuildTools.exe từ Microsoft."
    }

    Write-Step "Cài Visual Studio Build Tools vào $InstallRoot"
    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null

    $installArgs = @(
        "--quiet",
        "--wait",
        "--norestart",
        "--nocache",
        "--installPath", $InstallRoot,
        "--add", "Microsoft.VisualStudio.Workload.VCTools",
        "--includeRecommended"
    )

    & $bootstrapperPath @installArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Cài Visual Studio Build Tools thất bại."
    }

    $vsDevCmd = Find-VsDevCmd -RootPath $InstallRoot
    if (-not $vsDevCmd) {
        throw "Cài xong nhưng không tìm thấy VsDevCmd.bat trong $InstallRoot."
    }

    return $vsDevCmd
}

function Find-PythonExe {
    $candidates = @(
        (Get-Command py -ErrorAction SilentlyContinue)?.Source,
        (Get-Command python -ErrorAction SilentlyContinue)?.Source,
        "$env:LocalAppData\Programs\Python\Python311\python.exe",
        "$env:ProgramFiles\Python311\python.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($candidate in $candidates) {
        if ($candidate -like "*\py.exe") {
            return $candidate
        }
        return $candidate
    }

    $scoopPrefix = Get-ScoopPrefix -AppName "python"
    if ($scoopPrefix) {
        $candidate = Join-Path $scoopPrefix "python.exe"
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "Không tìm thấy Python sau khi cài đặt."
}

function Find-NvccPath {
    $command = Get-Command nvcc.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $scoopPrefix = Get-ScoopPrefix -AppName "cuda"
    if ($scoopPrefix) {
        $candidate = Join-Path $scoopPrefix "bin\nvcc.exe"
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    if ($env:CUDA_PATH) {
        $candidate = Join-Path $env:CUDA_PATH "bin\nvcc.exe"
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $cudaRoots = @(
        "D:\Applications\scoop\apps\cuda\current",
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"
    )
    foreach ($rootPath in $cudaRoots) {
        if (-not (Test-Path $rootPath)) {
            continue
        }
        $candidate = Join-Path $rootPath "bin\nvcc.exe"
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Find-VsDevCmd {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath
    )

    $directCandidate = Join-Path $RootPath "Common7\Tools\VsDevCmd.bat"
    if (Test-Path $directCandidate) {
        return $directCandidate
    }

    if (Test-Path $RootPath) {
        $recursiveCandidate = Get-ChildItem $RootPath -Recurse -Filter "VsDevCmd.bat" -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if ($recursiveCandidate) {
            return $recursiveCandidate
        }
    }

    return $null
}

function Invoke-CmdInVsDevShell {
    param(
        [Parameter(Mandatory = $true)][string]$VsDevCmd,
        [Parameter(Mandatory = $true)][string]$Command
    )

    $fullCommand = "`"$VsDevCmd`" -arch=x64 && $Command"
    & cmd.exe /c $fullCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Lệnh thất bại: $Command"
    }
}

function Set-DotEnvValue {
    param(
        [Parameter(Mandatory = $true)][string]$EnvFile,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    if (-not (Test-Path $EnvFile)) {
        New-Item -ItemType File -Path $EnvFile -Force | Out-Null
    }

    $lines = Get-Content $EnvFile -ErrorAction SilentlyContinue
    if ($null -eq $lines) {
        $lines = @()
    }

    $updated = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\Q$Key\E=") {
            $lines[$i] = "$Key=$Value"
            $updated = $true
            break
        }
    }
    if (-not $updated) {
        $lines += "$Key=$Value"
    }

    Set-Content -Path $EnvFile -Value $lines -Encoding UTF8
}

Test-ScoopInstalled

$BackendRoot = (Resolve-Path $BackendRoot).Path
if (-not $WorkspaceRoot) {
    $WorkspaceRoot = Join-Path $BackendRoot ".local-llm"
}
$WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)
$StateFile = Join-Path $WorkspaceRoot "turboquant-setup-state.json"
$ModelPath = [System.IO.Path]::GetFullPath($ModelPath)

if (-not (Test-Path $ModelPath)) {
    throw "Không tìm thấy model GGUF tại: $ModelPath"
}

$RepoDir = Join-Path $WorkspaceRoot "llama-cpp-turboquant-cuda"
$BuildDir = Join-Path $RepoDir "build-win-cuda"
$DownloadsDir = Get-DownloadsDir -RootPath $WorkspaceRoot
$VenvDir = Join-Path $BackendRoot ".venv"
$EnvFile = Join-Path $BackendRoot ".env"
$EnvExampleFile = Join-Path $BackendRoot ".env.example"
$EnvBackupFile = Join-Path $BackendRoot ".env.turboquant.backup"
$createdEnvFile = $false

Write-Step "Cài toolchain cơ bản"
Install-ScoopPackage -PackageSpec "main/git" -CheckCommand "git"
Install-ScoopPackage -PackageSpec "main/cmake" -CheckCommand "cmake"
Install-ScoopPackage -PackageSpec "main/ninja" -CheckCommand "ninja"
Install-ScoopPackage -PackageSpec "main/python" -CheckCommand "python" -PostInstallCheck "python"

if (-not $SkipCudaInstall) {
    $nvccPath = Find-NvccPath
    if (-not $nvccPath) {
        Write-Step "Cài NVIDIA CUDA Toolkit"
        Install-ScoopPackage -PackageSpec "main/cuda" -CheckCommand "nvcc" -PostInstallCheck "nvcc"
        $nvccPath = Find-NvccPath
    }
    if (-not $nvccPath) {
        throw "Không tìm thấy nvcc.exe sau khi cài CUDA Toolkit từ scoop."
    }
}
else {
    $nvccPath = Find-NvccPath
}

$vsDevCmd = Install-VisualStudioBuildTools -InstallRoot $VsBuildToolsRoot -DownloadsDir $DownloadsDir

if (-not $nvccPath) {
    throw "Không tìm thấy nvcc.exe. Hãy bỏ -SkipCudaInstall hoặc cài CUDA Toolkit thủ công."
}

Write-Step "Chuẩn bị workspace TurboQuant"
New-Item -ItemType Directory -Path $WorkspaceRoot -Force | Out-Null
if (-not (Test-Path $RepoDir)) {
    & git clone $TurboQuantRepo $RepoDir
    if ($LASTEXITCODE -ne 0) {
        throw "Clone TurboQuant thất bại."
    }
}

Push-Location $RepoDir
try {
    & git fetch --all --prune
    if ($LASTEXITCODE -ne 0) {
        throw "Git fetch thất bại."
    }
    & git checkout $TurboQuantBranch
    if ($LASTEXITCODE -ne 0) {
        throw "Git checkout branch $TurboQuantBranch thất bại."
    }
    & git pull --ff-only origin $TurboQuantBranch
    if ($LASTEXITCODE -ne 0) {
        throw "Git pull branch $TurboQuantBranch thất bại."
    }
}
finally {
    Pop-Location
}

if ($ForceReconfigure -and (Test-Path $BuildDir)) {
    Write-Step "Xóa build cũ"
    Remove-Item -Recurse -Force $BuildDir
}

Write-Step "Build llama-server với CUDA"
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
$configureCmd = @(
    "set `"CUDACXX=$nvccPath`"",
    "cmake -S `"$RepoDir`" -B `"$BuildDir`" -G Ninja",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DGGML_CUDA=ON",
    "-DCMAKE_CUDA_ARCHITECTURES=$CudaArch",
    "-DLLAMA_BUILD_TESTS=OFF",
    "-DLLAMA_BUILD_EXAMPLES=OFF",
    "-DLLAMA_BUILD_SERVER=ON",
    "-DLLAMA_BUILD_COMMON=ON",
    "-DLLAMA_OPENSSL=OFF",
    "-DGGML_LLAMAFILE=OFF",
    "-DGGML_CCACHE=OFF"
) -join " "
Invoke-CmdInVsDevShell -VsDevCmd $vsDevCmd -Command $configureCmd

$buildCmd = "cmake --build `"$BuildDir`" --config Release --target llama-server --parallel"
Invoke-CmdInVsDevShell -VsDevCmd $vsDevCmd -Command $buildCmd

$ServerExe = Join-Path $BuildDir "bin\Release\llama-server.exe"
if (-not (Test-Path $ServerExe)) {
    $ServerExe = Join-Path $BuildDir "bin\llama-server.exe"
}
if (-not (Test-Path $ServerExe)) {
    throw "Build xong nhưng không tìm thấy llama-server.exe"
}

Write-Step "Tạo virtual environment cho backend"
$pythonExe = Find-PythonExe
if ($pythonExe -like "*\py.exe") {
    & $pythonExe -3.11 -m venv $VenvDir
}
elseif (-not (Test-Path (Join-Path $VenvDir "Scripts\python.exe"))) {
    & $pythonExe -m venv $VenvDir
}
if ($LASTEXITCODE -ne 0) {
    throw "Tạo virtual environment thất bại."
}

$venvPython = Join-Path $VenvDir "Scripts\python.exe"
& $venvPython -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) {
    throw "Nâng cấp pip thất bại."
}
& $venvPython -m pip install -r (Join-Path $BackendRoot "requirements.txt")
if ($LASTEXITCODE -ne 0) {
    throw "Cài Python dependencies thất bại."
}

Write-Step "Cập nhật file .env"
if (Test-Path $EnvFile) {
    Copy-Item $EnvFile $EnvBackupFile -Force
}
elseif (Test-Path $EnvExampleFile) {
    Copy-Item $EnvExampleFile $EnvFile
    $createdEnvFile = $true
}

Set-DotEnvValue -EnvFile $EnvFile -Key "LOCAL_LLM_BACKEND" -Value "turboquant"
Set-DotEnvValue -EnvFile $EnvFile -Key "LOCAL_LLM_AUTOSTART" -Value "1"
Set-DotEnvValue -EnvFile $EnvFile -Key "LOCAL_LLM_HOST" -Value "127.0.0.1"
Set-DotEnvValue -EnvFile $EnvFile -Key "LOCAL_LLM_PORT" -Value "$LocalLlmPort"
Set-DotEnvValue -EnvFile $EnvFile -Key "LOCAL_LLM_TIMEOUT_S" -Value "120"
Set-DotEnvValue -EnvFile $EnvFile -Key "LOCAL_LLM_MODEL_NAME" -Value ([System.IO.Path]::GetFileName($ModelPath))
Set-DotEnvValue -EnvFile $EnvFile -Key "LOCAL_LLM_GGUF_PATH" -Value $ModelPath
Set-DotEnvValue -EnvFile $EnvFile -Key "TURBOQUANT_SERVER_BIN" -Value $ServerExe
Set-DotEnvValue -EnvFile $EnvFile -Key "TURBOQUANT_CACHE_TYPE" -Value $TurboQuantCacheType
Set-DotEnvValue -EnvFile $EnvFile -Key "TURBOQUANT_NGL" -Value "$TurboQuantNgl"
Set-DotEnvValue -EnvFile $EnvFile -Key "TURBOQUANT_CTX" -Value "$TurboQuantCtx"

$setupState = [ordered]@{
    backendRoot = $BackendRoot
    workspaceRoot = $WorkspaceRoot
    repoDir = $RepoDir
    buildDir = $BuildDir
    downloadsDir = $DownloadsDir
    venvDir = $VenvDir
    envFile = $EnvFile
    envBackupFile = $EnvBackupFile
    createdEnvFile = $createdEnvFile
    vsBuildToolsRoot = $VsBuildToolsRoot
    turboQuantRepo = $TurboQuantRepo
    turboQuantBranch = $TurboQuantBranch
    modelPath = $ModelPath
}
$setupState | ConvertTo-Json -Depth 4 | Set-Content -Path $StateFile -Encoding UTF8

Write-Step "Hoàn tất"
Write-Host "Backend root : $BackendRoot"
Write-Host "Workspace    : $WorkspaceRoot"
Write-Host "VS BuildTools : $VsBuildToolsRoot"
Write-Host "Model GGUF   : $ModelPath"
Write-Host "llama-server : $ServerExe"
Write-Host "Python venv  : $venvPython"
Write-Host "Env file     : $EnvFile"
Write-Host "Env backup   : $EnvBackupFile"
Write-Host "State file   : $StateFile"
Write-Host ""
Write-Host "Tiếp theo:"
Write-Host "1. Mở terminal mới."
Write-Host "2. cd `"$BackendRoot`""
Write-Host "3. .\\.venv\\Scripts\\activate"
Write-Host "4. uvicorn main:app --host 0.0.0.0 --port 8000 --reload"
