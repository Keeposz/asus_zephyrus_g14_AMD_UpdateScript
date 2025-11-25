# asus_zephyrus_g14_AMD_UpdateScript
All-in-one system update script for ASUS Zephyrus G14 (AMD/NVIDIA). Automates Windows Updates, Winget packages, and driver checks with a single click.

# Windows Update Script - ASUS Zephyrus G14 (AMD/NVIDIA)

Dit PowerShell script automatiseert het updateproces voor een ASUS Zephyrus G14 laptop (of vergelijkbare systemen met AMD CPU & NVIDIA GPU). Het controleert en installeert updates voor Windows, applicaties en drivers.

## Functies

*   **Windows Updates:** Controleert en installeert updates via de `PSWindowsUpdate` module.
*   **Winget Updates:** Updatet alle geïnstalleerde applicaties via Windows Package Manager (Winget).
*   **NVIDIA Drivers:** Controleert of de NVIDIA drivers up-to-date zijn (via GeForce Experience of NVIDIA App).
*   **AMD Drivers:** Controleert op AMD Chipset/Processor updates.
*   **ASUS Updates:** Controleert of de MyASUS app aanwezig is voor firmware/BIOS updates.
*   **Logging:** Houdt een gedetailleerd logboek bij van alle acties in `Desktop\SystemUpdateLogs`.
*   **Admin Check:** Controleert automatisch op Administrator rechten.

## Vereisten

*   Windows 10 of Windows 11
*   PowerShell 5.1 of hoger
*   Administrator rechten (Run as Administrator)
*   Internetverbinding

## Gebruik

1.  Download het script `Update-SystemComplete.ps1`.
2.  Klik met de rechtermuisknop op het bestand en kies **Run with PowerShell** (of open PowerShell als Administrator en navigeer naar de map).
3.  Volg de instructies op het scherm.

### Parameters

Je kunt het script ook draaien met parameters voor automatisering:

*   `-AutoInstall`: Installeert alle updates zonder om bevestiging te vragen.
*   `-SkipReboot`: Voorkomt dat de computer automatisch herstart na updates.

**Voorbeeld:**
```powershell
.\Update-SystemComplete.ps1 -AutoInstall -SkipReboot
```

## Installatie Opmerkingen

*   De eerste keer dat je het script draait, zal het vragen om de `PSWindowsUpdate` module en `NuGet` provider te installeren. Dit is nodig voor de Windows Updates.
*   Zorg dat je bent ingelogd bij de Microsoft Store en dat de "App Installer" (Winget) up-to-date is.

## Auteur

Gemaakt voor ASUS Zephyrus G14 gebruikers.
