param(
    [string]$BackendRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$WorkspaceRoot = "",
    [string]$TurboQuantRepo = "https://github.com/spiritbuun/llama-cpp-turboquant-cuda.git",
    [string]$TurboQuantBranch = "feature/turboquant-kv-cache",
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

function Require-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "Không tìm thấy winget. Hãy cài App Installer từ Microsoft Store trước."
    }
}

function Test-CommandAvailable([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [string]$CheckCommand = "",
        [string]$Override = ""
    )

    if ($CheckCommand -and (Test-CommandAvailable $CheckCommand)) {
        Write-Host "✔ Đã có $Id"
        return
    }

    Write-Host "Cài $Id qua winget..."
    $args = @(
        "install",
        "--id", $Id,
        "-e",
        "--source", "winget",
        "--accept-source-agreements",
        "--accept-package-agreements"
    )
    if ($Override) {
        $args += @("--override", $Override)
    }
    & winget @args
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

    throw "Không tìm thấy Python sau khi cài đặt."
}

function Find-NvccPath {
    $command = Get-Command nvcc.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $cudaRoots = Get-ChildItem "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA" -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    foreach ($root in $cudaRoots) {
        $nvcc = Join-Path $root.FullName "bin\nvcc.exe"
        if (Test-Path $nvcc) {
            return $nvcc
        }
    }

    return $null
}

function Find-VsDevCmd {
    $candidates = @(
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Run-CmdInVsDevShell {
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

Require-Winget

$BackendRoot = (Resolve-Path $BackendRoot).Path
if (-not $WorkspaceRoot) {
    $WorkspaceRoot = Join-Path $BackendRoot ".local-llm"
}
$WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)
$ModelPath = [System.IO.Path]::GetFullPath($ModelPath)

if (-not (Test-Path $ModelPath)) {
    throw "Không tìm thấy model GGUF tại: $ModelPath"
}

$RepoDir = Join-Path $WorkspaceRoot "llama-cpp-turboquant-cuda"
$BuildDir = Join-Path $RepoDir "build-win-cuda"
$VenvDir = Join-Path $BackendRoot ".venv"
$EnvFile = Join-Path $BackendRoot ".env"
$EnvExampleFile = Join-Path $BackendRoot ".env.example"

Write-Step "Cài toolchain cơ bản"
Install-WingetPackage -Id "Git.Git" -CheckCommand "git"
Install-WingetPackage -Id "Kitware.CMake" -CheckCommand "cmake"
Install-WingetPackage -Id "Ninja-build.Ninja" -CheckCommand "ninja"
Install-WingetPackage -Id "Python.Python.3.11" -CheckCommand "py"
Install-WingetPackage -Id "Microsoft.VisualStudio.2022.BuildTools" -Override "--quiet --wait --norestart --nocache --installPath `"C:\BuildTools`" --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"

if (-not $SkipCudaInstall) {
    $nvccPath = Find-NvccPath
    if (-not $nvccPath) {
        Write-Step "Cài NVIDIA CUDA Toolkit"
        Install-WingetPackage -Id "Nvidia.CUDA"
        $nvccPath = Find-NvccPath
    }
    if (-not $nvccPath) {
        throw "Không tìm thấy nvcc.exe sau khi cài CUDA Toolkit."
    }
}
else {
    $nvccPath = Find-NvccPath
}

$vsDevCmd = Find-VsDevCmd
if (-not $vsDevCmd) {
    throw "Không tìm thấy VsDevCmd.bat. Visual Studio Build Tools có thể chưa cài đúng workload C++."
}

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
Run-CmdInVsDevShell -VsDevCmd $vsDevCmd -Command $configureCmd

$buildCmd = "cmake --build `"$BuildDir`" --config Release --target llama-server --parallel"
Run-CmdInVsDevShell -VsDevCmd $vsDevCmd -Command $buildCmd

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
if (-not (Test-Path $EnvFile) -and (Test-Path $EnvExampleFile)) {
    Copy-Item $EnvExampleFile $EnvFile
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

Write-Step "Hoàn tất"
Write-Host "Backend root : $BackendRoot"
Write-Host "Workspace    : $WorkspaceRoot"
Write-Host "Model GGUF   : $ModelPath"
Write-Host "llama-server : $ServerExe"
Write-Host "Python venv  : $venvPython"
Write-Host "Env file     : $EnvFile"
Write-Host ""
Write-Host "Tiếp theo:"
Write-Host "1. Mở terminal mới."
Write-Host "2. cd `"$BackendRoot`""
Write-Host "3. .\\.venv\\Scripts\\activate"
Write-Host "4. uvicorn main:app --host 0.0.0.0 --port 8000 --reload"
