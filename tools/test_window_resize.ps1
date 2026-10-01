param(
    [string]$FlutterRoot = $env:FLUTTER_ROOT
)

$ErrorActionPreference = 'Stop'
$resizeRepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($FlutterRoot)) {
    $FlutterRoot = Join-Path (Split-Path -Parent $resizeRepoRoot) '.toolchain\flutter-3.47.5'
}
$resizeFlutterRoot = [System.IO.Path]::GetFullPath($FlutterRoot)
$resizeEngineRoot = Join-Path $resizeFlutterRoot 'bin\cache\artifacts\engine\windows-x64-release'
$resizeImportLibrary = Join-Path $resizeEngineRoot 'flutter_windows.dll.lib'
$resizeEngineDll = Join-Path $resizeEngineRoot 'flutter_windows.dll'
if (!(Test-Path -LiteralPath $resizeImportLibrary) -or !(Test-Path -LiteralPath $resizeEngineDll)) {
    throw 'Flutter Windows release artifacts are missing. Pass -FlutterRoot with the matching Flutter SDK.'
}

$resizeVsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (!(Test-Path -LiteralPath $resizeVsWhere)) {
    throw 'Visual Studio Installer/vswhere.exe was not found.'
}
$resizeVsRoot = & $resizeVsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ([string]::IsNullOrWhiteSpace($resizeVsRoot)) {
    throw 'Visual Studio C++ build tools were not found.'
}
$resizeVsDevCmd = Join-Path $resizeVsRoot 'Common7\Tools\VsDevCmd.bat'
$resizeDevCommand = 'call "' + $resizeVsDevCmd + '" -no_logo -arch=x64 -host_arch=x64 >nul && set'
# Capture the developer environment without printing environment values.
$resizeEnvironmentLines = & $env:ComSpec /d /c $resizeDevCommand
if ($LASTEXITCODE -ne 0) {
    throw 'Could not initialize the Visual Studio developer environment.'
}
foreach ($resizeLine in $resizeEnvironmentLines) {
    $resizeEquals = $resizeLine.IndexOf('=')
    if ($resizeEquals -gt 0) {
        Set-Item -Path ('Env:' + $resizeLine.Substring(0, $resizeEquals)) -Value $resizeLine.Substring($resizeEquals + 1)
    }
}

# All generated files stay under the existing ignored Flutter build directory.
$resizeBuildRoot = Join-Path $resizeRepoRoot 'src\build\native_resize_test'
New-Item -ItemType Directory -Path $resizeBuildRoot -Force | Out-Null
$resizeRunnerRoot = Join-Path $resizeRepoRoot 'src\windows\runner'
$resizeExecutable = Join-Path $resizeBuildRoot 'window_resize_test.exe'
$resizeCompileArguments = @(
    '/nologo', '/std:c++17', '/EHsc', '/MD', '/W4', '/WX', '/DUNICODE', '/D_UNICODE', '/DNOMINMAX',
    ('/I' + $resizeRunnerRoot), ('/I' + $resizeEngineRoot),
    ('/Fo' + $resizeBuildRoot + '\'),
    ('/Fd' + (Join-Path $resizeBuildRoot 'window_resize_test.pdb')),
    ('/Fe' + $resizeExecutable),
    (Join-Path $PSScriptRoot 'tests\window_resize_test.cpp'),
    (Join-Path $resizeRunnerRoot 'win32_window.cpp'),
    '/link', $resizeImportLibrary, 'user32.lib', 'dwmapi.lib', 'advapi32.lib'
)
& cl.exe @resizeCompileArguments
if ($LASTEXITCODE -ne 0) {
    throw 'The native resize regression test did not compile.'
}
Copy-Item -LiteralPath $resizeEngineDll -Destination (Join-Path $resizeBuildRoot 'flutter_windows.dll') -Force
& $resizeExecutable
if ($LASTEXITCODE -ne 0) {
    throw 'The native resize regression test failed.'
}
