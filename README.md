# message-bubble-bundle

**Your Hermes agent's iMessage voice notes arrive as dead 00:00 file shells. This fixes that.**

On a stock Hermes Agent install, the Photon platform sends voice replies whose
attachment *paperwork* is fiction — the audio is transcoded one way and uploaded
declared as another, so iMessage renders a generic file card that doesn't play
instead of a native voice bubble. Text works. TTS works. The pipe works. The
identity of the attachment is what's broken, and it's broken out of the box.

This repository is a one-shot re-applier for the fix: a procedure of changes to
the photon plugin, packaged so any Hermes update that overwrites them can be
answered by running one script again.

## Use it

While this repo is private, from a clone:

```sh
git clone https://github.com/mooserini/message-bubble-bundle
cd message-bubble-bundle
./install.sh            # or: ./install.sh /path/to/hermes-agent
```

Once public, the one-liner form will be:

```sh
curl -fsSL https://raw.githubusercontent.com/mooserini/message-bubble-bundle/main/install.sh | bash
```

The script locates your Hermes checkout (`~/.hermes/hermes-agent` by default),
applies the patch, declares and installs the transcoder, and runs the photon
test suite as its gate. It refuses to run on a tree whose photon files you've
locally modified, refuses a patch that doesn't apply cleanly, and never
restarts your gateway. Re-running it on a patched tree is safe — it verifies
instead of re-applying.

## What it changes

`payload/procedure.patch` (sha256 `a255bcd82cac2de8eea29e5895d99c6bc0df0e8e8f07d0db1dc2d780c167b068`),
6 files, +316/−23:

- `plugins/platforms/photon/adapter.py` — outbound voice identity: uploads carry
  a fresh `voice-<uuid>.m4a` name with matching `audio/mp4` metadata; read and
  read_receipt events are dropped before agent dispatch.
- `plugins/platforms/photon/sidecar/index.mjs` + `voice-send.mjs` (new) — the
  sidecar voice send path.
- `plugins/platforms/photon/sidecar_paths.py` — voice-send.mjs is mirrored into
  writable sidecar installs alongside the existing sidecar files.
- `tests/plugins/platforms/photon/` — regression coverage for the above.

Plus two declarations in the sidecar's `package.json`, made by the script:
`ffmpeg-static ^5.3.0` as a dependency, and an `allowScripts` pre-approval for
its install script — without the approval, npm silently skips downloading the
ffmpeg binary and the bundle is present but toothless.

**It does not change your spectrum-ts version.** The fix is version-indifferent
by design and by measurement: it was proven green and endpoint-verified with
the pin left at 12.10.1, and separately rehearsed green on 12.7.0.

## The proof

Fleet A/B, November 12, 2026, all on spectrum-ts 12.10.1:

| seat | state | result at the phone |
|---|---|---|
| Echo (Windows) | untreated | voice replies = dead file shells |
| Ara (macOS) | untreated | voice replies = dead file shells |
| Kaishi (macOS) | **treated** | **native voice bubble, first message** |

Test suites (photon, per tree): treated 166 passed / 1 skipped vs 161/1 pristine
control on the live 12.10.1 base; 154/1 vs 149/1 on the 12.7.0 base. The treated
seat then held a full round-trip voice conversation — outbound bubbles playable,
inbound voice notes transcribed.

## The record

This procedure was first filed upstream in August 2026 as three pull requests
against NousResearch/hermes-agent — #91129 (inbound CAF recognition), #91369
(outbound voice attachment identity), #91880 (the assembled bundle). A maintainer
commented once (Aug 30) that the SDK line was being held to soak and promised a
re-review; the re-review never came, and the author closed the PRs himself on
October 6–9, 2026 under the project's open-PR limit. The filing repository
("Hermes Agent Archive") was later deleted under the reasonable assumption that
silence meant the fix had landed; it had not — the PR pages remain as the public
record. A later PR by another author, #152929, addresses the same fault and is
cited here with respect; this bundle is the complete procedure, proven end-to-end
at the endpoint, which is the layer where the bug actually lives.

## Known limits

- macOS/Linux (bash) today. A Windows (PowerShell) twin is planned; the
  procedure itself is platform-identical.
- Inbound media larger than Photon's 20 MiB inline cap arrives as metadata
  only. That is a separate platform behavior; this bundle does not address it.
- One named divergence from the author's original bundle notes: the spectrum
  mixed-attachment patch that ships in current Hermes is *not* removed by this
  procedure. Both rehearsals and the live treated seat ran with it present and
  passed; it is a watch item, not a known break.

## Undo

From your Hermes checkout:

```sh
git checkout -- plugins/platforms/photon tests/plugins/platforms/photon
cd plugins/platforms/photon/sidecar && npm install
```

That returns the plugin to stock. Your Photon login, project, and phone number
live server-side and are untouched by either direction.

---

Procedure by Thomas Kenny (mooserini). Packaged with Maren Frost.
License to be set by the repository owner.
