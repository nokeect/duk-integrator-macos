#!/bin/zsh
# setup.sh — Instalare si configurare DUKIntegrator (ANAF) pe macOS
# Licenta: MIT. Acest script NU redistribuie software ANAF/Oracle/Thales —
# foloseste un kit ANAF pe care il aveti deja (ex. kitul SAF-T / D406) sau
# descarca kitul generic direct de la ANAF, apoi aplica doar corectii de configurare.
#
# Utilizare:
#   ./setup.sh                          kit generic ANAF (doar D112), instalat in ~/DUKIntegrator
#   ./setup.sh <kit> [folder-instalare] kitul vostru (folder sau .zip), ex. kitul SAF-T pentru D406

set -u

# ---------------------------------------------------------------------------
# Configurare
# ---------------------------------------------------------------------------
ANAF_KIT_URL="https://static.anaf.ro/static/DUKIntegrator/dist_javaInclus20200203.zip"
ANAF_KIT_PAGE="https://static.anaf.ro/static/DUKIntegrator/DUKIntegrator.htm"
KIT_SOURCE="${1:-}"
DEFAULT_INSTALL_DIR="$HOME/DUKIntegrator"
DEFAULT_INSTALL_DIR_LOCAL_KIT="$HOME/DUKIntegrator_D406"
SAFENET_DYLIB="/usr/local/lib/libeTPkcs11.dylib"
SAFENET_INFO_URL="https://www.certsign.ro/en/support/safenet-installing-the-device-on-macos/"
DEFAULT_WORK_FOLDER="$HOME/Documents"
JAVA_HEAP_ARGS="-Xms250m -Xmx4g"
# runtime-urile Java pentru Windows si lansatoarele .bat nu au ce cauta pe macOS
COPY_EXCLUDES=(jre6 jre8 '*.bat')

if [[ -n "$KIT_SOURCE" ]]; then
  INSTALL_DIR="${2:-$DEFAULT_INSTALL_DIR_LOCAL_KIT}"
else
  INSTALL_DIR="$DEFAULT_INSTALL_DIR"
fi

err()  { printf '\033[31mEROARE:\033[0m %s\n' "$1" >&2; }
info() { printf '\033[36m==>\033[0m %s\n' "$1"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }

# seteaza cheie=valoare in config.properties (inlocuieste linia existenta sau o adauga)
set_property() {
  local key="$1" value="$2" file="$3"
  if grep -q "^${key}=" "$file"; then
    sed -i '' "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$file"
  fi
}

# gaseste folderul "dist" intr-un kit (poate fi chiar kitul, sau un subfolder)
find_dist_dir() {
  local root="$1"
  if [[ -f "$root/DUKIntegrator.jar" ]]; then
    print -r -- "$root"
  elif [[ -d "$root/dist" ]]; then
    print -r -- "$root/dist"
  else
    find "$root" -maxdepth 3 -type f -name DUKIntegrator.jar -not -path '*/__MACOSX/*' \
      | head -1 | xargs -I{} dirname "{}"
  fi
}

# ---------------------------------------------------------------------------
# 0. Shell corect (scriptul foloseste sintaxa zsh)
# ---------------------------------------------------------------------------
if [[ -z "${ZSH_VERSION:-}" ]]; then
  exec /bin/zsh "$0" "$@"
fi

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

# ---------------------------------------------------------------------------
# 3. Kitul DUKIntegrator: local (ex. SAF-T / D406) sau generic de la ANAF
# ---------------------------------------------------------------------------
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -n "$KIT_SOURCE" ]]; then
  if [[ ! -e "$KIT_SOURCE" ]]; then
    err "Nu gasesc kitul: $KIT_SOURCE"
    exit 1
  fi
  if [[ -f "$KIT_SOURCE" ]]; then
    info "Dezarhivez kitul $KIT_SOURCE..."
    if ! unzip -q "$KIT_SOURCE" -d "$TMP_DIR/kit"; then
      err "Dezarhivarea a esuat. Kitul trebuie sa fie un folder sau o arhiva .zip."
      exit 1
    fi
    SOURCE_DIST="$(find_dist_dir "$TMP_DIR/kit")"
  else
    SOURCE_DIST="$(find_dist_dir "${KIT_SOURCE:A}")"
  fi
  if [[ -z "$SOURCE_DIST" || ! -f "$SOURCE_DIST/DUKIntegrator.jar" ]]; then
    err "Nu gasesc DUKIntegrator.jar in kitul $KIT_SOURCE."
    exit 1
  fi

  DIST_DIR="$INSTALL_DIR/dist"
  if [[ -d "$DIST_DIR" ]]; then
    BACKUP_DIR="$INSTALL_DIR/dist.bak.$(date +%Y%m%d%H%M%S)"
    mv "$DIST_DIR" "$BACKUP_DIR"
    info "Instalarea anterioara a fost mutata in $BACKUP_DIR"
  fi
  mkdir -p "$DIST_DIR"
  info "Copiez kitul din $SOURCE_DIST in $DIST_DIR..."
  EXCLUDE_ARGS=()
  for pattern in "${COPY_EXCLUDES[@]}"; do
    EXCLUDE_ARGS+=(--exclude "$pattern")
  done
  if ! rsync -a "${EXCLUDE_ARGS[@]}" "$SOURCE_DIST/" "$DIST_DIR/"; then
    err "Copierea kitului a esuat."
    exit 1
  fi
  ok "Kit instalat in $INSTALL_DIR"
else
  if [[ -d "$INSTALL_DIR/dist" ]]; then
    ok "Kitul exista deja in $INSTALL_DIR — sar peste descarcare."
  else
    info "Descarc kitul generic DUKIntegrator de la ANAF (contine doar validatorul D112)..."
    mkdir -p "$INSTALL_DIR"
    TMP_ZIP="$TMP_DIR/duk_kit.zip"
    if ! curl -fSL -o "$TMP_ZIP" "$ANAF_KIT_URL"; then
      err "Descarcarea a esuat. Verificati conexiunea sau descarcati manual de la:"
      err "  $ANAF_KIT_PAGE"
      exit 1
    fi
    info "Dezarhivez..."
    if ! unzip -q "$TMP_ZIP" -d "$INSTALL_DIR"; then
      err "Dezarhivarea a esuat."
      exit 1
    fi
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
fi

CONFIG="$DIST_DIR/config/config.properties"
SAFENET_CFG="$DIST_DIR/config/safeNet.cfg"

xattr -dr com.apple.quarantine "$INSTALL_DIR" 2>/dev/null

# ---------------------------------------------------------------------------
# 4. Corectie 1: offLine=Y
#    Fara asta, aplicatia incearca auto-update printr-o cale Windows
#    (jre8\bin\java.exe), esueaza silentios si se inchide imediat pe macOS.
# ---------------------------------------------------------------------------
if [[ ! -f "$CONFIG" ]]; then
  err "Nu gasesc $CONFIG — kitul pare incomplet."
  exit 1
fi
[[ -f "$CONFIG.bak" ]] || cp "$CONFIG" "$CONFIG.bak"
if grep -q '^offLine=Y' "$CONFIG"; then
  ok "offLine=Y este deja setat."
else
  set_property offLine Y "$CONFIG"
  ok "Am setat offLine=Y in config.properties (backup: config.properties.bak)."
fi

# ---------------------------------------------------------------------------
# 5. Corectie 2: folderul implicit de lucru (kitul vine cu o cale Windows, ex. E:\tmp)
# ---------------------------------------------------------------------------
if grep -q '^defFolder=.*\\' "$CONFIG" || ! grep -q '^defFolder=' "$CONFIG"; then
  set_property defFolder "$DEFAULT_WORK_FOLDER" "$CONFIG"
  ok "defFolder setat pe $DEFAULT_WORK_FOLDER."
fi

# ---------------------------------------------------------------------------
# 6. Declaratiile disponibile in kit
# ---------------------------------------------------------------------------
VALIDATORS=("$DIST_DIR"/lib/*Validator.jar(N:t:r))
VALIDATORS=(${VALIDATORS:#Validator})
DECLARATIONS=(${VALIDATORS%Validator})
if (( ${#DECLARATIONS} == 0 )); then
  err "Nu am gasit niciun validator de declaratie in $DIST_DIR/lib."
  exit 1
fi
ok "Declaratii disponibile in kit: ${(j:, :)DECLARATIONS}"
if (( ! ${DECLARATIONS[(Ie)D406]} )); then
  info "ATENTIE: kitul NU contine validatorul D406 (SAF-T)."
  info "Pentru D406 rulati: ./setup.sh \"<calea catre kitul SAF-T>\""
fi

# ---------------------------------------------------------------------------
# 7. Corectie 3: driverul PKCS11 pentru tokenul SafeNet (daca este instalat)
# ---------------------------------------------------------------------------
if [[ -f "$SAFENET_DYLIB" ]]; then
  if [[ -f "$SAFENET_CFG" ]] && ! grep -q "$SAFENET_DYLIB" "$SAFENET_CFG"; then
    cp "$SAFENET_CFG" "$SAFENET_CFG.bak"
    sed -i '' "s|^library=.*|library=$SAFENET_DYLIB|" "$SAFENET_CFG"
    ok "safeNet.cfg configurat cu driverul macOS ($SAFENET_DYLIB)."
  else
    ok "safeNet.cfg este deja configurat."
  fi
  if ! grep -q '^defSmartCard=safeNet' "$CONFIG"; then
    set_property defSmartCard safeNet "$CONFIG"
    ok "defSmartCard setat pe safeNet."
  fi
else
  info "SafeNet Authentication Client NU este instalat — semnarea cu token USB nu va functiona inca."
  info "Instalati-l de la certSIGN (gratuit): $SAFENET_INFO_URL"
  info "Dupa instalare + restart, rulati din nou acest script."
fi

# ---------------------------------------------------------------------------
# 8. Lansator cu dublu-click
# ---------------------------------------------------------------------------
LAUNCHER="$INSTALL_DIR/DUKIntegrator.command"
cat > "$LAUNCHER" <<LAUNCH
#!/bin/zsh
JAVA8_HOME="\$(/usr/libexec/java_home -v 1.8 2>/dev/null)"
if [[ -z "\$JAVA8_HOME" ]]; then
  osascript -e 'display alert "Java 8 lipseste" message "Instalati Java 8: brew install --cask zulu@8"'
  exit 1
fi
cd "$DIST_DIR" || exit 1
exec "\$JAVA8_HOME/bin/java" $JAVA_HEAP_ARGS -jar DUKIntegrator.jar
LAUNCH
chmod +x "$LAUNCHER"
ok "Lansator creat: $LAUNCHER"

echo
ok "Gata! Porniti aplicatia cu dublu-click pe $LAUNCHER"
info "(la prima deschidere: click dreapta -> Open, pentru avertismentul Gatekeeper)"
