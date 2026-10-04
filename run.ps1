<#
.SYNOPSIS
    Runs the Godot client on the desktop, emulating a phone screen.
.EXAMPLE
    .\run.ps1 -Device iphone_15
.EXAMPLE
    .\run.ps1 -Device iphone_17_pro -ScreenDpi 109
.EXAMPLE
    .\run.ps1 -Server http://10.20.30.5:7350
.EXAMPLE
    .\run.ps1 -OfficeScreen -Office office_1a2b3c4d
.NOTES
    The game always needs the Nakama server (server/, docker compose up), 127.0.0.1:7350 by default.
    The office screen gets its codes with the server's HTTP key, read from server\.env.
#>
param(
    [ValidateSet('pixel_8', 'iphone_15', 'iphone_17_pro', 'iphone_17_pro_max', 'galaxy_s24', 'android_hd', 'iphone_se', 'desktop')]
    [string]$Device = 'pixel_8',
    # Monitor pixel density for the real-size phone window; the OS value is used when omitted.
    [double]$ScreenDpi = 0,
    # Show the reception screen with the rotating entry and exit QR codes instead of the game.
    [switch]$OfficeScreen,
    # Office of the screen (id from the admin panel); the default office when omitted.
    [string]$Office = '',
    # Another Nakama server, e.g. http://10.20.30.5:7350.
    [string]$Server = ''
)

$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'client'
$godotDir = Join-Path $PSScriptRoot 'tools\godot'

$console = Get-ChildItem $godotDir -Filter 'Godot_v*_win64_console.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
$gui = Get-ChildItem $godotDir -Filter 'Godot_v*_win64.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $console -or -not $gui) {
    throw "Godot not found in $godotDir. Download Godot 4.7 (win64) and unpack it there."
}

if (-not (Test-Path (Join-Path $project '.godot'))) {
    Write-Host 'First run: importing assets...'
    & $console.FullName --headless --path $project --import
}

$arguments = @('--path', "`"$project`"")
if ($OfficeScreen) {
    $arguments += @('res://scenes/kiosk/office_screen.tscn', '--resolution', '720x960')
    $envFile = Join-Path $PSScriptRoot 'server\.env'
    $keyLine = if (Test-Path $envFile) { Get-Content $envFile | Where-Object { $_ -match '^NAKAMA_HTTP_KEY=' } | Select-Object -First 1 }
    if ($keyLine) {
        $arguments += @('--', "--kiosk-key=$($keyLine.Split('=', 2)[1])")
        if ($Office) {
            $arguments += "--kiosk-office=$Office"
        }
    }
    else {
        Write-Warning 'NAKAMA_HTTP_KEY not found in server\.env: the office screen cannot get its codes.'
    }
}
else {
    $gameArguments = @()
    if ($Device -ne 'desktop') {
        $gameArguments += "--device=$Device"
        if ($ScreenDpi -gt 0) {
            $gameArguments += "--screen-dpi=$([string]::Format([cultureinfo]::InvariantCulture, '{0}', $ScreenDpi))"
        }
    }
    if ($Server) {
        $gameArguments += "--server=$Server"
    }
    if ($gameArguments.Count -gt 0) {
        $arguments += @('--') + $gameArguments
    }
}
Start-Process -FilePath $gui.FullName -ArgumentList $arguments
