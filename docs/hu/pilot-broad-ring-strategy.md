# Pilot/Broad ring stratégia

Ez a dokumentum a Pilot és Broad ringekhez való eszközhozzárendelés javasolt stratégiáját, valamint azokat az üzemeltetési feltételezéseket írja le, amelyek mellett a beépített ütemezési alapértékek valóban hatékony védelmet nyújtanak. Magát a ring-hozzárendelést a HP-DCF nem valósítja meg — ez egy policy-kiosztási döntés (Intune/GPO csoport-targetálás), amely meghatározza, mely eszközök kapják a `Ring = Pilot`, illetve a `Ring = Broad` értéket. Ez a dokumentum azért létezik, mert ez a döntés érdemben befolyásolja, hogy a framework alapértelmezett időzítése ténylegesen mennyi védelmet nyújt.

## Tervezési szándék

A Pilot/Broad felosztás célja megakadályozni, hogy egy hibás SoftPaq úgy jusson el a Broad ringbe, hogy azt előtte a Pilot ring ne próbálta volna ki. Ez kizárólag **időbeli elválasztással** valósul meg, nem valamilyen automatikus visszacsatolással:

- A Pilot a `WeeksOfMonth = 1,3` beállítás szerint értékel ki, és sikeres snapshot esetén azonnal telepít.
- A Broad a `WeeksOfMonth = 3` szerint értékel ki, és a snapshot időbélyegétől számított `BroadDelayDays` (alapértelmezetten 21) nap múlva válik telepítésre jogosulttá.

Mivel mindkét ring ugyanazon a harmadik szerdai előforduláson értékel ki, ugyanazon a napon fagyasztják be ugyanazt a SoftPaq-ajánláskészletet. A Pilot ezt a snapshotot azonnal telepíti, míg a Broad ugyanerre a befagyasztott snapshotra csak a `BroadDelayDays` (alapértelmezetten 21 nap) letelte után válik jogosulttá. Emellett a Pilot ekkorra már többhetes tapasztalattal is rendelkezhet azokkal az ajánlásokkal kapcsolatban, amelyek először az 1. heti kiértékelés során jelentek meg.

## Javasolt Pilot-összetétel

Önmagában egy egyszerű véletlen minta nem elegendő. A javasolt Pilot-populáció két, eltérő célú kohorszot kombinál:

### 1. Support/Help Desk gépek

A support, help desk és technikai személyzet gépei a véletlen szelekciótól függetlenül, explicit módon részei a Pilot ringnek. Indoklás:

- Ez a felhasználói kör tudja leggyorsabban **észrevenni és jelenteni** egy driver-/firmware-regressziót — hamarabb felismerik egy HPIA-vel összefüggő tünetet, mint egy átlagos végfelhasználó, és már eleve van közvetlen eszkalációs útjuk.
- Ez a kohorsz a **korai észlelési sebességet** optimalizálja, nem a reprezentativitást.

### 2. Randomizált, általános populációs minta (~10%)

A standard flotta egy random ~10%-a — egy stabil eszközattribútum, például a gyári szám utolsó karaktere alapján kiválasztva — szintén a Pilot ringbe kerül. Indoklás:

- A support/Help Desk hardver gyakran nem standard (más modell, image vagy konfiguráció, mint az általános flotta). Egy olyan regresszió, ami csak standard végfelhasználói hardveren jelentkezik, egy kizárólag support-gépekből álló Pilot mellett észrevétlen maradhatna.
- Ez a kohorsz a **reprezentativitást** optimalizálja — a SoftPaq validálását valós, standard, "élő" éles konfigurációkon biztosítja, mielőtt a Broad terítés elindulna.

### A szelekciós módszer korlátai

- **Az eloszlás egyenletessége.** A gyári szám utolsó karaktere szerinti szelekció feltételezi, hogy ez a karakter nagyjából egyenletesen oszlik el. Ez nem garantált — a HP gyáriszám-kiosztása gyártási sáv vagy telephely szerint klaszterezhet. Mielőtt nagy flottán érdemben támaszkodnál erre a módszerre, érdemes leellenőrizni a célflotta tényleges utolsó karakter szerinti eloszlását; egy torz eloszlás bizonyos hardvergyártási sávokat felül- vagy alulreprezentálhat a teljes flottához képest.
- **Kohorsz-átfedés.** Előfordulhat, hogy egy support/Help Desk gép egyébként is a véletlenszerűen kiválasztott gyáriszám-szeletbe esne. Kisebb flottánál ez torzíthatja a tényleges Pilot-arányt; több ezres flottánál ez várhatóan elhanyagolható, de ez legyen tudatos feltételezés, ne véletlen — különösen, ha valaha auditálni kell a ring-lefedettséget.
- **A framework nem lát bele a kohorsz-összetételbe.** A `DriverDeployer` csak egy sima `Ring = Pilot|Broad` értéket olvas ki a registry-ből. Nem tudja, és nem is kell tudnia, miért került egy adott gép egy adott ringbe. Ez szándékos — a ring-hozzárendelés logikája teljes egészében a policy-kiosztás (Intune/GPO csoport-targetálás) szintjén él, nem a framework-ben. Ennek következménye, hogy a teljes szelekciós stratégia kizárólag a policy-konfigurációban és az intézményi tudásban létezik; a kódbázisban semmi nem dokumentálja, *miért* van egy eszköz egy adott csoportban.

## A monitoring-függőség (kritikus)

**Ez nem egy fail-safe mechanizmus.** A HP-DCF-ben nincs automatikus visszacsatolási út a Pilot telepítési eredményei és az `ExcludeSoftPaqs` között. A `BroadDelayDays` ablak csak *lehetőséget* teremt arra, hogy egy ember észlelje és kezelje a problémát — önmagában nem észlel és nem reagál semmire.

Konkrétan:

1. Egy Pilot-gépen nem sikerül egy SoftPaq telepítése (például a HPIA/PSADT `3020` exit kódot ad vissza — egy vagy több SoftPaq telepítése sikertelen).
2. A HP-DCF ezt önmagában sehol nem jelzi központilag, és nem blokkolja emiatt automatikusan a Broad ringet.
3. Valakinek észre kell vennie ezt (log-áttekintés, RMM-/monitoring-integráció vagy support-jegy útján), azonosítania kell az érintett SoftPaq ID-t, és manuálisan hozzá kell adnia a következőhöz:

   ```text
   HKLM\SOFTWARE\HPDriverComplianceFramework
     ExcludeSoftPaqs = <SoftPaq ID>
   ```

4. Ennek **azelőtt** meg kell történnie, hogy az érintett snapshot `BroadDelayDays` ablaka lejárna. Ha ez nem történik meg időben, a Broad ugyanazt a SoftPaqot fogja megkapni, amin a Pilot már elbukott.

### Üzemeltetési előfeltétel

A HP-DCF-től függetlenül kell léteznie egy monitoring-folyamatnak ahhoz, hogy ez a védelem valóban működjön. Ennek a folyamatnak minimálisan a következőket kell biztosítania:

- A `DriverDeployer-<ComputerName>.log` és a `DriverEvaluator-<ComputerName>.log` áttekintése a Pilot-gépeken, a nem sikeres kimenetek kiszűrésére.
- Kifejezett figyelés a `3020` (telepítési hiba) és `4099` (érvénytelen SoftPaq szám) HPIA/telepítési exit kódokra a Pilot-gépeken.
- Meghatározott felelős és reakcióidő, ami kényelmesen a konfigurált `BroadDelayDays` ablakon belülre esik (nem csak épphogy belefér — hagyj mozgásteret az észlelési késleltetésre, a jegykezelésre és a változáskezelési jóváhagyásra).

E folyamat nélkül a Pilot/Broad elválasztás még mindig nyújt *valamennyi* értéket (már önmagában az időbeli szétválasztás is csökkenti a hatáskört), de nem biztosítja azt a védelmet, amit a tervezési szándék eredetileg megcéloz — hogy egy ismert hibás SoftPaq ne jusson el a teljes flottához.

## A `BroadDelayDays` hangolása kockázattűrés szerint

A `BroadDelayDays` egy `REG_DWORD` a `0..365` tartományban, és környezetenként központilag felülírható:

```text
HKLM\SOFTWARE\HPDriverComplianceFramework\DriverDeployer
  BroadDelayDays = <0-365>
```

- **Az alapértelmezett (21 nap)** egy enterprise méretű flottát feltételez (több ezer eszköz), ahol elég Pilot-gép várhatóan bekapcsol és bejelentkezik három héten belül ahhoz, hogy értékelhető visszajelzés szülessen, párosulva egy support csapattal, amely az ablakon belül tud reagálni.
- **Hosszabb ablakok** (például 180 nap féléves Broad terítéshez) olyan környezeteknek valók, ahol a stabilitás elsőbbséget élvez a naprakészséggel szemben, vagy ahol a Pilot-populáció kisebb, illetve kevésbé folyamatosan online — ott több idő kell ahhoz, hogy megbízhatóság alakuljon ki egy snapshot körül, mielőtt széles körben kitelepítenék.
- **Rövidebb ablakok** az észlelési időt cserélik gyorsabb flottaszintű naprakészségre, és csak akkor érdemes csökkenteni őket, ha a fenti monitoring-folyamat gyors és megbízható.

Nincs olyan érték, amitől ez teljesen fail-safe lenne. Ha a teljes Pilot-populáció offline van a `BroadDelayDays` teljes időtartama alatt (például egy elhúzódó leállás vagy a mintába eső gépeket érintő ünnepi leállás miatt), a Broad ring akkor is megkaphatja a validálatlan snapshotot, amikor a saját késleltetése lejár. Reális flottaméret mellett (több ezer eszköz, a fent leírt vegyes kohorszokkal) ez reziduális üzemeltetési kockázatként kezelhető, nem pedig a framework hibájaként, feltéve hogy a telepítő szervezet ezt a kockázatot ismeri és tudatosan elfogadja.

## A feltételezések összefoglalása

| Feltételezés | Miért számít | Mit tegyünk, ha sérül |
|---|---|---|
| Legalább néhány Pilot-gép bekapcsol a kiértékelési/telepítési ablakon belül | Offline gépen nem történhet Pilot-telepítés | A Pilot tartalmazzon folyamatosan vagy gyakran használt eszközosztályokat is (ebben segítenek a support-gépek) |
| A gyáriszám-alapú véletlen szelekció nagyjából egyenletes | Ellenkező esetben a Pilot nem reprezentálja a standard flottát | A nagy flottán való érdemi támaszkodás előtt auditáld a tényleges utolsó karakter szerinti eloszlást |
| Egy emberi monitoring-folyamat áttekinti a Pilot-logokat a `BroadDelayDays` ablakon belül | A framework önmagában nem állítja meg a hibás SoftPaqot | Határozz meg explicit felelőst, log-áttekintési ütemezést és eszkalációs útvonalat |
| A ring-hozzárendelés (policy-/csoport-targetálás) hosszú távon is illeszkedik ehhez a stratégiához | A ring-tagság elsodródhat, ahogy a személyzet és az eszközök változnak | Időszakosan validáld újra az Intune/GPO csoporttagságot a tervezett kohorszokhoz képest |
