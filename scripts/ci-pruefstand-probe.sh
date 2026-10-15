#!/usr/bin/env bash
# Probelauf des Prüfstands mit erzeugten Beispielbildern. Nur für den GitHub-Build.
set -uo pipefail
cd "$(dirname "$0")/.."

DIR="$(mktemp -d)"
P() { swift run -c release --package-path Packages/Pruefstand kirei-pruefstand "$@" 2>&1 | grep -v -E '^\[|Building|Build of product|Write |Compiling|Linking|FBBA'; }

stamp() { echo "== $1 ($(date -u +%H:%M:%S))"; }
stamp beispiel; P beispiel "$DIR" || exit 1
stamp messen; P messen "$DIR/mediathek" || exit 1
stamp vorschlaege; P vorschlaege "$DIR/mediathek" || exit 1
if [ -f "$DIR/mediathek/kirei-vorschlaege.csv" ]; then
  stamp CSV; head -n 6 "$DIR/mediathek/kirei-vorschlaege.csv"
  # Alle Vorschläge als richtig markieren, um auswerten zu prüfen.
  sed '2,$ s/;$/;richtig/' "$DIR/mediathek/kirei-vorschlaege.csv" > "$DIR/urteile.csv"
  stamp auswerten; P auswerten "$DIR/urteile.csv"
  test -s "$DIR/mediathek/kirei-vorschlaege.html" && echo "HTML: $(wc -c < "$DIR/mediathek/kirei-vorschlaege.html") Byte"
fi
stamp kalibrieren; P kalibrieren "$DIR/kalibrierung"
exit 0
