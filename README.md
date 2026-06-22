# Codex RTL Fix

**Right-to-left support for Codex Desktop on Windows.**

Codex RTL Fix installs a small local runtime that launches Codex through `Codex RTL` shortcuts, opens a loopback-only DevTools port, and injects an idempotent RTL patch into the renderer at runtime. It does not modify the Microsoft Store package under `WindowsApps`.

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6.svg)](#requirements)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE.svg)](#requirements)

## What It Does

- Creates `Codex RTL` shortcuts that launch Codex with local RTL injection.
- Keeps mixed Hebrew or Arabic content readable without changing the installed app package.
- Preserves normal left-to-right behavior for technical fragments such as code blocks and English-only text.
- Verifies the signed bootstrap script before elevation.

## Requirements

| Requirement | Notes |
| :--- | :--- |
| **Windows 10 / 11** | Codex Desktop installed |
| **Windows PowerShell** | Windows PowerShell 5.1 (`powershell.exe`) or PowerShell 7 (`pwsh`) |
| **Administrator** | Required for install and restore |

## Quick Install

Open **Windows PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/Ben-Boaron0/codex-rtl-fix/main/install.ps1 | iex
```

The installer verifies `patch.ps1`, downloads the required module files, prompts for elevation, and opens the Codex RTL Fix menu.

## If You Prefer To Run From A Local Checkout

```powershell
git clone https://github.com/Ben-Boaron0/codex-rtl-fix.git
cd codex-rtl-fix
powershell.exe -ExecutionPolicy Bypass -File .\patch.ps1
```

## How It Works

Codex RTL Fix keeps the Microsoft Store installation untouched and works entirely through a local runtime under `%LOCALAPPDATA%\Codex RTL Fix`.

At patch time it:

1. Copies the signed runtime files into the local runtime folder.
2. Creates or refreshes `Codex RTL` shortcuts in writable user-facing locations.
3. Launches Codex with:
   - `--remote-debugging-port=<port>`
   - `--remote-debugging-address=127.0.0.1`
4. Injects a small RTL payload through DevTools:
   - `Page.addScriptToEvaluateOnNewDocument` for future documents
   - `Runtime.evaluate` for the currently open document

The payload is idempotent and reapplies itself when Codex recreates relevant DOM surfaces.

## Menu

When you run the tool, the menu offers:

```text
Codex Desktop: Found

  1. Patch Codex RTL
  2. Restore Codex RTL
  3. Exit
```

- `Patch Codex RTL` installs the local runtime, creates or refreshes `Codex RTL` shortcuts, and relaunches Codex with RTL injection if needed.
- `Restore Codex RTL` removes the local runtime launcher artifacts and owned `Codex RTL` shortcuts.

## Using It

- Launch Codex through a `Codex RTL` shortcut when you want RTL support.
- Launch Codex through the normal Codex shortcut when you want the unpatched app.
- If Codex is already open during patch or restore, the tool may restart it so the runtime state is consistent.

## Troubleshooting

**Codex Desktop was not found**

Install or reopen Codex Desktop, then run Codex RTL Fix again.

**Codex opens without RTL fixes**

Launch Codex through a `Codex RTL` shortcut, not the original Codex shortcut. If the shortcut is missing, run `Patch Codex RTL` again.

**Controlled Folder Access warns about Codex**

Codex RTL Fix stores its runtime under `%LOCALAPPDATA%\Codex RTL Fix` and launches Codex with local DevTools flags so it can inject RTL support. If Controlled Folder Access is enabled, allow Codex or keep Codex workspaces outside protected folders.

**Windows PowerShell shows `Import-Module ... AuditToString is already present`**

This is a cosmetic warning from the Appx module when running under PowerShell 7. It does not affect the tool. You can safely ignore it, or switch to Windows PowerShell (`powershell.exe`) to suppress it.

## Security And Verification

`install.ps1` verifies an RSA-4096 signature over this repo's `patch.ps1` before running it. `patch.ps1` also pins SHA-256 hashes for every dot-sourced module it loads.

**Public-key fingerprint (SHA-256):**

```text
dc:6e:f8:65:eb:3c:00:46:76:98:3b:35:9c:77:1e:ba:31:70:4b:5f:fc:c2:b2:3e:5f:4a:d3:46:44:84:7b:1f
```

To verify a local checkout:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\verify-signature.ps1
```

This key is what lets the installer confirm that the checked-out `patch.ps1` matches a release signed by the maintainer. If the public key or fingerprint changes unexpectedly and there is no clearly announced key rotation in the repo history or release notes, treat that as a reason to pause and review before running the tool.

## Maintainer Notes

These are only needed when preparing or validating a release:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\sign-release.ps1
powershell -ExecutionPolicy Bypass -File .\tools\verify-signature.ps1
```

## Support Status

> [!CAUTION]
> This tool changes desktop app behavior in unsupported ways. Use it at your own risk.

By using it, you accept that:

1. You trust the code you are running with administrator privileges.
2. Modifying Codex behavior may not align with vendor support expectations or terms.
3. RTL support depends on launching Codex through Codex RTL Fix-created shortcuts.
4. This is a stopgap until Codex provides native RTL support.

## License

MIT
