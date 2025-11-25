#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Uitgebreid systeem update script voor Windows 11 met hardware driver checks
    
.DESCRIPTION
    Dit script controleert en installeert:
    - Windows Updates (inclusief optionele updates)
    - Winget package updates (alle geinstalleerde programma's)
    - NVIDIA driver updates
    - AMD driver updates (optioneel)
    
    Alle acties worden gelogd naar een bestand voor troubleshooting
    
.PARAMETER AutoInstall
    Automatisch installeren zonder confirmatie vragen
    
.PARAMETER SkipReboot
    Voorkomt automatische herstart na updates
    
.EXAMPLE
    .\Update-SystemComplete.ps1 -AutoInstall
    
.NOTES
    Author: Claude (voor Jonas)
    Requires: Administrator rechten
    Version: 1.2 (ASCII fix + Winget detection)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$AutoInstall = $false,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipReboot = $false,
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:USERPROFILE\Desktop\SystemUpdateLogs"
)

# Set console encoding to UTF-8 (just in case)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ============================================================================
# CONFIGURATIE
# ============================================================================

$Script:Config = @{
    LogPath           = $LogPath
    LogFile           = Join-Path $LogPath "UpdateLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    ErrorLogFile      = Join-Path $LogPath "UpdateErrors_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    RebootRequired    = $false
    EmailNotification = $false  # Optie om email notificaties toe te voegen
}

# ============================================================================
# LOGGING FUNCTIES
# ============================================================================

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Console output met kleuren
    switch ($Level) {
        'ERROR' { Write-Host $logMessage -ForegroundColor Red }
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor White }
    }
    
    # Schrijf naar log bestand
    Add-Content -Path $Script:Config.LogFile -Value $logMessage
    
    # Schrijf errors naar apart error log
    if ($Level -eq 'ERROR') {
        Add-Content -Path $Script:Config.ErrorLogFile -Value $logMessage
    }
}

function Initialize-Logging {
    # Maak log directory aan als deze niet bestaat
    if (-not (Test-Path $Script:Config.LogPath)) {
        New-Item -Path $Script:Config.LogPath -ItemType Directory -Force | Out-Null
        Write-Log "Log directory aangemaakt: $($Script:Config.LogPath)" -Level INFO
    }
    
    # Verwijder oude logs (ouder dan 30 dagen)
    Get-ChildItem -Path $Script:Config.LogPath -Filter "*.log" | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | 
    Remove-Item -Force
    
    Write-Log "==============================================" -Level INFO
    Write-Log "START SYSTEEM UPDATE SESSIE" -Level INFO
    Write-Log "Computer: $env:COMPUTERNAME" -Level INFO
    Write-Log "Gebruiker: $env:USERNAME" -Level INFO
    Write-Log "Datum: $(Get-Date -Format 'dd-MM-yyyy HH:mm:ss')" -Level INFO
    Write-Log "==============================================" -Level INFO
}

# ============================================================================
# HELPER FUNCTIES
# ============================================================================

function Test-AdminRights {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-InternetConnection {
    try {
        $testConnection = Test-Connection -ComputerName "8.8.8.8" -Count 2 -Quiet -ErrorAction Stop
        return $testConnection
    }
    catch {
        return $false
    }
}

function Install-RequiredModule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )
    
    Write-Log "Controleren of module $ModuleName geinstalleerd is..." -Level INFO
    
    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Log "Module $ModuleName niet gevonden. Installeren..." -Level WARNING
        try {
            # Zorg dat NuGet provider geinstalleerd is
            if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false | Out-Null
            }
            
            # Installeer de module
            Install-Module -Name $ModuleName -Force -AllowClobber -Scope CurrentUser -Confirm:$false
            Write-Log "Module $ModuleName succesvol geinstalleerd" -Level SUCCESS
            return $true
        }
        catch {
            Write-Log "Fout bij installeren van module $ModuleName : $($_.Exception.Message)" -Level ERROR
            return $false
        }
    }
    else {
        Write-Log "Module $ModuleName is al geinstalleerd" -Level SUCCESS
        return $true
    }
}

# ============================================================================
# WINDOWS UPDATE FUNCTIES
# ============================================================================

function Update-WindowsSystem {
    Write-Log "`n=== WINDOWS UPDATES CONTROLEREN ===" -Level INFO
    
    # Installeer PSWindowsUpdate module indien nodig
    if (-not (Install-RequiredModule -ModuleName "PSWindowsUpdate")) {
        Write-Log "Kan Windows Updates niet uitvoeren zonder PSWindowsUpdate module" -Level ERROR
        return $false
    }
    
    try {
        Import-Module PSWindowsUpdate -ErrorAction Stop
        
        Write-Log "Zoeken naar beschikbare Windows Updates..." -Level INFO
        
        # Haal alle beschikbare updates op
        $updates = Get-WindowsUpdate -MicrosoftUpdate -Verbose:$false
        
        if ($updates.Count -eq 0) {
            Write-Log "Geen Windows Updates beschikbaar" -Level SUCCESS
            return $true
        }
        
        Write-Log "Gevonden: $($updates.Count) update(s)" -Level WARNING
        
        # Toon updates
        foreach ($update in $updates) {
            Write-Log "  - $($update.Title) [Size: $([math]::Round($update.Size/1MB, 2)) MB]" -Level INFO
        }
        
        if (-not $AutoInstall) {
            $response = Read-Host "`nWil je deze updates installeren? (Y/N)"
            if ($response -notmatch '^[Yy]') {
                Write-Log "Windows Updates overgeslagen door gebruiker" -Level WARNING
                return $true
            }
        }
        
        Write-Log "Installeren van Windows Updates..." -Level INFO
        
        # Installeer updates
        $installResult = Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot:$false -Verbose:$false
        
        # Check of herstart nodig is
        if ($installResult | Where-Object { $_.RebootRequired -eq $true }) {
            $Script:Config.RebootRequired = $true
            Write-Log "WAARSCHUWING: Herstart is vereist na Windows Updates" -Level WARNING
        }
        
        Write-Log "Windows Updates succesvol geinstalleerd" -Level SUCCESS
        return $true
        
    }
    catch {
        Write-Log "Fout bij Windows Updates: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

# ============================================================================
# WINGET PACKAGE UPDATE FUNCTIES
# ============================================================================

function Update-WingetPackages {
    Write-Log "`n=== WINGET PACKAGES CONTROLEREN ===" -Level INFO
    
    # Zoek winget executable via AppxPackage (betrouwbaarder)
    $wingetPath = "winget"
    $foundWinget = $false
    
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $wingetPath = "winget"
        $foundWinget = $true
    }
    else {
        # Probeer via AppxPackage locatie
        $appInstaller = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue
        if ($appInstaller) {
            $possiblePath = Join-Path $appInstaller.InstallLocation "winget.exe"
            if (Test-Path $possiblePath) {
                $wingetPath = $possiblePath
                $foundWinget = $true
            }
            else {
                # Soms zit het in een subdirectory of is de alias de enige weg
                $localAppDataPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
                if (Test-Path $localAppDataPath) {
                    $wingetPath = $localAppDataPath
                    $foundWinget = $true
                }
            }
        }
        
        # Fallback: Program Files zoektocht
        if (-not $foundWinget) {
            $pfWinget = Get-ChildItem "C:\Program Files\WindowsApps" -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($pfWinget) {
                $wingetPath = $pfWinget.FullName
                $foundWinget = $true
            }
        }
    }
    
    if (-not $foundWinget) {
        Write-Log "Winget is niet geinstalleerd of niet gevonden" -Level ERROR
        Write-Log "Installeer App Installer vanuit de Microsoft Store" -Level WARNING
        return $false
    }
    
    try {
        Write-Log "Winget gevonden: $wingetPath" -Level INFO
        Write-Log "Zoeken naar beschikbare package updates... (Dit kan even duren)" -Level INFO
        
        # Haal lijst op van packages met beschikbare updates
        # Toevoegen van --accept-source-agreements en --disable-interactivity om hangen te voorkomen
        $upgradeList = & $wingetPath upgrade --include-unknown --accept-source-agreements --disable-interactivity 2>&1 | Out-String
        
        Write-Log "Winget output:`n$upgradeList" -Level INFO
        
        # Parse de output om te zien of er updates zijn
        if ($upgradeList -match "No installed package found matching input criteria" -or 
            $upgradeList -match "No applicable update found") {
            Write-Log "Geen package updates beschikbaar via Winget" -Level SUCCESS
            return $true
        }
        
        if (-not $AutoInstall) {
            $response = Read-Host "`nWil je alle beschikbare package updates installeren? (Y/N)"
            if ($response -notmatch '^[Yy]') {
                Write-Log "Winget package updates overgeslagen door gebruiker" -Level WARNING
                return $true
            }
        }
        
        Write-Log "Installeren van alle beschikbare package updates..." -Level INFO
        
        # Upgrade alle packages
        $upgradeResult = & $wingetPath upgrade --all --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-String
        
        Write-Log "Winget upgrade resultaat:`n$upgradeResult" -Level INFO
        Write-Log "Winget packages succesvol geupdatet" -Level SUCCESS
        
        return $true
        
    }
    catch {
        Write-Log "Fout bij Winget updates: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

# ============================================================================
# NVIDIA DRIVER UPDATE FUNCTIES
# ============================================================================

function Get-NvidiaLatestDriver {
    Write-Log "`n=== NVIDIA DRIVER CONTROLEREN ===" -Level INFO
    
    try {
        # Check of NVIDIA GPU aanwezig is
        $nvidiaGPU = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -like "*NVIDIA*" }
        
        if (-not $nvidiaGPU) {
            Write-Log "Geen NVIDIA GPU gevonden" -Level INFO
            return $null
        }
        
        Write-Log "NVIDIA GPU gevonden: $($nvidiaGPU.Name)" -Level INFO
        
        # Haal huidige driver versie op
        $currentDriver = Get-CimInstance Win32_PnPSignedDriver | 
        Where-Object { $_.DeviceName -like "*NVIDIA*" -and $_.DriverVersion } | 
        Select-Object -First 1
        
        if ($currentDriver) {
            Write-Log "Huidige NVIDIA driver versie: $($currentDriver.DriverVersion)" -Level INFO
        }
        
        # GeForce Experience / NVIDIA App check
        $gfePath = "C:\Program Files\NVIDIA Corporation\NVIDIA GeForce Experience\NVIDIA GeForce Experience.exe"
        $nvidiaAppFound = $false
        
        if (Test-Path $gfePath) {
            $nvidiaAppFound = $true
        }
        else {
            # Check Registry for NVIDIA GeForce Experience or NVIDIA App
            $uninstallKeys = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue
            foreach ($key in $uninstallKeys) {
                $props = Get-ItemProperty $key.PSPath
                if ($props.DisplayName -match "NVIDIA GeForce Experience|NVIDIA App") {
                    $nvidiaAppFound = $true
                    break
                }
            }
            
            # Fallback: Check Service
            if (-not $nvidiaAppFound) {
                if (Get-Service "NvContainerLocalSystem" -ErrorAction SilentlyContinue) {
                    $nvidiaAppFound = $true
                }
            }
        }

        if ($nvidiaAppFound) {
            Write-Log "GeForce Experience / NVIDIA App gedetecteerd" -Level INFO
            Write-Log "Open de NVIDIA app handmatig om te controleren op driver updates" -Level WARNING
            Write-Log "Of download de nieuwste driver van: https://www.nvidia.com/Download/index.aspx" -Level INFO
        }
        else {
            Write-Log "GeForce Experience niet gevonden" -Level WARNING
            Write-Log "Installeer GeForce Experience voor automatische driver updates" -Level INFO
            Write-Log "Of download drivers handmatig van: https://www.nvidia.com/Download/index.aspx" -Level INFO
        }
        
        return $currentDriver
        
    }
    catch {
        Write-Log "Fout bij NVIDIA driver check: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

# ============================================================================
# AMD DRIVER UPDATE FUNCTIES
# ============================================================================

function Get-AMDLatestDriver {
    Write-Log "`n=== AMD PROCESSOR/CHIPSET CONTROLEREN ===" -Level INFO
    
    try {
        # Check of AMD processor aanwezig is
        $amdCPU = Get-CimInstance Win32_Processor | Where-Object { $_.Name -like "*AMD*" }
        
        if (-not $amdCPU) {
            Write-Log "Geen AMD processor gevonden" -Level INFO
            return $null
        }
        
        Write-Log "AMD Processor gevonden: $($amdCPU.Name)" -Level INFO
        
        # Check voor AMD Software (vroeger Radeon Software)
        $amdSoftware = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
        Where-Object { $_.DisplayName -like "*AMD*" -or $_.DisplayName -like "*Radeon*" } | 
        Select-Object -First 1
        
        if ($amdSoftware) {
            Write-Log "AMD Software gedetecteerd: $($amdSoftware.DisplayName)" -Level INFO
            Write-Log "Open AMD Software handmatig om te controleren op updates" -Level WARNING
        }
        else {
            Write-Log "AMD Software niet gevonden" -Level WARNING
            Write-Log "Download AMD drivers van: https://www.amd.com/en/support" -Level INFO
        }
        
        # AMD chipset drivers worden vaak via Windows Update of Winget geupdatet
        Write-Log "AMD chipset drivers worden meestal via Windows Update geupdatet" -Level INFO
        
        return $amdCPU
        
    }
    catch {
        Write-Log "Fout bij AMD driver check: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

# ============================================================================
# ASUS SPECIFIEKE UPDATES
# ============================================================================

function Get-AsusUpdates {
    Write-Log "`n=== ASUS UPDATES CONTROLEREN ===" -Level INFO
    
    try {
        # Check of MyASUS app geinstalleerd is (Check op PackageFamilyName deel)
        $myAsus = Get-AppxPackage -Name "*ASUSPCAssis*" 
        
        if ($myAsus) {
            Write-Log "MyASUS app gevonden" -Level SUCCESS
            Write-Log "Open MyASUS app handmatig voor BIOS en firmware updates" -Level WARNING
            Write-Log "WAARSCHUWING: BIOS updates dienen ALTIJD handmatig te gebeuren!" -Level WARNING
        }
        else {
            Write-Log "MyASUS app niet gevonden" -Level WARNING
            Write-Log "Download MyASUS vanuit de Microsoft Store voor ASUS updates" -Level INFO
        }
        
        # ASUS software via winget
        Write-Log "ASUS software wordt geupdatet via Winget (indien beschikbaar)" -Level INFO
        
    }
    catch {
        Write-Log "Fout bij ASUS update check: $($_.Exception.Message)" -Level ERROR
    }
}

# ============================================================================
# SYSTEEM INFORMATIE
# ============================================================================

function Show-SystemInfo {
    Write-Log "`n=== SYSTEEM INFORMATIE ===" -Level INFO
    
    try {
        # OS Info
        $os = Get-CimInstance Win32_OperatingSystem
        Write-Log "OS: $($os.Caption) - Build $($os.BuildNumber)" -Level INFO
        
        # CPU Info
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        Write-Log "CPU: $($cpu.Name)" -Level INFO
        
        # RAM Info
        $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
        Write-Log "RAM: $ram GB" -Level INFO
        
        # GPU Info
        $gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1
        Write-Log "GPU: $($gpu.Name)" -Level INFO
        
        # Disk Info
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        $diskSizeGB = [math]::Round($disk.Size / 1GB, 2)
        Write-Log "Disk C: $diskFreeGB GB vrij van $diskSizeGB GB" -Level INFO
        
    }
    catch {
        Write-Log "Fout bij ophalen systeem informatie: $($_.Exception.Message)" -Level ERROR
    }
}

# ============================================================================
# REBOOT FUNCTIE
# ============================================================================

function Request-Reboot {
    if ($Script:Config.RebootRequired) {
        Write-Log "`n==============================================" -Level WARNING
        Write-Log "HERSTART VEREIST" -Level WARNING
        Write-Log "==============================================" -Level WARNING
        
        if ($SkipReboot) {
            Write-Log "Automatische herstart overgeslagen door parameter" -Level WARNING
            Write-Log "Gelieve handmatig te herstarten om updates te voltooien" -Level WARNING
            return
        }
        
        if (-not $AutoInstall) {
            $response = Read-Host "`nWil je nu herstarten? (Y/N)"
            if ($response -notmatch '^[Yy]') {
                Write-Log "Herstart uitgesteld door gebruiker" -Level WARNING
                return
            }
        }
        
        Write-Log "Computer wordt over 60 seconden herstart..." -Level WARNING
        Write-Log "Druk op Ctrl+C om te annuleren" -Level WARNING
        
        Start-Sleep -Seconds 10
        
        # Shutdown met 50 seconden delay
        shutdown /r /t 50 /c "Systeem herstart vereist na updates. Sla je werk op!"
        
    }
    else {
        Write-Log "`nGeen herstart vereist" -Level SUCCESS
    }
}

# ============================================================================
# MAIN FUNCTIE
# ============================================================================

function Start-SystemUpdate {
    # Check admin rechten
    if (-not (Test-AdminRights)) {
        Write-Host "ERROR: Dit script vereist Administrator rechten!" -ForegroundColor Red
        Write-Host "Klik rechts op het script en kies 'Run as Administrator'" -ForegroundColor Yellow
        Read-Host "Druk op Enter om af te sluiten"
        exit 1
    }
    
    # Initialize logging
    Initialize-Logging
    
    # Check internet connectie
    if (-not (Test-InternetConnection)) {
        Write-Log "WAARSCHUWING: Geen internet connectie gedetecteerd" -Level WARNING
        Write-Log "Sommige updates kunnen niet worden uitgevoerd" -Level WARNING
        $continue = Read-Host "Wil je toch doorgaan? (Y/N)"
        if ($continue -notmatch '^[Yy]') {
            Write-Log "Script afgebroken door gebruiker" -Level INFO
            return
        }
    }
    
    # Toon systeem info
    Show-SystemInfo
    
    # Vraag bevestiging indien niet auto
    if (-not $AutoInstall) {
        Write-Host "`n=============================================="
        Write-Host "DIT SCRIPT ZAL DE VOLGENDE ACTIES UITVOEREN:"
        Write-Host "=============================================="
        Write-Host "1. Windows Updates installeren"
        Write-Host "2. Winget packages updaten"
        Write-Host "3. NVIDIA drivers controleren"
        Write-Host "4. AMD drivers controleren"
        Write-Host "5. ASUS updates controleren"
        Write-Host "==============================================`n"
        
        $confirm = Read-Host "Wil je doorgaan? (Y/N)"
        if ($confirm -notmatch '^[Yy]') {
            Write-Log "Script afgebroken door gebruiker" -Level INFO
            return
        }
    }
    
    # Voer updates uit
    $windowsUpdateSuccess = Update-WindowsSystem
    $wingetUpdateSuccess = Update-WingetPackages
    Get-NvidiaLatestDriver | Out-Null
    Get-AMDLatestDriver | Out-Null
    Get-AsusUpdates
    
    # Summary
    Write-Log "`n===============================================" -Level INFO
    Write-Log "UPDATE SESSIE VOLTOOID" -Level SUCCESS
    Write-Log "===============================================" -Level INFO
    Write-Log "Windows Updates: $(if($windowsUpdateSuccess){'[OK] Succesvol'}else{'[ERROR] Gefaald'})" -Level $(if ($windowsUpdateSuccess) { 'SUCCESS' }else { 'ERROR' })
    Write-Log "Winget Updates: $(if($wingetUpdateSuccess){'[OK] Succesvol'}else{'[ERROR] Gefaald'})" -Level $(if ($wingetUpdateSuccess) { 'SUCCESS' }else { 'ERROR' })
    Write-Log "Log bestand: $($Script:Config.LogFile)" -Level INFO
    Write-Log "===============================================`n" -Level INFO
    
    # Check voor herstart
    Request-Reboot
    
    Write-Log "Script voltooid om $(Get-Date -Format 'HH:mm:ss')" -Level SUCCESS
}

# ============================================================================
# START SCRIPT
# ============================================================================

try {
    Start-SystemUpdate
}
catch {
    Write-Host "KRITIEKE FOUT: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    Read-Host "Druk op Enter om af te sluiten"
    exit 1
}
finally {
    # Cleanup indien nodig
}


