# Gyors üzembe helyezés

Ez az útmutató a HP Driver Compliance Framework (HP-DCF) minimális Pilot üzembe helyezését mutatja be az ütemezett végrehajtási útvonal használatával.

## Előfeltételek

A HP-DCF telepítése előtt:

- a telepítést rendszergazdai jogosultsággal kell futtatni;
- a célgépen a Windows Package Managernek (`winget`) telepítve és működőképes állapotban kell lennie;
- a gépnek el kell érnie a HP CMSL és HPIA működéséhez szükséges HP szolgáltatásokat.

A HP-DCF a framework telepítése és javítása során Wingetet használ a HP CMSL telepítéséhez vagy frissítéséhez. Ha a szükséges Winget csomagműveletek nem érhetők el, a framework telepítése nem tud sikeresen befejeződni.

## 1. A framework telepítése

A framework PSADT csomag könyvtárából futtasd:

```powershell
.\Invoke-AppDeployToolkit.exe -DeploymentType Install -DeployMode Interactive
```

A framework csomag telepíti/frissíti a HP CMSL-t és a HPIA-t, létrehozza a `C:\HPIA` runtime-ot, kimásolja az Automation és DriverDeployment fájlokat, és regisztrálja a framework Scheduled Taskot.

A telepítés önmagában nem engedélyezi az ütemezett kiértékelést vagy telepítést.

## 2. Minimális Pilot konfiguráció engedélyezése

Emelt jogosultságú PowerShellből futtasd:

```powershell
New-Item `
    -Path "HKLM:\SOFTWARE\HPDriverComplianceFramework" `
    -Force | Out-Null

New-ItemProperty `
    -Path "HKLM:\SOFTWARE\HPDriverComplianceFramework" `
    -Name "Enabled" `
    -PropertyType DWord `
    -Value 1 `
    -Force | Out-Null

New-Item `
    -Path "HKLM:\SOFTWARE\HPDriverComplianceFramework\DriverDeployer" `
    -Force | Out-Null

New-ItemProperty `
    -Path "HKLM:\SOFTWARE\HPDriverComplianceFramework\DriverDeployer" `
    -Name "Enabled" `
    -PropertyType DWord `
    -Value 1 `
    -Force | Out-Null

New-ItemProperty `
    -Path "HKLM:\SOFTWARE\HPDriverComplianceFramework\DriverDeployer" `
    -Name "Ring" `
    -PropertyType String `
    -Value "Pilot" `
    -Force | Out-Null
```

Ez engedélyezi a frameworköt és a DriverDeployert, valamint a Pilot rollout ringet választja. A többi beállítás továbbra is a beépített alapértékét használja.

## 3. A Pilot folyamat indítása

Jelentkezz ki, majd jelentkezz be újra.

A framework Scheduled Task felhasználói bejelentkezéskor, 3 perces késleltetéssel indul. A műveletek egymás után futnak:

```text
DriverEvaluator
      |
      v
Evaluation snapshot
      |
      v
DriverDeployer
      |
      v
Pilot telepítési jogosultság
      |
      v
DriverDeployment PSADT
```

A Pilot konfiguráció a beépített evaluation policy szerint lehetővé teszi a kimaradt kiértékelési előfordulások pótlását. A Pilot ringhez nem tartozik Broad telepítési késleltetés, ezért egy érvényes, frissen létrehozott evaluation snapshot azonnal telepítésre jogosult.

## 4. A kiértékelés ellenőrzése telepítés előtt

Normal Pilot deployment csak akkor indul, ha a DriverDeployer érvényes, teljes evaluation snapshotot tud kiválasztani. A teljes sikeres snapshot az egymáshoz tartozó:

```text
Evaluation-....manifest.json
Evaluation-....splist.txt
Evaluation-....success
```

fájlokból áll.

Ellenőrizd a snapshot könyvtárat:

```text
C:\HPIA\IAReport\Snapshots
```

A `.splist.txt` fájl a DriverEvaluator által rögzített SoftPaq ID-ket tartalmazza. Ha nincs érvényes teljes snapshot/SPList, a DriverDeployer nem indít Normal deploymentet.

A kiértékelés és a deployment-döntés a logokban is ellenőrizhető:

```text
C:\HPIA\IAReport\DriverEvaluator-<ComputerName>.log
C:\HPIA\IAReport\DriverDeployer-<ComputerName>.log
```

A DriverEvaluator naplózza a HPIA életciklus-ellenőrzést és a kiértékeléshez használt HPIA fájlverziót. A DriverDeployer naplózza a snapshot kiválasztását, a jogosultságot és azt az okot is, ha nem indul deployment.

## 5. Várható működés

Egy sikeres első Pilot ciklusban:

1. A DriverEvaluator szükség szerint ellenőrzi/frissíti a HPIA-t.
2. A HPIA Analyze/List műveletet végez.
3. A DriverEvaluator érvényes snapshotot és rögzített SPListet hoz létre.
4. A DriverDeployer kiválasztja ezt a snapshotot.
5. A Pilot ring miatt a snapshot azonnal telepítésre jogosult.
6. Elindul a DriverDeployment PSADT interaktív/elhalasztható telepítési folyamata.

Normal és `-ForceRun` deployment előtt nincs új HPIA-frissítés; a rögzített evaluation eredmény kerül telepítésre.

Az összes policy-értékhez és ütemezési lehetőséghez lásd a [Konfigurációs referenciát](configuration.md). A csomag életciklusához és a Scheduled Task részleteihez lásd a [Telepítés](deployment.md) dokumentumot.
