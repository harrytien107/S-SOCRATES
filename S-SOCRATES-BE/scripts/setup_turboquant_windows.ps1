param(
    [string]$BackendRoot = "",
    [string]$SoftwareRoot = "G:\Software",
    [string]$WorkspaceRoot = "",
    [string]$VenvRoot = "",
    [string]$TurboQuantRepo = "https://github.com/spiritbuun/llama-cpp-turboquant-cuda.git",
    [string]$TurboQuantBranch = "feature/turboquant-kv-cache",
    [Parameter(Mandatory = $true)]
    [string]$ModelPath,
    [string]$CudaArch = "86",
    [int]$LocalPort = 8011,
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
        throw "winget is required. Install App Installer from Microsoft Store first."
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
        Write-Host "Already installed: $Id"
        return
    }

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

    $output = (& winget @args 2>&1 | Out-String)
    $exitCode = $LASTEXITCODE
    if ($output) {
        Write-Host $output.Trim()
    }

    $nonFatalMessages = @(
        "Found an existing package already installed",
        "No available upgrade found",
        "No newer package versions are available"
    )
    $hasNonFatalMessage = $false
    foreach ($message in $nonFatalMessages) {
        if ($output -like "*$message*") {
            $hasNonFatalMessage = $true
            break
        }
    }

    if ($exitCode -ne 0 -and -not $hasNonFatalMessage) {
        throw "Failed to install $Id via winget."
    }
}

function Find-PythonExe {
    param(
        [Parameter(Mandatory = $true)][string]$PreferredPythonDir
    )

    $pyCommand = Get-Command py -ErrorAction SilentlyContinue
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    $candidates = @(
        $(if ($pyCommand) { $pyCommand.Source }),
        $(if ($pythonCommand) { $pythonCommand.Source }),
        (Join-Path $PreferredPythonDir "python.exe"),
        "$env:LocalAppData\Programs\Python\Python311\python.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($candidate in $candidates) {
        return $candidate
    }

    throw "Python 3.11 was not found."
}

function Find-NvccPath {
    param(
        [Parameter(Mandatory = $true)][string]$SoftwareRoot
    )

    $command = Get-Command nvcc.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $searchRoots = @(
        (Join-Path $SoftwareRoot "NVIDIA GPU Computing Toolkit\CUDA"),
        "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"
    ) | Where-Object { Test-Path $_ }

    $cudaRoots = foreach ($searchRoot in $searchRoots) {
        Get-ChildItem $searchRoot -Directory -ErrorAction SilentlyContinue
    }
    $cudaRoots = $cudaRoots | Sort-Object Name -Descending
    foreach ($root in $cudaRoots) {
        $nvcc = Join-Path $root.FullName "bin\nvcc.exe"
        if (Test-Path $nvcc) {
            return $nvcc
        }
    }

    return $null
}

function Find-VsDevCmd {
    param(
        [Parameter(Mandatory = $true)][string]$VsBuildToolsRoot
    )

    $candidates = @(
        (Join-Path $VsBuildToolsRoot "Common7\Tools\VsDevCmd.bat"),
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

    $fullCommand = "call `"$VsDevCmd`" -arch=x64 && $Command"
    & cmd.exe /c $fullCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $Command"
    }
}

function Resolve-TurboQuantBranch {
    param(
        [Parameter(Mandatory = $true)][string]$RepoDir,
        [Parameter(Mandatory = $true)][string]$PreferredBranch
    )

    $branches = @(
        (& git -C $RepoDir branch -r 2>$null | ForEach-Object { $_.Trim() })
    )

    if ($branches -contains "origin/$PreferredBranch") {
        return $PreferredBranch
    }

    if ($branches -contains "origin/master") {
        Write-Host "Preferred branch '$PreferredBranch' not found. Falling back to 'master'."
        return "master"
    }

    if ($branches -contains "origin/main") {
        Write-Host "Preferred branch '$PreferredBranch' not found. Falling back to 'main'."
        return "main"
    }

    throw "Could not find a usable TurboQuant branch on origin."
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
        if ($lines[$i].StartsWith("$Key=")) {
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

if (-not $BackendRoot) {
    if ($PSScriptRoot) {
        $BackendRoot = Split-Path -Parent $PSScriptRoot
    } else {
        $BackendRoot = (Get-Location).Path
    }
}

$BackendRoot = (Resolve-Path $BackendRoot).Path
$SoftwareRoot = [System.IO.Path]::GetFullPath($SoftwareRoot)
if (-not $WorkspaceRoot) {
    $WorkspaceRoot = Join-Path $SoftwareRoot "S-SOCRATES\turboquant-workspace"
}
if (-not $VenvRoot) {
    $VenvRoot = Join-Path $SoftwareRoot "S-SOCRATES\venvs\backend"
}
$WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)
$VenvRoot = [System.IO.Path]::GetFullPath($VenvRoot)
$ModelPath = [System.IO.Path]::GetFullPath($ModelPath)
$VsBuildToolsRoot = Join-Path $SoftwareRoot "BuildTools"
$PreferredPythonDir = Join-Path $SoftwareRoot "Python311"

if (-not (Test-Path $ModelPath)) {
    throw "GGUF model was not found at: $ModelPath"
}

$RepoDir = Join-Path $WorkspaceRoot "llama-cpp-turboquant-cuda"
$BuildDir = Join-Path $RepoDir "build-win-cuda"
$VenvDir = $VenvRoot
$EnvFile = Join-Path $BackendRoot ".env"
$EnvExampleFile = Join-Path $BackendRoot ".env.example"

Write-Step "Installing required toolchain"
Install-WingetPackage -Id "Git.Git" -CheckCommand "git"
Install-WingetPackage -Id "Kitware.CMake" -CheckCommand "cmake"
Install-WingetPackage -Id "Ninja-build.Ninja" -CheckCommand "ninja"
Install-WingetPackage -Id "Python.Python.3.11" -CheckCommand "py" -Override "InstallAllUsers=1 TargetDir=`"$PreferredPythonDir`" PrependPath=1 Include_launcher=1"
Install-WingetPackage -Id "Microsoft.VisualStudio.2022.BuildTools" -Override "--quiet --wait --norestart --nocache --installPath `"$VsBuildToolsRoot`" --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"

if (-not $SkipCudaInstall) {
    $nvccPath = Find-NvccPath -SoftwareRoot $SoftwareRoot
    if (-not $nvccPath) {
        Install-WingetPackage -Id "Nvidia.CUDA"
        $nvccPath = Find-NvccPath -SoftwareRoot $SoftwareRoot
    }
    if (-not $nvccPath) {
        throw "nvcc.exe was not found after CUDA installation."
    }
} else {
    $nvccPath = Find-NvccPath -SoftwareRoot $SoftwareRoot
}

if (-not $nvccPath) {
    throw "nvcc.exe was not found. Install CUDA Toolkit or omit -SkipCudaInstall."
}

$vsDevCmd = Find-VsDevCmd -VsBuildToolsRoot $VsBuildToolsRoot
if (-not $vsDevCmd) {
    throw "VsDevCmd.bat was not found. Install Visual Studio Build Tools with the C++ workload."
}

Write-Step "Preparing TurboQuant workspace"
New-Item -ItemType Directory -Path $WorkspaceRoot -Force | Out-Null
New-Item -ItemType Directory -Path $VenvDir -Force | Out-Null
if (-not (Test-Path $RepoDir)) {
    & git clone $TurboQuantRepo $RepoDir
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to clone TurboQuant repository."
    }
}

Push-Location $RepoDir
try {
    & git fetch --all --prune
    $resolvedBranch = Resolve-TurboQuantBranch -RepoDir $RepoDir -PreferredBranch $TurboQuantBranch
    & git checkout $resolvedBranch
    & git pull --ff-only origin $resolvedBranch
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to update TurboQuant repository."
    }
}
finally {
    Pop-Location
}

if ($ForceReconfigure -and (Test-Path $BuildDir)) {
    Write-Step "Removing previous build directory"
    Remove-Item -Recurse -Force $BuildDir
}

Write-Step "Building TurboQuant llama-server with CUDA"
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

$cmakeCache = Join-Path $BuildDir "CMakeCache.txt"
if (-not (Test-Path $cmakeCache)) {
    Write-Host "Initial CMake configure did not produce CMakeCache.txt. Cleaning build directory and retrying..."
    if (Test-Path $BuildDir) {
        Remove-Item -Recurse -Force $BuildDir
    }
    New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
    Run-CmdInVsDevShell -VsDevCmd $vsDevCmd -Command $configureCmd
}

if (-not (Test-Path $cmakeCache)) {
    throw "CMake configure did not produce CMakeCache.txt in $BuildDir"
}

$buildCmd = "cmake --build `"$BuildDir`" --config Release --target llama-server --parallel"
Run-CmdInVsDevShell -VsDevCmd $vsDevCmd -Command $buildCmd

$serverExe = Join-Path $BuildDir "bin\Release\llama-server.exe"
if (-not (Test-Path $serverExe)) {
    $serverExe = Join-Path $BuildDir "bin\llama-server.exe"
}
if (-not (Test-Path $serverExe)) {
    throw "Build finished but llama-server.exe was not found."
}

Write-Step "Preparing backend virtual environment"
$pythonExe = Find-PythonExe -PreferredPythonDir $PreferredPythonDir
if ($pythonExe -like "*\py.exe") {
    & $pythonExe -3.11 -m venv $VenvDir
} elseif (-not (Test-Path (Join-Path $VenvDir "Scripts\python.exe"))) {
    & $pythonExe -m venv $VenvDir
}
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create backend virtual environment."
}

$venvPython = Join-Path $VenvDir "Scripts\python.exe"
& $venvPython -m pip install --upgrade pip
& $venvPython -m pip install -r (Join-Path $BackendRoot "requirements.txt")
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install backend dependencies."
}

Write-Step "Updating .env for TurboQuant-only local runtime"
if (-not (Test-Path $EnvFile) -and (Test-Path $EnvExampleFile)) {
    Copy-Item $EnvExampleFile $EnvFile
}

Set-DotEnvValue -EnvFile $EnvFile -Key "LOCAL_LLM_BACKEND" -Value "turboquant"
Set-DotEnvValue -EnvFile $EnvFile -Key "LOCAL_LLM_AUTOSTART" -Value "1"
Set-DotEnvValue -EnvFile $EnvFile -Key "LOCAL_LLM_HOST" -Value "127.0.0.1"
Set-DotEnvValue -EnvFile $EnvFile -Key "LOCAL_LLM_PORT" -Value "$LocalPort"
Set-DotEnvValue -EnvFile $EnvFile -Key "LOCAL_LLM_TIMEOUT_S" -Value "120"
Set-DotEnvValue -EnvFile $EnvFile -Key "LOCAL_LLM_MODEL_NAME" -Value ([System.IO.Path]::GetFileName($ModelPath))
Set-DotEnvValue -EnvFile $EnvFile -Key "LOCAL_LLM_GGUF_PATH" -Value $ModelPath
Set-DotEnvValue -EnvFile $EnvFile -Key "TURBOQUANT_SERVER_BIN" -Value $serverExe
Set-DotEnvValue -EnvFile $EnvFile -Key "TURBOQUANT_CACHE_TYPE" -Value $TurboQuantCacheType
Set-DotEnvValue -EnvFile $EnvFile -Key "TURBOQUANT_NGL" -Value "$TurboQuantNgl"
Set-DotEnvValue -EnvFile $EnvFile -Key "TURBOQUANT_CTX" -Value "$TurboQuantCtx"

Write-Step "TurboQuant setup complete"
Write-Host "Software root   : $SoftwareRoot"
Write-Host "TurboQuant repo : $RepoDir"
Write-Host "Model GGUF      : $ModelPath"
Write-Host "llama-server    : $serverExe"
Write-Host "Backend venv    : $venvPython"
Write-Host "Env file        : $EnvFile"
Write-Host ""
Write-Host "Note:"
Write-Host "- Script da uu tien cai workspace, Build Tools, va Python vao G:\Software."
Write-Host "- Mot so goi winget nhu Git/CMake/Ninja/CUDA co the van do installer tu quyet dinh vi tri cai dat."
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Open a new terminal"
Write-Host "2. cd `"$BackendRoot`""
Write-Host "3. `"$venvPython`" -m pip --version"
Write-Host "4. `"$venvPython`" -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload"
