#!/bin/zsh
# setup.sh — Instalare si configurare DUKIntegrator (ANAF) pe macOS
# Licenta: MIT. Acest script NU redistribuie software ANAF/Oracle/Thales —
# descarca kitul oficial direct de la ANAF si aplica doar corectii de configurare.

set -u

# ---------------------------------------------------------------------------
# Configurare
# ---------------------------------------------------------------------------
ANAF_KIT_URL="https://static.anaf.ro/static/DUKIntegrator/dist_javaInclus20200203.zip"
INSTALL_DIR="${1:-$HOME/DUKIntegrator}"
SAFENET_DYLIB="/usr/local/lib/libeTPkcs11.dylib"
SAFENET_INFO_URL="https://www.certsign.ro/en/support/safenet-installing-the-device-on-macos/"

err()  { print -P "%F{red}EROARE:%f $1" >&2; }
info() { print -P "%F{cyan}==>%f $1"; }
ok()   { print -P "%F{green}✓%f $1"; }

# ---------------------------------------------------------------------------
# 1. Verificari preliminare
# ---------------------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  err "Homebrew nu este instalat. Instalati-l de la https://brew.sh apoi rulati din nou."
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Java 8 (obligatoriu pentru semnarea cu token — versiunile noi de Java
#    au eliminat API-ul intern PKCS11 folosit de DUKIntegrator)
# ---------------------------------------------------------------------------
if /usr/libexec/java_home -v 1.8 >/dev/null 2>&1; then
  ok "Java 8 este deja instalat: $(/usr/libexec/java_home -v 1.8)"
else
  info "Instalez Java 8 (Azul Zulu, nativ Apple Silicon). Vi se poate cere parola de administrator."
  if ! brew install --cask zulu@8; then
    err "Instalarea Java 8 a esuat. Rulati manual: brew install --cask zulu@8"
    exit 1
  fi
  ok "Java 8 instalat."
fi
JAVA8_HOME="$(/usr/libexec/java_home -v 1.8)"

# ---------------------------------------------------------------------------
# 3. Descarcare kit oficial ANAF
# ---------------------------------------------------------------------------
if [[ -d "$INSTALL_DIR/dist" ]]; then
  ok "Kitul exista deja in $INSTALL_DIR — sar peste descarcare."
else
  info "Descarc kitul oficial DUKIntegrator de la ANAF..."
  mkdir -p "$INSTALL_DIR"
  TMP_ZIP="$(mktemp -d)/duk_kit.zip"
  if ! curl -fSL -o "$TMP_ZIP" "$ANAF_KIT_URL"; then
    err "Descarcarea a esuat. Verificati conexiunea sau descarcati manual de la:"
    err "  https://static.anaf.ro/static/DUKIntegrator/DUKIntegrator.htm"
    exit 1
  fi
  info "Dezarhivez..."
  if ! unzip -q "$TMP_ZIP" -d "$INSTALL_DIR"; then
    err "Dezarhivarea a esuat."
    exit 1
  fi
  rm -f "$TMP_ZIP"
  # kitul poate dezarhiva direct "dist/" sau un folder parinte care contine dist/
  if [[ ! -d "$INSTALL_DIR/dist" ]]; then
    FOUND_DIST="$(find "$INSTALL_DIR" -maxdepth 3 -type d -name dist | head -1)"
    if [[ -n "$FOUND_DIST" ]]; then
      INSTALL_DIR="$(dirname "$FOUND_DIST")"
    else
      err "Structura arhivei este neasteptata — folderul 'dist' nu a fost gasit in $INSTALL_DIR."
      exit 1
    fi
  fi
  ok "Kit instalat in $INSTALL_DIR"
fi
DIST_DIR="$INSTALL_DIR/dist"
CONFIG="$DIST_DIR/config/config.properties"
SAFENET_CFG="$DIST_DIR/config/safeNet.cfg"

# ---------------------------------------------------------------------------
# 4. Corectie 1: offLine=Y
#    Fara asta, aplicatia incearca auto-update printr-o cale Windows
#    (jre8\bin\java.exe), esueaza silentios si se inchide imediat pe macOS.
# ---------------------------------------------------------------------------
if [[ ! -f "$CONFIG" ]]; then
  err "Nu gasesc $CONFIG — kitul pare incomplet."
  exit 1
fi
if grep -q '^offLine=Y' "$CONFIG"; then
  ok "offLine=Y este deja setat."
else
  cp "$CONFIG" "$CONFIG.bak"
  printf '\noffLine=Y\n' >> "$CONFIG"
  ok "Am setat offLine=Y in config.properties (backup: config.properties.bak)."
fi

# ---------------------------------------------------------------------------
# 5. Corectie 2: driverul PKCS11 pentru tokenul SafeNet (daca este instalat)
# ---------------------------------------------------------------------------
if [[ -f "$SAFENET_DYLIB" ]]; then
  if [[ -f "$SAFENET_CFG" ]] && ! grep -q "$SAFENET_DYLIB" "$SAFENET_CFG"; then
    cp "$SAFENET_CFG" "$SAFENET_CFG.bak"
    sed -i '' "s|^library=.*|library=$SAFENET_DYLIB|" "$SAFENET_CFG"
    ok "safeNet.cfg configurat cu driverul macOS ($SAFENET_DYLIB)."
  else
    ok "safeNet.cfg este deja configurat."
  fi
  if grep -q '^defSmartCard=' "$CONFIG" && ! grep -q '^defSmartCard=safeNet' "$CONFIG"; then
    sed -i '' 's|^defSmartCard=.*|defSmartCard=safeNet|' "$CONFIG"
    ok "defSmartCard setat pe safeNet."
  fi
else
  info "SafeNet Authentication Client NU este instalat — semnarea cu token USB nu va functiona inca."
  info "Instalati-l de la certSIGN (gratuit): $SAFENET_INFO_URL"
  info "Dupa instalare + restart, rulati din nou acest script."
fi

# ---------------------------------------------------------------------------
# 6. Lansator cu dublu-click
# ---------------------------------------------------------------------------
LAUNCHER="$INSTALL_DIR/DUKIntegrator.command"
cat > "$LAUNCHER" <<LAUNCH
#!/bin/zsh
JAVA8_HOME="\$(/usr/libexec/java_home -v 1.8 2>/dev/null)"
if [[ -z "\$JAVA8_HOME" ]]; then
  osascript -e 'display alert "Java 8 lipseste" message "Instalati Java 8: brew install --cask zulu@8"'
  exit 1
fi
cd "$DIST_DIR"
exec "\$JAVA8_HOME/bin/java" -Xms250m -Xmx2g -jar DUKIntegrator.jar
LAUNCH
chmod +x "$LAUNCHER"
ok "Lansator creat: $LAUNCHER"

print
ok "Gata! Porniti aplicatia cu dublu-click pe DUKIntegrator.command"
info "(la prima deschidere: click dreapta -> Open, pentru avertismentul Gatekeeper)"
