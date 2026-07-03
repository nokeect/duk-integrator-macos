# DUKIntegrator (ANAF) pe macOS

Realizat de [AXIOM ADVISORY S.R.L.](https://axiomadvisory.ro).

Ghid + script de instalare pentru rularea **DUKIntegrator** — aplicația ANAF de validare,
generare PDF și semnare a declarațiilor fiscale (SAF-T / D406, D112 etc.) — **nativ pe macOS**,
inclusiv **semnarea cu token USB** (testat cu SafeNet eToken / certificat AlfaSign, pe Apple Silicon).

> **Disclaimer:** kitul DUKIntegrator este certificat oficial de ANAF doar pentru Windows.
> Configurația de față funcționează, dar o folosiți pe propria răspundere. Validarea finală a
> declarației o face oricum serverul ANAF la depunerea prin SPV.

## Instalare rapidă

```bash
git clone https://github.com/nokeect/duk-integrator-macos.git
cd duk-integrator-macos
./setup.sh
```

Scriptul:
1. instalează **Java 8** (Azul Zulu, nativ Apple Silicon) prin Homebrew — dacă lipsește
2. descarcă **kitul oficial DUKIntegrator direct de la ANAF**
3. aplică cele două corecții de configurare (detalii mai jos)
4. creează un lansator `DUKIntegrator.command` pe care îl deschizi cu dublu-click

Pentru semnarea cu token USB îți trebuie în plus **SafeNet Authentication Client** pentru macOS —
gratuit, de la certSIGN: [instrucțiuni și download](https://www.certsign.ro/en/support/safenet-installing-the-device-on-macos/)
(instalezi, dai restart, apoi rulezi `./setup.sh` din nou).

## Ce probleme rezolvă (dacă vrei să faci pașii manual)

### 1. Aplicația se închide imediat după pornire, fără nicio eroare

**Cauza:** la pornire, aplicația încearcă să-și verifice actualizările lansând `Download.jar`
printr-o cale Windows hardcodată în `config/config.properties` (`javaStartPrefix=..\jre8\bin\java.exe`).
Pe macOS acel exec eșuează silențios și aplicația iese înainte să deschidă fereastra.

**Fix:** adaugă în `dist/config/config.properties` linia:

```properties
offLine=Y
```

(Consecință: nu mai primești actualizări automate — vezi secțiunea „Actualizarea validatoarelor".)

### 2. `eroare acces driver: C:\WINDOWS\system32\dkck201.dll` la semnare

**Cauza:** fișierele `dist/config/*.cfg` indică drivere PKCS11 de Windows (`.dll`).

**Fix:** în `dist/config/safeNet.cfg` (pentru eToken SafeNet), înlocuiește linia `library=` cu:

```properties
library=/usr/local/lib/libeTPkcs11.dylib
```

Acest `.dylib` există după instalarea SafeNet Authentication Client. Pentru alte tokenuri,
calea diferă (ex. Gemalto IDPrime: `/usr/local/lib/libIDPrimePKCS11.dylib`); pune calea
corespunzătoare în fișierul `.cfg` al tokenului tău.

### 3. `IllegalAccessException: ... module jdk.crypto.cryptoki does not export sun.security.pkcs11.wrapper`

**Cauza:** DUKIntegrator folosește API-uri interne Java (inclusiv un constructor
`SunPKCS11(InputStream)` eliminat din JDK 9+). Cu Java 9…26 semnarea nu poate funcționa.

**Fix:** rulează aplicația cu **Java 8**. Recomandat Azul Zulu 8 — are build nativ Apple Silicon:

```bash
brew install --cask zulu@8
cd <folderul-kitului>/dist
"$(/usr/libexec/java_home -v 1.8)/bin/java" -Xms250m -Xmx2g -jar DUKIntegrator.jar
```

## Actualizarea validatoarelor de declarații

Cu `offLine=Y`, aplicația nu-și mai descarcă singură validatoarele noi. Când ANAF publică o
versiune nouă pentru o declarație (ex. D406), descarcă „Soft J" de pe
[pagina declarației de pe anaf.ro](https://static.anaf.ro/static/10/Anaf/Declaratii_R/406.html)
și copiază jar-urile din arhivă în `dist/lib/` (suprascriind versiunile vechi).

## De ce scriptul doar descarcă lucrurile, nu le include

Kitul DUKIntegrator e software ANAF, fără licență de redistribuire. La fel Java (licența Oracle
pentru JRE) și driverul SafeNet/Thales pentru token. Din cauza asta repo-ul nu are în el niciun
`.jar`, `.dmg` sau `.pkg` — scriptul le ia mereu de la sursa oficială, iar pentru driverul de
token te trimite direct la pagina certSIGN.

## Compatibilitate testată

| Componentă | Versiune |
|---|---|
| macOS | 26 (Tahoe), Apple Silicon |
| DUKIntegrator | 1.4.18.3.3 |
| Java | Azul Zulu 8 (arm64) |
| Token | SafeNet eToken „Token JC", certificat AlfaSign |
| SafeNet Authentication Client | 10.8 |

## Licență

Scriptul și documentația: [MIT](LICENSE), © AXIOM ADVISORY S.R.L. Software-ul ANAF, Java și
driverele de token aparțin deținătorilor lor și au licențe proprii.
