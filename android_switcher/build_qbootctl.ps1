$ErrorActionPreference = "Stop"

$SdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
$NdkDir = Get-ChildItem "$SdkRoot\ndk" -Directory | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $NdkDir) {
    throw "No Android NDK found under $SdkRoot\ndk"
}

$ToolchainBin = Join-Path $NdkDir "toolchains\llvm\prebuilt\windows-x86_64\bin"
$Clang = Join-Path $ToolchainBin "aarch64-linux-android31-clang.cmd"
$Strip = Join-Path $ToolchainBin "llvm-strip.exe"

$CppDir = Join-Path $PSScriptRoot "app\src\main\cpp"
$OutDir = Join-Path $PSScriptRoot "app\src\main\jniLibs\arm64-v8a"
$OutBin = Join-Path $OutDir "libqbootctl.so"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

& $Clang -O2 -Wall -Wextra -Wno-unused-parameter -fPIE -pie -std=gnu11 "-I$CppDir" `
    (Join-Path $CppDir "qbootctl.c") `
    (Join-Path $CppDir "bootctrl_impl.c") `
    (Join-Path $CppDir "gpt-utils.c") `
    (Join-Path $CppDir "ufs-bsg.c") `
    (Join-Path $CppDir "crc32.c") `
    -o $OutBin

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& $Strip $OutBin
Write-Host "Built $OutBin using $NdkDir"
