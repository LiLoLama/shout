#!/usr/bin/env bash
# Release-Notes einer Version aus CHANGELOG.md — für
#   gh release create v1.13.0 … --notes-file <(Support/release-notes.sh 1.13.0)
#   Support/release-notes.sh --check 1.13.0   → Exit 0 nur mit gültigem Abschnitt
# CHANGELOG=<pfad> liest eine andere Datei (Tests).
set -euo pipefail
cd "$(dirname "$0")/.."

check=0
if [[ "${1:-}" == "--check" ]]; then check=1; shift; fi
version="${1:?Version fehlt, z. B. 1.13.0}"
datei="${CHANGELOG:-CHANGELOG.md}"
[[ -f "$datei" ]] || { echo "$datei fehlt" >&2; exit 1; }

# Der Abschnitt ohne seine Kopfzeile.
abschnitt=$(awk -v v="$version" '/^## /{ drin = ($2 == v); next } drin { print }' "$datei")
[[ -n "$abschnitt" ]] || { echo "Kein Abschnitt für $version in $datei" >&2; exit 1; }

block() {
  printf '%s\n' "$abschnitt" | awk -v name="$1" '
    /^### /{ drin = ($0 == "### " name); next }
    drin { z[++n] = $0 }
    END {
      a = 1; while (a <= n && z[a] ~ /^[[:space:]]*$/) a++
      e = n; while (e >= a && z[e] ~ /^[[:space:]]*$/) e--
      for (i = a; i <= e; i++) print z[i]
    }'
}

deutsch=$(block "Deutsch")
englisch=$(block "English")
printf '%s\n' "$abschnitt" | grep -Eq '^zeigen:[[:space:]]*(ja|nein)[[:space:]]*$' \
  || { echo "$version: Zeile „zeigen: ja|nein“ fehlt" >&2; exit 1; }
[[ -n "$deutsch" ]] || { echo "$version: Block „### Deutsch“ fehlt oder ist leer" >&2; exit 1; }
[[ -n "$englisch" ]] || { echo "$version: Block „### English“ fehlt oder ist leer" >&2; exit 1; }

(( check )) && exit 0
printf '%s\n\n---\n\n%s\n' "$deutsch" "$englisch"
