#!/usr/bin/env bash
#
# Prépare le dossier android/ de Ding.
#
# Le projet Gradle n'est pas versionné : il est régénéré par `flutter create`
# (ce qui évite de committer ~40 fichiers de plomberie Android), puis on
# applique les fichiers de référence versionnés dans tool/android/.
#
# Utilisé par la CI et utilisable en local (Linux, macOS, WSL) :
#     bash tool/setup_android.sh
#
# Idempotent : on peut le relancer autant de fois que nécessaire.

set -euo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$racine"

if [ ! -d android ]; then
  echo "→ Génération du projet Android (flutter create)…"
  flutter create \
    --org com.meganae \
    --project-name ding \
    --platforms=android \
    . >/dev/null
fi

# Le scaffold crée un test de démonstration qui référence une application
# inexistante : il ferait échouer `flutter test`.
rm -f test/widget_test.dart

echo "→ Application du manifeste de référence…"
mkdir -p android/app/src/main/res/xml
cp tool/android/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
cp tool/android/network_security_config.xml \
  android/app/src/main/res/xml/network_security_config.xml

# minSdk 23 : requis par flutter_secure_storage (EncryptedSharedPreferences).
echo "→ minSdk = 23"
for f in android/app/build.gradle android/app/build.gradle.kts; do
  [ -f "$f" ] || continue
  # -i.bak pour rester compatible GNU sed et BSD sed (macOS).
  sed -i.bak -E \
    's/minSdk(Version)?[[:space:]]*=?[[:space:]]*flutter\.minSdkVersion/minSdk = 23/' \
    "$f"
  rm -f "$f.bak"
done

if ! grep -Rqs "minSdk = 23" android/app/build.gradle android/app/build.gradle.kts; then
  echo "⚠ Impossible de fixer minSdk automatiquement :" >&2
  echo "  ouvre android/app/build.gradle(.kts) et mets minSdk = 23." >&2
fi

# Garde-fou : si les permissions disparaissent du manifeste, l'APK serait
# incapable de se localiser et l'app semblerait cassée.
for permission in ACCESS_FINE_LOCATION INTERNET POST_NOTIFICATIONS; do
  if ! grep -q "$permission" android/app/src/main/AndroidManifest.xml; then
    echo "✗ Permission $permission absente du manifeste." >&2
    exit 1
  fi
done

echo "✓ android/ prêt (applicationId com.meganae.ding, label Ding)"
