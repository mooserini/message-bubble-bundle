#!/usr/bin/env bash
# message-bubble-bundle — re-apply the Photon voice procedure to a Hermes Agent install.
#
# What this fixes: on a stock Hermes install, Photon/iMessage voice messages arrive
# at the recipient's phone as dead 00:00 file shells instead of native voice bubbles.
# The fault is outbound attachment identity in the photon plugin (the sidecar uploaded
# transcoded audio under the wrong name/MIME/declared type). The fix is a procedure,
# not a version bump — proven version-indifferent on spectrum-ts 12.7.0 and 12.10.1.
#
# What it does, in order:
#   1. Locates your Hermes Agent checkout (arg 1, else $HERMES_HOME/hermes-agent,
#      else ~/.hermes/hermes-agent).
#   2. Applies payload/procedure.patch (6 files: adapter identity fix, sidecar
#      voice-send mirroring, read/read-receipt suppression, regression tests).
#   3. Adds ffmpeg-static ^5.3.0 to the sidecar's package.json AND pre-approves its
#      install script (allowScripts) — without that approval npm silently skips the
#      ffmpeg binary download and voice transcoding has no transcoder.
#   4. Runs npm install in the sidecar and VERIFIES the ffmpeg binary actually landed.
#   5. Runs the photon test suite as the gate, if a runner is available.
#
# Safe by design: refuses to touch a tree whose photon files are locally modified;
# refuses on a patch that does not apply cleanly; idempotent (re-running on an
# already-patched tree verifies and exits 0). It never restarts your gateway —
# bounce it yourself when you're ready, the way you'd want it.
#
# Provenance: PRs NousResearch/hermes-agent #91129, #91369, #91880 (Aug 2026,
# closed unreviewed Oct 2026). Endpoint proof, Nov 12 2026: untreated seats on
# spectrum-ts 12.10.1 produced dead shells; the treated seat produced a native
# voice bubble on the first message, same pin.
#
# Author: Thomas Kenny (mooserini) — procedure. Packaged with Maren Frost.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="$SCRIPT_DIR/payload/procedure.patch"
TARGET="${1:-${HERMES_HOME:-$HOME/.hermes}/hermes-agent}"
PHOTON_REL="plugins/platforms/photon"
SIDECAR_REL="$PHOTON_REL/sidecar"

say()  { printf '%s\n' "$*"; }
die()  { printf 'message-bubble-bundle: REFUSING — %s\n' "$*" >&2; exit 1; }

[ -d "$TARGET" ] || die "Hermes checkout not found at $TARGET (pass the path as arg 1)."
[ -f "$TARGET/$PHOTON_REL/adapter.py" ] || die "$TARGET does not look like a Hermes Agent checkout (no photon adapter)."
[ -f "$PATCH" ] || die "payload/procedure.patch missing next to install.sh."
cd "$TARGET"

# Toolchain: prefer Hermes-bundled node/uv when the bare names are absent.
for tool_dir in "$HOME"/.hermes/tools/node-*/bin; do
  [ -x "$tool_dir/node" ] && PATH="$tool_dir:$PATH"
done
command -v node >/dev/null || die "node not found on PATH and no Hermes-bundled node under ~/.hermes/tools."
command -v npm  >/dev/null || die "npm not found alongside node."
command -v git  >/dev/null || die "git not found."

# State detection: patched already?
ALREADY=0
if [ -f "$SIDECAR_REL/voice-send.mjs" ] && grep -q '"ffmpeg-static"' "$SIDECAR_REL/package.json" 2>/dev/null; then
  ALREADY=1
fi

if [ "$ALREADY" -eq 0 ]; then
  # Refuse to trample local modifications to the files the patch touches.
  DIRTY="$(git status --porcelain -- "$PHOTON_REL" tests/plugins/platforms/photon | grep -v '^??' || true)"
  [ -z "$DIRTY" ] || die "photon files are locally modified; stash or commit them first:
$DIRTY"
  git apply --check "$PATCH" || die "procedure.patch does not apply cleanly to this tree (unexpected base — nothing changed)."
  git apply "$PATCH"
  say "procedure.patch applied (6 files)."
else
  say "procedure already present (voice-send.mjs + ffmpeg-static) — verifying instead of re-applying."
fi

# package.json: declare ffmpeg-static and pre-approve its install script.
node - "$TARGET/$SIDECAR_REL/package.json" <<'EOF'
const fs = require('fs');
const p = process.argv[2];
const pkg = JSON.parse(fs.readFileSync(p, 'utf8'));
pkg.dependencies = pkg.dependencies || {};
pkg.dependencies['ffmpeg-static'] = '^5.3.0';
pkg.allowScripts = pkg.allowScripts || {};
pkg.allowScripts['ffmpeg-static@5.3.0'] = true;
fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + '\n');
console.log('package.json: ffmpeg-static ^5.3.0 declared; install script pre-approved.');
EOF

# Sidecar install — this is where the ffmpeg binary is fetched; verify it landed.
( cd "$SIDECAR_REL" && npm install --no-audit --no-fund )
FFBIN="$TARGET/$SIDECAR_REL/node_modules/ffmpeg-static/ffmpeg"
[ -x "$FFBIN" ] || die "npm install completed but the ffmpeg binary is missing at $FFBIN (install script blocked?). Nothing else to do — report this."
say "ffmpeg binary verified: $FFBIN ($(stat -f%z "$FFBIN" 2>/dev/null || stat -c%s "$FFBIN") bytes)."
[ -f "$TARGET/$SIDECAR_REL/voice-send.mjs" ] || die "voice-send.mjs missing after patch — tree is in an unexpected state."
say "voice-send.mjs present in sidecar."

# Gate: the photon suite, when a runner exists. Skipped gate is reported, never faked.
# The suite needs the fleet-proven environment shape: HERMES_HOME unset and
# HERMES_RUNTIME_DIR pointed at a scratch dir, or adapter construction dies in
# the package-store root resolution and half the suite fails on environment,
# not code (Ara's fan-out harness note, Nov 12 2026 — verified the hard way).
SUITE_RESULT="not run (no uv/pytest found)"
SUITE_RUNTIME_DIR="$(mktemp -d)"
if command -v uv >/dev/null; then
  if env -u HERMES_HOME HERMES_RUNTIME_DIR="$SUITE_RUNTIME_DIR" uv run --group dev pytest tests/plugins/platforms/photon -q > /tmp/mbb-suite.log 2>&1; then
    SUITE_RESULT="PASS ($(tail -1 /tmp/mbb-suite.log))"
  else
    tail -5 /tmp/mbb-suite.log >&2 || true
    die "photon suite FAILED on the patched tree (full log: /tmp/mbb-suite.log). The patch is applied but NOT proven — investigate before use."
  fi
elif python3 -c 'import pytest' >/dev/null 2>&1; then
  if env -u HERMES_HOME HERMES_RUNTIME_DIR="$SUITE_RUNTIME_DIR" python3 -m pytest tests/plugins/platforms/photon -q > /tmp/mbb-suite.log 2>&1; then
    SUITE_RESULT="PASS ($(tail -1 /tmp/mbb-suite.log))"
  else
    tail -5 /tmp/mbb-suite.log >&2 || true
    die "photon suite FAILED on the patched tree (full log: /tmp/mbb-suite.log)."
  fi
fi

say ""
say "message-bubble-bundle: applied and verified."
say "  tree:        $TARGET"
say "  suite:       $SUITE_RESULT"
say "  next step:   restart your gateway when ready (this script never restarts it for you)."
say "  first proof: send your agent a text and have it reply with /voice on — a native bubble, not a shell."
