# AI RTL Fix

AI RTL Fix is a Windows RTL patch manager for desktop AI apps.

The current baseline supports **Claude Desktop** using the MIT-licensed work from
[`shraga100/claude-desktop-rtl-patch`](https://github.com/shraga100/claude-desktop-rtl-patch).
The goal is to evolve this into one tool for Claude Desktop, Codex Desktop, and
other AI desktop apps that need better Hebrew, Arabic, Persian, and mixed
RTL/LTR text rendering.

## Current Status

- Claude Desktop patching is imported from the original Claude Desktop RTL Patch.
- Codex Desktop read-only inspection is available as the next discovery step.
- ChatGPT Desktop support is planned after Codex discovery.
- The verified `irm | iex` installer flow uses an AI RTL Fix signing key.

## What It Does Today

For Claude Desktop, the patcher:

- Detects RTL text in Claude responses and the input box.
- Keeps code blocks and code-like content LTR.
- Creates backups of modified files.
- Can restore the original app state.
- Can enable an automatic re-patch scheduled task after Claude updates.

## Running Locally

Open Windows PowerShell as Administrator from this repository and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\patch.ps1
```

The verified installer downloads `patch.ps1` and `patch.ps1.sig` from this
repository and checks them against the AI RTL Fix public key before elevation:

```powershell
irm https://raw.githubusercontent.com/Ben-Boaron0/ai-rtl-fix/main/install.ps1 | iex
```

## Menu

The menu is app-first: select target apps, then choose an action available for
that selection. Codex inspection is read-only and does not patch or launch
Codex.

```text
AI RTL Fix

Select target apps:
  1. [ ] Claude Desktop: Found
  2. [ ] Codex Desktop: Found
  3. [ ] ChatGPT Desktop: Not found (planned)

Toggle app number, A for all supported, C to continue, Q to exit

Selected apps:
  - Codex Desktop

Select action:
  1. Inspect selected apps
  B. Back to app selection
  Q. Exit
```

## Verification

The public-key fingerprint for the verified installer is:

```text
dc:6e:f8:65:eb:3c:00:46:76:98:3b:35:9c:77:1e:ba:31:70:4b:5f:fc:c2:b2:3e:5f:4a:d3:46:44:84:7b:1f
```

Maintainer commands:

```powershell
# One-time key creation, then back up C:\Users\Ben\.ai-rtl-fix-signing.key.
powershell -ExecutionPolicy Bypass -File .\tools\new-signing-key.ps1

# Per release after patch.ps1 changes.
powershell -ExecutionPolicy Bypass -File .\tools\sign-release.ps1
powershell -ExecutionPolicy Bypass -File .\tools\verify-signature.ps1
```

## How The Claude Patch Works

Claude Desktop is an Electron application. The imported Claude patch modifies
its packaged JavaScript and handles Claude-specific integrity checks:

1. Extracts `app.asar`.
2. Injects RTL JavaScript into renderer files.
3. Repackages `app.asar`.
4. Replaces the ASAR hash embedded in `claude.exe`.
5. Re-signs modified binaries with a self-signed certificate.
6. Updates Claude's service certificate expectations.
7. Stores backups so the original state can be restored.

Codex and ChatGPT may require different app-specific patch strategies. AI RTL
Fix will treat each app as its own adapter rather than assuming Claude's exact
integrity model applies everywhere.

## Codex Inspection

Run the normal menu and choose option `6`, or run the read-only inspection
directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\patch.ps1 -InspectCodex
```

The inspection reports the installed Codex package, `app.asar` shape,
`webview/index.html` injection candidate, renderer assets, ASAR integrity
metadata, and whether the current ASAR hashes appear embedded in Codex binaries.
It does not modify Codex files.

## Attribution

This project includes code adapted from
[`shraga100/claude-desktop-rtl-patch`](https://github.com/shraga100/claude-desktop-rtl-patch),
licensed under the MIT License. See [NOTICE.md](NOTICE.md) and [LICENSE](LICENSE).

## Disclaimer

This tool modifies installed desktop application files. Use it at your own risk.
Always keep backups, and restore the original state before reporting issues to
the upstream app vendors.

## License

MIT
