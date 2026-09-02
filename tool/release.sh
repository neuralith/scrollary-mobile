#!/usr/bin/env bash
#
# Cut a release: bump the version, check the build, commit and tag.
#
#   bash tool/release.sh              # 1.0.0 -> 1.0.1  (patch, the default)
#   bash tool/release.sh --minor      # 1.0.1 -> 1.1.0
#   bash tool/release.sh --major      # 1.1.0 -> 2.0.0
#   bash tool/release.sh --set 2.3.4  # exactly that
#
#   --dry-run     say what would change and touch nothing
#   --no-verify   skip `flutter analyze` and `flutter test` (they run by default)
#   --no-commit   write the files, leave them uncommitted and untagged
#   --push        push the branch and the tag after committing
#
# Two numbers move, and they mean different things. The **version** is what a
# person reads — 1.0.1. The **build number** is what the stores key an upload
# on: it only ever goes up, including across versions, because App Store
# Connect and Play both refuse an upload that reuses one.
#
# Two files hold them and they must agree: `pubspec.yaml`, which is what the
# build system reads, and `lib/core/version.dart`, which is what the app shows.
# `test/version_test.dart` fails the build if they ever disagree, so this
# script is the only supported way to move them.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
PUBSPEC="$REPO_ROOT/pubspec.yaml"
VERSION_DART="$REPO_ROOT/lib/core/version.dart"

BUMP=patch
EXPLICIT=""
DRY_RUN=false
VERIFY=true
COMMIT=true
PUSH=false

die() { printf 'release: %s\n' "$*" >&2; exit 1; }
say() { printf '\n=== %s ===\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --patch) BUMP=patch ;;
    --minor) BUMP=minor ;;
    --major) BUMP=major ;;
    --set) shift; EXPLICIT="${1:-}"; [ -n "$EXPLICIT" ] || die "--set needs a version" ;;
    --dry-run) DRY_RUN=true ;;
    --no-verify) VERIFY=false ;;
    --no-commit) COMMIT=false ;;
    --push) PUSH=true ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

command -v flutter >/dev/null 2>&1 || die "flutter is not on PATH"
[ -f "$PUBSPEC" ] || die "no pubspec.yaml at $PUBSPEC"
[ -f "$VERSION_DART" ] || die "no lib/core/version.dart — this script generates it, but it must exist to be replaced"

# --- where we are now -------------------------------------------------------

CURRENT_LINE=$(grep -E '^version: ' "$PUBSPEC" || true)
[ -n "$CURRENT_LINE" ] || die "pubspec.yaml has no 'version:' line"

CURRENT=${CURRENT_LINE#version: }
CURRENT_VERSION=${CURRENT%%+*}
CURRENT_BUILD=${CURRENT##*+}

case "$CURRENT_VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) die "cannot read '$CURRENT_VERSION' as major.minor.patch" ;;
esac
case "$CURRENT_BUILD" in
  ''|*[!0-9]*) die "cannot read '$CURRENT_BUILD' as a build number" ;;
esac

MAJOR=${CURRENT_VERSION%%.*}
REST=${CURRENT_VERSION#*.}
MINOR=${REST%%.*}
PATCH=${REST#*.}

# --- where we are going -----------------------------------------------------

if [ -n "$EXPLICIT" ]; then
  case "$EXPLICIT" in
    [0-9]*.[0-9]*.[0-9]*) NEXT_VERSION="$EXPLICIT" ;;
    *) die "--set wants major.minor.patch, got '$EXPLICIT'" ;;
  esac
else
  case "$BUMP" in
    patch) NEXT_VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
    minor) NEXT_VERSION="$MAJOR.$((MINOR + 1)).0" ;;
    major) NEXT_VERSION="$((MAJOR + 1)).0.0" ;;
  esac
fi
NEXT_BUILD=$((CURRENT_BUILD + 1))
TAG="v$NEXT_VERSION"

printf 'release: %s (%s)  ->  %s (%s)\n' \
  "$CURRENT_VERSION" "$CURRENT_BUILD" "$NEXT_VERSION" "$NEXT_BUILD"

if [ "$DRY_RUN" = true ]; then
  printf 'release: --dry-run, nothing written\n'
  exit 0
fi

# --- refuse to release from a tree that is not the one being tested ---------

if [ "$COMMIT" = true ]; then
  git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "not a git repository — pass --no-commit to write the files anyway"
  if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
    die "the working tree has uncommitted changes; commit or stash them first (or pass --no-commit)"
  fi
  if git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    die "tag $TAG already exists"
  fi
fi

# --- write ------------------------------------------------------------------

say "writing $NEXT_VERSION+$NEXT_BUILD"

# In place, on the one line, so nothing else in pubspec.yaml can be touched by
# a stray match: `version:` at the start of a line appears exactly once.
tmp=$(mktemp)
awk -v v="version: $NEXT_VERSION+$NEXT_BUILD" \
  '/^version: /{print v; next} {print}' "$PUBSPEC" > "$tmp"
mv "$tmp" "$PUBSPEC"

tmp=$(mktemp)
awk -v ver="const String kAppVersion = '$NEXT_VERSION';" \
    -v bld="const int kAppBuild = $NEXT_BUILD;" \
  '/^const String kAppVersion = /{print ver; next} \
   /^const int kAppBuild = /{print bld; next} {print}' "$VERSION_DART" > "$tmp"
mv "$tmp" "$VERSION_DART"

grep -q "kAppVersion = '$NEXT_VERSION'" "$VERSION_DART" \
  || die "lib/core/version.dart was not rewritten — has its shape changed?"

# --- check ------------------------------------------------------------------

if [ "$VERIFY" = true ]; then
  say 'flutter analyze'
  (cd "$REPO_ROOT" && flutter analyze) || die "analyze failed — nothing was committed"
  say 'flutter test'
  (cd "$REPO_ROOT" && flutter test) || die "tests failed — nothing was committed"
fi

# --- commit and tag ---------------------------------------------------------

if [ "$COMMIT" = false ]; then
  say "written, not committed"
  printf 'release: pubspec.yaml and lib/core/version.dart are at %s+%s\n' \
    "$NEXT_VERSION" "$NEXT_BUILD"
  exit 0
fi

say "committing $TAG"
git -C "$REPO_ROOT" add pubspec.yaml lib/core/version.dart
git -C "$REPO_ROOT" commit -m "release: $TAG (build $NEXT_BUILD)"
git -C "$REPO_ROOT" tag -a "$TAG" -m "$TAG (build $NEXT_BUILD)"

if [ "$PUSH" = true ]; then
  BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)
  say "pushing $BRANCH and $TAG"
  git -C "$REPO_ROOT" push origin "$BRANCH"
  git -C "$REPO_ROOT" push origin "$TAG"
else
  printf '\nrelease: committed and tagged locally. Push with:\n'
  printf '  git push origin %s && git push origin %s\n' \
    "$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)" "$TAG"
fi
