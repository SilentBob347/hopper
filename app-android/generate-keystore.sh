#!/usr/bin/env bash
set -euo pipefail

# Hopper release signing — same layout as android-tv-browser.
# Keystore lives outside the repo; credentials in keystore.properties (gitignored).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYSTORE="${KEYSTORE:-$HOME/googlePlayKeys.jks}"
KEYSTORE_PROPS="$ROOT_DIR/keystore.properties"
ALIAS="${ALIAS:-hopper-upload}"

die() {
    echo "error: $*" >&2
    exit 1
}

find_java() {
    local candidate
    for candidate in \
        "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" \
        "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" \
        "${JAVA_HOME:-}/bin/keytool"; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    command -v keytool
}

KEYTOOL="$(find_java)"

if [[ -f "$KEYSTORE" ]] && "$KEYTOOL" -list -keystore "$KEYSTORE" -alias "$ALIAS" &>/dev/null; then
    die "alias '$ALIAS' already exists in $KEYSTORE"
fi

if [[ -f "$KEYSTORE_PROPS" ]]; then
    store_password="$(grep '^storePassword=' "$KEYSTORE_PROPS" | cut -d= -f2-)"
    key_password="$(grep '^keyPassword=' "$KEYSTORE_PROPS" | cut -d= -f2-)"
else
    store_password="$(openssl rand -base64 24 | tr -d '/+=' | head -c 20)"
    key_password="$store_password"
fi

if [[ -z "$store_password" || -z "$key_password" ]]; then
    die "could not determine passwords; set storePassword/keyPassword in $KEYSTORE_PROPS or remove the file to auto-generate"
fi

echo "Keystore: $KEYSTORE"
echo "Alias:    $ALIAS"
echo

if [[ ! -f "$KEYSTORE" ]]; then
    echo "Creating new keystore..."
    "$KEYTOOL" -genkeypair -v \
        -keystore "$KEYSTORE" \
        -alias "$ALIAS" \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -storepass "$store_password" \
        -keypass "$key_password" \
        -dname "CN=Hopper, OU=Mobile, O=AENGIX SL, L=Barcelona, ST=Barcelona, C=ES"
else
    echo "Adding key to existing keystore..."
    "$KEYTOOL" -genkeypair -v \
        -keystore "$KEYSTORE" \
        -alias "$ALIAS" \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -storepass "$store_password" \
        -keypass "$key_password" \
        -dname "CN=Hopper, OU=Mobile, O=AENGIX SL, L=Barcelona, ST=Barcelona, C=ES"
fi

if [[ ! -f "$KEYSTORE_PROPS" ]]; then
    cat > "$KEYSTORE_PROPS" <<EOF
storePassword=$store_password
keyPassword=$key_password
keyAlias=$ALIAS
EOF
    echo
    echo "Wrote $KEYSTORE_PROPS"
else
    echo
    echo "Keystore updated. $KEYSTORE_PROPS already exists — ensure keyAlias=$ALIAS"
fi

echo
echo "Done. Fingerprint:"
"$KEYTOOL" -list -v -keystore "$KEYSTORE" -alias "$ALIAS" -storepass "$store_password" 2>/dev/null | grep -E 'Alias name:|SHA256:|Valid from'
