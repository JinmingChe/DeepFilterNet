#!/bin/bash

set -e

if [ "$#" -ne 1 ]; then
  echo "Usage: release.sh <new-version>"
  exit 1
fi

VERSION=$1
CUR_VERSION=$(sed -nr "/^\[package\]/ { :l /^version[ ]*=/ { s/.*=[ ]*//; p; q;}; n; b l;}" libDF/Cargo.toml | tr -d "\"")

verle() {
  [ "$1" = "$(echo -e "$1\n$2" | sort -V | head -n1)" ]
}

verlt() {
  if [ "$1" = "$2" ]; then return 1; else verle "$1" "$2"; fi
}

if echo "$CUR_VERSION" | rg -q "\-pre"; then
  # Pre-release already has an incremented version
  if verlt "$VERSION" "${CUR_VERSION%-pre}"; then
    echo "New version ($VERSION) needs to be equal or greater then current version ($CUR_VERSION)"
    exit 2
  fi
else
  if verle "$VERSION" "$CUR_VERSION"; then
    echo "New version ($VERSION) needs to be greater then current version ($CUR_VERSION)"
    exit 2
  fi
fi

echo "Setting new version $VERSION"

set_version() {
  FILE=$1
  VERSION=$2
  sed -i "0,/^version/s/^version *= *\".*\"/version = \"$VERSION\"/" "$FILE"
}
export -f set_version

fd "(pyproject)|(Cargo)" -t f -e toml -x bash -c "set_version {} $VERSION"
(
  cd DeepFilterNet/
  # poetry add deepfilterlib@"$VERSION"
  # poetry add --optional deepfilterdataloader@"$VERSION"
  # Workaround since 'poetry add' needs the specified package version to be at pypi
  sed -i "s/^deepfilterlib.*/deepfilterlib = \"$VERSION\"/" pyproject.toml
  sed -i "s/^deepfilterdataloader.*/deepfilterdataloader = { version = \"$VERSION\", optional = true }/" pyproject.toml
  # Git dependency does not work when uploading to pypi
  sed -i "/^semetrics.*/d" pyproject.toml
)
cargo add --manifest-path ./pyDF/Cargo.toml deep_filter@"$VERSION" --features transforms
cargo add --manifest-path ./pyDF-data/Cargo.toml --features dataset deep_filter@"$VERSION"

(
  cd libDF
  cargo publish --allow-dirty
)

fd "(pyproject)|(Cargo)" -t f -e toml -X git add {}

git commit -m "v$VERSION"
git push
git tag -f "v$VERSION"
git push -f --tags

cargo update
