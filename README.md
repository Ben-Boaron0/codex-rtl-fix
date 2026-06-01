# AI RTL Fix

AI RTL Fix is a Windows RTL patch manager for desktop AI apps.

The current baseline supports **Claude Desktop** using the MIT-licensed work from
[`shraga100/claude-desktop-rtl-patch`](https://github.com/shraga100/claude-desktop-rtl-patch).
The goal is to evolve this into one tool for Claude Desktop, Codex Desktop, and
other AI desktop apps that need better Hebrew, Arabic, Persian, and mixed
RTL/LTR text rendering.

## Current Status

- Claude Desktop patching is imported from the original Claude Desktop RTL Patch.
- Codex Desktop support is planned next.
- ChatGPT Desktop support is planned after Codex discovery.
- The verified `irm | iex` installer flow needs a new AI RTL Fix signing key
  before public releases.

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

Do not use the old upstream `irm | iex` command for this repository. The
imported signature files still belong to the original Claude patch project and
will be replaced once AI RTL Fix has its own release signing flow.

## Menu

The current menu is still Claude-focused while the project is being reshaped.
The next UI milestone is:

```text
AI RTL Fix

Detected apps:
  Claude Desktop: Found
  Codex Desktop: Found
  ChatGPT Desktop: Not found

Select action:
  1. Patch Claude Desktop RTL
  2. Restore Claude Desktop
  3. Create Claude quick update shortcut
  4. Enable Claude auto re-patch
  5. Disable Claude auto re-patch
  6. Exit
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
