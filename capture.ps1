param(
    [Parameter(Mandatory=$true)][string]$FixtureDir,
    [Parameter(Mandatory=$true)][string]$TestBinary,
    [string]$Theme = 'dark',
    [string]$Language = 'en-US',
    [string]$State = '',
    [switch]$Narrow
)
$ErrorActionPreference = 'Stop'
$fixtureRoot = [IO.Path]::GetFullPath($FixtureDir)
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $PWD 'tmp')) + [IO.Path]::DirectorySeparatorChar
if (-not $fixtureRoot.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Fixture must stay inside this contribution tmp directory'
}
if (Test-Path -LiteralPath $fixtureRoot) { throw 'Use a fresh fixture directory' }
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$configRoot = Join-Path $fixtureRoot 'config'
New-Item -ItemType Directory -Path $configRoot | Out-Null
$themeSetting = if ($Theme -eq 'light') { 'WarmSand' } else { 'Nord' }
$settingsText = @"
terminal_startup=welcome
restore_session=0
keep_session=0
new_tab_position=end
tabs_position=top
startup_directory=
shell=cmd
fetch=0
theme=$themeSetting
follow_system_theme=0
language=$Language
"@
[IO.File]::WriteAllText((Join-Path $configRoot 'pebrel_settings.txt'), $settingsText, [Text.UTF8Encoding]::new($false))
$env:PEBREL_CONFIG_DIR = $configRoot
$env:PEBREL_WELCOME_QA_DIR = $fixtureRoot
$env:PEBREL_WELCOME_QA_THEME = $Theme
$env:PEBREL_WELCOME_QA_STATE = if ($State.StartsWith('settings')) { 'ssh' } else { $State }
$env:PEBREL_WELCOME_QA_NARROW = if ($Narrow) { '1' } else { '0' }
$env:TEMP = $fixtureRoot
$env:TMP = $fixtureRoot
$nativeTest = 'gpui_shell::workspace::startup::native_tests::native_welcome_preview'
$child = Start-Process -FilePath $TestBinary -ArgumentList @($nativeTest, '--exact', '--ignored', '--test-threads=1', '--nocapture') -WindowStyle Hidden -WorkingDirectory $fixtureRoot -RedirectStandardOutput (Join-Path $fixtureRoot 'stdout.log') -RedirectStandardError (Join-Path $fixtureRoot 'stderr.log') -PassThru
$processHandle = $child.Handle
$savedPointer = $null
try {
    $readyPath = Join-Path $fixtureRoot 'window-ready'
    for ($attempt = 0; $attempt -lt 200 -and -not (Test-Path -LiteralPath $readyPath); $attempt++) {
        if ($child.HasExited) { throw "Native fixture exited early: $($child.ExitCode)" }
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path -LiteralPath $readyPath)) { throw 'Native fixture did not become ready' }
    $nativePid = [int][IO.File]::ReadAllText($readyPath)
    if ($nativePid -ne $child.Id) { throw 'Unexpected fixture process identity' }
    $windowHandle = [IntPtr][long][IO.File]::ReadAllText((Join-Path $fixtureRoot 'window-handle'))
    if ($windowHandle -eq [IntPtr]::Zero) { throw 'Fixture did not provide its native window' }
    # CopyFromScreen includes covering windows. Capture this fixture's client directly.
    Add-Type -AssemblyName System.Drawing
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WelcomeCaptureNative {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr handle, out Rect rect);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr handle, IntPtr dc, uint flags);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr handle, out uint pid);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr handle, int command);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr handle, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr handle, uint message, IntPtr wparam, IntPtr lparam);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr handle, ref Point point);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
}
'@
    [uint32]$windowOwner = 0
    $null = [WelcomeCaptureNative]::GetWindowThreadProcessId($windowHandle, [ref]$windowOwner)
    if ($windowOwner -ne $child.Id) { throw 'Capture window is not owned by this fixture' }
    $null = [WelcomeCaptureNative]::SetProcessDPIAware()
    $null = [WelcomeCaptureNative]::ShowWindow($windowHandle, 5)
    if (-not [WelcomeCaptureNative]::SetWindowPos($windowHandle, [IntPtr](-1), 0, 0, 0, 0, 0x53)) { throw 'Could not show the owned preview window' }
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'shown'), 'shown')
    for ($attempt = 0; $attempt -lt 200 -and -not (Test-Path -LiteralPath (Join-Path $fixtureRoot 'ready')); $attempt++) {
        if ($child.HasExited) { throw "Native fixture exited during input: $($child.ExitCode)" }
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path -LiteralPath (Join-Path $fixtureRoot 'ready'))) { throw 'Native fixture did not finish input' }
    if ($State -match '^(hover|pressed)(-ssh)?$' -or $State.StartsWith('settings')) {
        $layout = Get-Content -LiteralPath (Join-Path $fixtureRoot 'layout.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($layout.width -ne 1000 -or $layout.height -ne 720) { throw 'Pointer coordinates require the inspected full-size layout' }
        $savedPointer = [WelcomeCaptureNative+Point]::new()
        $null = [WelcomeCaptureNative]::GetCursorPos([ref]$savedPointer)
        $logicalX = if ($State.StartsWith('settings')) { 90 } else { 500 }
        $logicalY = if ($State.StartsWith('settings')) { 238 } elseif ($State.EndsWith('ssh')) { 464 } else { 404 }
        $clientX = [int]($logicalX * $layout.scale)
        $clientY = [int]($logicalY * $layout.scale)
        $pointer = [WelcomeCaptureNative+Point]::new()
        $pointer.X = $clientX
        $pointer.Y = $clientY
        $null = [WelcomeCaptureNative]::ClientToScreen($windowHandle, [ref]$pointer)
        $null = [WelcomeCaptureNative]::SetCursorPos($pointer.X, $pointer.Y)
        Start-Sleep -Milliseconds 200
        if ($State.StartsWith('pressed') -or $State.StartsWith('settings')) {
            $coordinates = [IntPtr](($clientY -shl 16) -bor $clientX)
            $null = [WelcomeCaptureNative]::SendMessage($windowHandle, 0x201, [IntPtr]1, $coordinates)
            if ($State.StartsWith('settings')) {
                $null = [WelcomeCaptureNative]::SendMessage($windowHandle, 0x202, [IntPtr]::Zero, $coordinates)
            }
        }
        if ($State -eq 'settings-dropdown') {
            Start-Sleep -Milliseconds 200
            $coordinates = [IntPtr](([int](174 * $layout.scale) -shl 16) -bor [int](860 * $layout.scale))
            $null = [WelcomeCaptureNative]::SendMessage($windowHandle, 0x200, [IntPtr]::Zero, $coordinates)
            $null = [WelcomeCaptureNative]::SendMessage($windowHandle, 0x201, [IntPtr]1, $coordinates)
            $null = [WelcomeCaptureNative]::SendMessage($windowHandle, 0x202, [IntPtr]::Zero, $coordinates)
        }
    }
    $null = [WelcomeCaptureNative]::SendMessage($windowHandle, 15, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 250
    $rect = [WelcomeCaptureNative+Rect]::new()
    if (-not [WelcomeCaptureNative]::GetClientRect($windowHandle, [ref]$rect)) { throw 'Client geometry unavailable' }
    $bitmap = [Drawing.Bitmap]::new($rect.Right, $rect.Bottom, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $dc = $graphics.GetHdc()
    try {
        if (-not [WelcomeCaptureNative]::PrintWindow($windowHandle, $dc, 3)) { throw 'Native client capture failed' }
    } finally { $graphics.ReleaseHdc($dc); $graphics.Dispose() }
    try { $bitmap.Save((Join-Path $fixtureRoot 'preview.png'), [Drawing.Imaging.ImageFormat]::Png) }
    finally { $bitmap.Dispose() }
    Join-Path $fixtureRoot 'preview.png'
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'capture-complete'), 'captured')
    if (-not $child.WaitForExit(5000)) { throw 'Native fixture did not shut down' }
    if ($null -ne $child.ExitCode -and $child.ExitCode -ne 0) { throw "Native fixture failed: $($child.ExitCode)" }
    if ([IO.File]::ReadAllText((Join-Path $fixtureRoot 'stdout.log')) -notmatch 'test result: ok[.] 1 passed; 0 failed') { throw 'Native harness did not report success' }
    Get-Content -LiteralPath (Join-Path $fixtureRoot 'stdout.log') -Encoding UTF8 -Tail 5
    if (Test-Path -LiteralPath (Join-Path $fixtureRoot 'shell-pid')) {
        'Real shell PID: ' + [IO.File]::ReadAllText((Join-Path $fixtureRoot 'shell-pid'))
    }
} finally {
    if ($null -ne $savedPointer) { $null = [WelcomeCaptureNative]::SetCursorPos($savedPointer.X, $savedPointer.Y) }
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'capture-complete'), 'complete')
    if (-not $child.HasExited) {
        if (-not $child.WaitForExit(5000)) { Stop-Process -Id $child.Id -Force }
    }
}
