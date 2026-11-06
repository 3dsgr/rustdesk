#!/usr/bin/env bash
# Download/upload assets of a (draft) release by numeric release id.
# `gh release` resolves releases by tag, which does not work for drafts, so we
# use the REST API directly.
#
#   release-asset.sh download <release_id> <asset_name> <dest_file>
#   release-asset.sh upload   <release_id> <file>
#
# Needs GH_TOKEN (contents: write) and GITHUB_REPOSITORY.
set -euo pipefail

api="${GITHUB_API_URL:-https://api.github.com}/repos/${GITHUB_REPOSITORY}"
uploads="https://uploads.github.com/repos/${GITHUB_REPOSITORY}"
auth=(-H "Authorization: Bearer ${GH_TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28")

case "${1:-}" in
  download)
    release_id="$2" name="$3" dest="$4"
    asset_id=$(curl -fsSL "${auth[@]}" -H "Accept: application/vnd.github+json" \
      "${api}/releases/${release_id}/assets?per_page=100" |
      jq -r --arg n "$name" '.[] | select(.name == $n) | .id' | head -n1)
    if [ -z "$asset_id" ]; then
      echo "asset '$name' not found in release $release_id" >&2
      exit 1
    fi
    curl -fsSL "${auth[@]}" -H "Accept: application/octet-stream" \
      "${api}/releases/assets/${asset_id}" -o "$dest"
    ;;
  upload)
    release_id="$2" file="$3"
    name=$(basename "$file")
    curl -fsSL -o /dev/null "${auth[@]}" -X POST \
      -H "Content-Type: application/octet-stream" \
      --data-binary @"$file" \
      "${uploads}/releases/${release_id}/assets?name=${name}"
    echo "uploaded $name"
    ;;
  *)
    echo "usage: $0 download <release_id> <asset_name> <dest> | upload <release_id> <file>" >&2
    exit 2
    ;;
esac
