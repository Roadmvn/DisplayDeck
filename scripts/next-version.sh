#!/bin/bash
set -euo pipefail

# Déduit la prochaine version des commits depuis le dernier tag v*, selon les préfixes
# Conventional Commits : "!" ou "BREAKING CHANGE" -> major, feat -> minor, le reste -> patch.
# stdout = sorties pour GITHUB_OUTPUT (version=, tag=), vide s'il n'y a rien à publier.

cd "$(dirname "$0")/.."

last_tag="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
range="${last_tag:+$last_tag..}HEAD"

if [[ -z "$(git rev-list "$range")" ]]; then
    echo "rien à publier : aucun commit depuis $last_tag" >&2
    exit 0
fi

IFS=. read -r major minor patch <<< "${last_tag#v}"
: "${major:=0}" "${minor:=0}" "${patch:=0}"

if git log --format='%s%n%b' "$range" | grep -Eq '^[a-z]+(\([^)]*\))?!:|^BREAKING CHANGE:'; then
    major=$((major + 1)); minor=0; patch=0
elif git log --format='%s' "$range" | grep -Eq '^feat(\([^)]*\))?:'; then
    minor=$((minor + 1)); patch=0
else
    patch=$((patch + 1))
fi

next="$major.$minor.$patch"
echo "${last_tag:-aucun tag} -> v$next" >&2
echo "version=$next"
echo "tag=v$next"
