param(
    [string]$BackendRoot = "",
    [string]$SoftwareRoot = "",
    [string]$WorkspaceRoot = "",
    [string]$VenvRoot = "",
    [string]$TurboQuantRepo = "https://github.com/spiritbuun/llama-cpp-turboquant-cuda.git",
    [string]$TurboQuantBranch = "feature/turboquant-kv-cache",
    [string]$ModelPath = "",
    [string]$CudaArch = "86",
    [string]$CudaVersion = "12.5",
    [int]$LocalPort = 8011,
    [int]$TurboQuantCtx = 8192,
    [string]$TurboQuantCacheType = "turbo2",
    [int]$TurboQuantNgl = 99,
    [switch]$SkipCudaInstall,
    [switch]$ForceReconfigure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Read key/value pairs from .env and expose them to the current PowerShell process.
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

# Get a string setting from parsed .env, process env, or a fallback value.
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

# Get an integer setting from parsed .env, process env, or a fallback value.
function Get-SettingIntOrDefault {
    param([hashtable]$EnvMap, [string]$Name, [int]$DefaultValue)
    $raw = Get-SettingOrDefault -EnvMap $EnvMap -Name $Name
    $parsed = 0
    if ([int]::TryParse($raw, [ref]$parsed)) {
        return $parsed
    }
    return $DefaultValue
}

# Print a visible setup step header.
function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

# Ensure winget is available before trying to install dependencies.
function Require-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget is required. Install App Installer from Microsoft Store first."
    }
}

# Check whether a command can be resolved from the current PATH.
function Test-CommandAvailable([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# Install a winget package when the matching command is not already available.
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

# Try common winget package ids for a specific CUDA Toolkit version.
function Install-CudaToolkit {
    param(
        [Parameter(Mandatory = $true)][string]$Version
    )

    $cudaPackageIds = @(
        "Nvidia.CUDA.Toolkit.$Version",
        "Nvidia.CUDA.$Version",
        "Nvidia.CUDA"
    )

    foreach ($packageId in $cudaPackageIds) {
        Write-Host "Trying CUDA package: $packageId"
        try {
            Install-WingetPackage -Id $packageId
            return
        } catch {
            Write-Host "CUDA package '$packageId' was not installed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    throw "Failed to install CUDA Toolkit $Version via winget. Install CUDA Toolkit $Version manually, then rerun with -SkipCudaInstall."
}

# Locate a Python executable that can create the backend virtual environment.
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

# Locate nvcc.exe from PATH or common CUDA installation directories.
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

# Find a VS2022/MSVC host compiler that is supported by CUDA 12.x.
function Find-MsvcClPath {
    param(
        [Parameter(Mandatory = $true)][string]$VsBuildToolsRoot
    )

    $msvcRoots = @(
        (Join-Path $VsBuildToolsRoot "VC\Tools\MSVC"),
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC"
    ) | Where-Object { Test-Path $_ }

    $toolsets = foreach ($root in $msvcRoots) {
        Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue
    }
    $toolsets = $toolsets | Sort-Object Name -Descending
    foreach ($toolset in $toolsets) {
        $cl = Join-Path $toolset.FullName "bin\Hostx64\x64\cl.exe"
        if (Test-Path $cl) {
            return $cl
        }
    }

    return $null
}

# Find the VS2022 developer environment script used to build CUDA code.
function Find-VsDevCmd {
    param(
        [Parameter(Mandatory = $true)][string]$VsBuildToolsRoot
    )

    $candidates = @(
        (Join-Path $VsBuildToolsRoot "Common7\Tools\VsDevCmd.bat"),
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

# Check whether cl.exe is already available in the active shell.
function Test-MsvcReady {
    return [bool](Get-Command cl.exe -ErrorAction SilentlyContinue)
}

# Run a command inside the VS developer shell so CMake can see MSVC/CUDA tools.
function Run-CmdInVsDevShell {
    param(
        [string]$VsDevCmd = "",
        [Parameter(Mandatory = $true)][string]$Command
    )

    if (-not $VsDevCmd) {
        throw "VS2022 VsDevCmd.bat was not found. CUDA 12.5 requires MSVC 2017-2022, so do not build with Visual Studio 2026."
    }

    $fullCommand = "call `"$VsDevCmd`" -arch=x64 && $Command"
    & cmd.exe /c $fullCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $Command"
    }
}

# Checkout the preferred TurboQuant branch, falling back to master if needed.
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

# Add or replace a single key in .env.
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

    $newLine = "$Key=$Value"
    $outputLines = @()
    $updated = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=") {
            if (-not $updated) {
                $outputLines += $newLine
                $updated = $true
            }
            continue
        }
        $outputLines += $line
    }

    if (-not $updated) {
        $outputLines += $newLine
    }

    Set-Content -Path $EnvFile -Value $outputLines -Encoding UTF8
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
$EnvFile = Join-Path $BackendRoot ".env"
$envMap = Import-DotEnvValues -EnvFilePath $EnvFile

if (-not $SoftwareRoot) {
    $SoftwareRoot = Get-SettingOrDefault -EnvMap $envMap -Name "SETUP_SOFTWARE_ROOT" -DefaultValue "G:\Software"
}
$SoftwareRoot = [System.IO.Path]::GetFullPath($SoftwareRoot)
if (-not $WorkspaceRoot) {
    $WorkspaceRoot = Get-SettingOrDefault -EnvMap $envMap -Name "TURBOQUANT_WORKSPACE_ROOT" -DefaultValue (Join-Path $SoftwareRoot "BuildTool\")
}
if (-not $VenvRoot) {
    $VenvRoot = Get-SettingOrDefault -EnvMap $envMap -Name "BACKEND_VENV_ROOT" -DefaultValue (Join-Path $SoftwareRoot "BuildTool\venvs")
}
if (-not $ModelPath) {
    $ModelPath = Get-SettingOrDefault -EnvMap $envMap -Name "LOCAL_GGUF_PATH"
}
if (-not $ModelPath) {
    throw "Model path is required. Set LOCAL_GGUF_PATH in .env or pass -ModelPath."
}
if (-not $PSBoundParameters.ContainsKey("LocalPort")) {
    $LocalPort = Get-SettingIntOrDefault -EnvMap $envMap -Name "LOCAL_LLM_PORT" -DefaultValue $LocalPort
}
if (-not $PSBoundParameters.ContainsKey("TurboQuantCtx")) {
    $TurboQuantCtx = Get-SettingIntOrDefault -EnvMap $envMap -Name "LOCAL_CTX" -DefaultValue $TurboQuantCtx
}
if (-not $PSBoundParameters.ContainsKey("TurboQuantNgl")) {
    $TurboQuantNgl = Get-SettingIntOrDefault -EnvMap $envMap -Name "LOCAL_NGL" -DefaultValue $TurboQuantNgl
}
if (-not $PSBoundParameters.ContainsKey("TurboQuantCacheType")) {
    $TurboQuantCacheType = Get-SettingOrDefault -EnvMap $envMap -Name "LOCAL_CACHE_TYPE" -DefaultValue $TurboQuantCacheType
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
        Install-CudaToolkit -Version $CudaVersion
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

$msvcClPath = Find-MsvcClPath -VsBuildToolsRoot $VsBuildToolsRoot
if (-not $msvcClPath) {
    throw "MSVC cl.exe (VS2022) was not found. Install Visual Studio Build Tools 2022 with Desktop development with C++."
}

$vsDevCmd = Find-VsDevCmd -VsBuildToolsRoot $VsBuildToolsRoot
if (-not $vsDevCmd) {
    throw "VS2022 VsDevCmd.bat was not found. Install Visual Studio Build Tools 2022 with the Desktop development with C++ workload."
}
Write-Host "Using VS2022 developer environment: $vsDevCmd"
Write-Host "Using VS2022 host compiler: $msvcClPath"

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
    "cmake -S `"$RepoDir`" -B `"$BuildDir`" -G Ninja",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DGGML_CUDA=ON",
    "-DCMAKE_CUDA_COMPILER=`"$nvccPath`"",
    "-DCMAKE_CUDA_HOST_COMPILER=`"$msvcClPath`"",
    "-DCMAKE_CUDA_ARCHITECTURES=$CudaArch"
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
