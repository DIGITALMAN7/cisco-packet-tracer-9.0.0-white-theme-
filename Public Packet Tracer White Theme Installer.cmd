@echo off
setlocal
set "LAUNCHER=%~f0"
set "INSTALL_DIR=%ProgramFiles%\Cisco Packet Tracer 9.0.0"
set "INSTALLED_LAUNCHER=%INSTALL_DIR%\Public Packet Tracer White Theme Installer.cmd"
if /I not "%~f0"=="%INSTALLED_LAUNCHER%" if /I not "%~1"=="--installed" if /I not "%~1"=="--install" (
    echo Installing Public Packet Tracer White Theme. Administrator approval is required.
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs -WindowStyle Hidden -Wait -ArgumentList '--install'"
    exit /b %ERRORLEVEL%
)
if /I "%~1"=="--install" (
    if not exist "%INSTALL_DIR%\bin\PacketTracer.exe" (
        echo Packet Tracer 9.0.0 was not found.
        pause
        exit /b 1
    )
    copy /Y "%~f0" "%INSTALLED_LAUNCHER%" >nul
    if not exist "%INSTALLED_LAUNCHER%" (
        echo Could not install the launcher.
        pause
        exit /b 1
    )
    start "" /b "%INSTALLED_LAUNCHER%" --installed
    exit /b 0
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$lines = Get-Content -LiteralPath '%~f0'; $marker = [Array]::IndexOf($lines, ':PowerShell'); & ([scriptblock]::Create(($lines[($marker + 1)..($lines.Length - 1)] -join [Environment]::NewLine)))"
exit /b %ERRORLEVEL%

:PowerShell
$themeKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$themesKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes'
$packetTracerPath = Join-Path $env:ProgramFiles 'Cisco Packet Tracer 9.0.0\bin\PacketTracer.exe'
$searchRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ -and (Test-Path $_) }
$packetTracer = Get-ChildItem -Path $searchRoots -Filter PacketTracer.exe -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\Cisco Packet Tracer[^\\]*\\bin\\PacketTracer\.exe$' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -eq $packetTracer) {
    Write-Host 'Packet Tracer 9.0.0 was not found.' -ForegroundColor Red
    Read-Host 'Press Enter to close'
    exit 1
}

if (Test-Path $packetTracerPath) {
    $packetTracer = Get-Item -LiteralPath $packetTracerPath
}

$firewallRules = @(
    @{ Name = 'Packet Tracer White Theme - Block Inbound Private Public'; Direction = 'Inbound' },
    @{ Name = 'Packet Tracer White Theme - Block Outbound Private Public'; Direction = 'Outbound' }
)
foreach ($firewallRule in $firewallRules) {
    if ($null -eq (Get-NetFirewallRule -DisplayName $firewallRule.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $firewallRule.Name -Direction $firewallRule.Direction -Program $packetTracer.FullName -Action Block -Profile Private,Public -Protocol Any -Enabled True -ErrorAction SilentlyContinue | Out-Null
    }
}

$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop 'Public Packet Tracer White Theme.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $PSHOME 'powershell.exe'
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "& { & ''' + $env:LAUNCHER + ''' }"'
$shortcut.WorkingDirectory = Split-Path $env:LAUNCHER
$shortcut.IconLocation = "$($packetTracer.FullName),0"
$shortcut.Description = 'Launch Packet Tracer with a white theme'
$shortcut.Save()

try {
    Set-ItemProperty -Path $themeKey -Name AppsUseLightTheme -Value 1 -Type DWord
    Set-ItemProperty -Path $themeKey -Name SystemUsesLightTheme -Value 1 -Type DWord
    $packetTracerProcess = Start-Process -FilePath $packetTracer.FullName -PassThru
    $packetTracerProcess.WaitForExit()
}
finally {
    Set-ItemProperty -Path $themeKey -Name AppsUseLightTheme -Value 0 -Type DWord
    Set-ItemProperty -Path $themeKey -Name SystemUsesLightTheme -Value 0 -Type DWord
    Set-ItemProperty -Path $themesKey -Name CurrentTheme -Value "$env:windir\Resources\Themes\aero.theme"

    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ThemeRefresh {
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint msg, UIntPtr wParam, string lParam,
        uint flags, uint timeout, out UIntPtr result);
}
'@
    [UIntPtr]$result = [UIntPtr]::Zero
    [ThemeRefresh]::SendMessageTimeout(
        [IntPtr]0xffff, 0x001A, [UIntPtr]::Zero,
        'ImmersiveColorSet', 0x0002, 1000, [ref]$result) | Out-Null
}
