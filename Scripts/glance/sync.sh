#!/usr/bin/env bash
# Keeps the glance fork current with upstream CodexBar and installs only builds that pass.
#
# Each run: rebase the glance branch onto upstream/main in a dedicated clone, build, run the glance tests,
# package, install to /Applications, then publish the rebased branch to the fork. Any failure leaves the
# installed app untouched and posts a notification. Run by the com.sdrshn.codexbar-glance-sync LaunchAgent.
#
# Development clones must `git pull --rebase` after a sync, because the fork's glance branch is rebased.
set -euo pipefail

GLANCE_HOME="${GLANCE_HOME:-$HOME/Library/Application Support/CodexBarGlance}"
SRC="$GLANCE_HOME/src"
STATE_FILE="$GLANCE_HOME/installed-commit"
LOCK_DIR="$GLANCE_HOME/lock"
APP_DEST="${GLANCE_APP_DEST:-/Applications/CodexBar.app}"
FORK_URL="https://github.com/sdrshn-nmbr/CodexBar.git"
UPSTREAM_URL="https://github.com/steipete/CodexBar.git"
BRANCH="glance"
CLI_LINK="$HOME/.local/bin/codexbar"
# Stable local identity: macOS keys privacy grants and Keychain access to it, so they survive updates.
# Ad-hoc signatures change every build and make macOS re-ask after each install.
SIGN_IDENTITY="${GLANCE_SIGN_IDENTITY:-CodexBar Glance Local Signing}"

mkdir -p "$GLANCE_HOME"

log() { printf '%s [glance-sync] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*"; }
notify() { osascript -e "display notification \"$1\" with title \"CodexBar Glance\"" >/dev/null 2>&1 || true; }
fail() {
  log "FAILED: $1"
  notify "Update skipped: $1. Still running the previous build."
  exit 1
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "another sync is running; exiting"
  exit 0
fi
trap 'rmdir "$LOCK_DIR"' EXIT

if [[ "${GLANCE_FORCE:-0}" != "1" ]] && ! pmset -g batt | grep -q "AC Power"; then
  log "on battery; deferring to the next scheduled run"
  exit 0
fi

if [[ ! -d "$SRC/.git" ]]; then
  log "cloning fork into $SRC"
  git clone --branch "$BRANCH" "$FORK_URL" "$SRC"
  git -C "$SRC" remote add upstream "$UPSTREAM_URL"
fi

cd "$SRC"
git fetch --prune --quiet origin
git fetch --prune --quiet upstream main
published=$(git rev-parse "origin/$BRANCH")
git checkout --quiet -B "$BRANCH" "origin/$BRANCH"
git reset --quiet --hard "origin/$BRANCH"
git clean -fdq -e .build

rebased=0
if ! git merge-base --is-ancestor upstream/main HEAD; then
  log "rebasing $BRANCH onto upstream/main ($(git rev-parse --short upstream/main))"
  if ! git rebase --quiet upstream/main; then
    conflicts=$(git diff --name-only --diff-filter=U | tr '\n' ' ')
    git rebase --abort
    fail "upstream conflicts in ${conflicts:-unknown files}"
  fi
  rebased=1
fi

target=$(git rev-parse HEAD)
if [[ -f "$STATE_FILE" && "$(cat "$STATE_FILE")" == "$target" && -d "$APP_DEST" ]]; then
  log "already installed $target"
  exit 0
fi

log "building $target"
swift build --product CodexBar >"$GLANCE_HOME/last-build.log" 2>&1 || fail "build failed (see last-build.log)"
swift test --filter GlanceModelTests >"$GLANCE_HOME/last-test.log" 2>&1 || fail "glance tests failed (see last-test.log)"
xcodebuild -resolvePackageDependencies -project WidgetExtension/CodexBarWidgetExtension.xcodeproj \
  -scheme CodexBarWidgetExtension -derivedDataPath .build/xcode-widget-extension-release \
  >"$GLANCE_HOME/last-resolve.log" 2>&1 \
  || fail "widget dependency refresh failed (see last-resolve.log)"
CODEXBAR_SKIP_LAUNCH_SMOKE=1 ./Scripts/package_app.sh release >"$GLANCE_HOME/last-package.log" 2>&1 \
  || fail "packaging failed (see last-package.log)"

if security find-identity -p codesigning -v | grep -q "\"$SIGN_IDENTITY\""; then
  log "signing with $SIGN_IDENTITY"
  codesign --force --deep --sign "$SIGN_IDENTITY" --preserve-metadata=entitlements,flags,runtime \
    --timestamp=none "$SRC/CodexBar.app" >"$GLANCE_HOME/last-sign.log" 2>&1 \
    || fail "signing failed (see last-sign.log)"
  codesign --verify --deep --strict "$SRC/CodexBar.app" >>"$GLANCE_HOME/last-sign.log" 2>&1 \
    || fail "signature check failed (see last-sign.log)"
else
  log "WARNING: signing identity '$SIGN_IDENTITY' not found; installing ad-hoc build"
fi

log "installing to $APP_DEST"
rm -rf "$GLANCE_HOME/previous"
if [[ -d "$APP_DEST" ]]; then
  mkdir -p "$GLANCE_HOME/previous"
  ditto "$APP_DEST" "$GLANCE_HOME/previous/CodexBar.app"
fi
was_running=0
if pgrep -x CodexBar >/dev/null; then
  was_running=1
  pkill -x CodexBar || true
  for _ in {1..50}; do pgrep -x CodexBar >/dev/null || break; sleep 0.1; done
fi
rm -rf "$APP_DEST"
ditto "$SRC/CodexBar.app" "$APP_DEST"
echo "$target" >"$STATE_FILE"
mkdir -p "$(dirname "$CLI_LINK")"
ln -sf "$APP_DEST/Contents/Helpers/CodexBarCLI" "$CLI_LINK"
if [[ "$was_running" == "1" || "${GLANCE_LAUNCH:-1}" == "1" ]]; then
  open "$APP_DEST"
  sleep 8
  if ! pgrep -x CodexBar >/dev/null; then
    if [[ -d "$GLANCE_HOME/previous/CodexBar.app" ]]; then
      rm -rf "$APP_DEST"
      ditto "$GLANCE_HOME/previous/CodexBar.app" "$APP_DEST"
      rm -f "$STATE_FILE"
      open "$APP_DEST"
    fi
    fail "installed $target exited at launch; restored previous build"
  fi
fi

if [[ "$rebased" == "1" ]]; then
  if git push --quiet --force-with-lease="$BRANCH:$published" origin "HEAD:refs/heads/$BRANCH"; then
    log "published rebased $BRANCH"
  else
    log "WARNING: could not publish rebased $BRANCH (installed build is still current)"
  fi
  git push --quiet --force origin upstream/main:refs/heads/main || log "WARNING: could not mirror upstream main"
fi

cp "$SRC/Scripts/glance/sync.sh" "$GLANCE_HOME/bin/sync.sh" 2>/dev/null || true
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DEST/Contents/Info.plist")
log "installed CodexBar $version (glance $(git rev-parse --short HEAD))"
notify "Updated to CodexBar $version"
