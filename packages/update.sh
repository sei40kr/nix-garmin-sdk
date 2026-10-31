# Regenerates sources.json from Garmin's SDK listings, keeping the newest
# patch release of each major.minor line.

cd "$(git rev-parse --show-toplevel)"

base=https://developer.garmin.com/downloads/connect-iq
old="$(cat sources.json 2>/dev/null || echo '{}')"

prefetch() {
  nix store prefetch-file --json --hash-type sha256 "$1" | jq -r .hash
}

sdks='[]'
while read -r version file; do
  # Archive names embed the build ID, so an unchanged name means unchanged content
  hash="$(jq -r --arg f "$file" '.sdks[]? | select(.file == $f) | .hash' <<<"$old")"
  if [[ -z "$hash" ]]; then
    echo "prefetching SDK $version" >&2
    hash="$(prefetch "$base/sdks/$file")"
  fi
  sdks="$(jq -c --arg v "$version" --arg f "$file" --arg h "$hash" \
    '. + [{version: $v, file: $f, hash: $h}]' <<<"$sdks")"
done < <(
  curl -fsSL "$base/sdks/sdks.json" |
    jq -r '
      map(select(.linux != null) | .v = (.version | split(".") | map(tonumber)))
      | group_by(.v[:2]) | map(max_by(.v)) | sort_by(.v)
      | .[] | "\(.version) \(.linux)"'
)

manager_version="$(curl -fsSL "$base/sdk-manager/sdk-manager.json" | jq -r .version)"
manager_hash="$(jq -r --arg v "$manager_version" 'select(.sdkManager.version == $v) | .sdkManager.hash' <<<"$old")"
if [[ -z "$manager_hash" ]]; then
  echo "prefetching SDK Manager $manager_version" >&2
  # The unversioned URL always serves the latest release
  manager_hash="$(prefetch "$base/sdk-manager/connectiq-sdk-manager-linux.zip")"
fi

jq -n --argjson sdks "$sdks" --arg v "$manager_version" --arg h "$manager_hash" \
  '{sdkManager: {version: $v, hash: $h}, sdks: $sdks}' >sources.json.tmp
mv sources.json.tmp sources.json
