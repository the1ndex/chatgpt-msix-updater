[简体中文](README.md) | **English**

# One-Click ChatGPT Windows MSIX Updater

This script is intended for Windows PCs that cannot use the Microsoft Store normally. It resolves the latest installer from ChatGPT's Microsoft Store product page, selects the primary `x64 .msix` package, downloads it to the current user's `Downloads` folder, verifies it, and then installs or updates the app.

> Microsoft Store product ID: [`9PLM9XGG6VKS`](https://apps.microsoft.com/detail/9plm9xgg6vks?hl=en-US&gl=US)

## Features

- Gets temporary Microsoft Store download links through [store.rg-adguard.net](https://store.rg-adguard.net/).
- Selects the primary `x64 .msix` package while excluding `arm64`, BlockMap, and framework dependency packages.
- Only accepts installer downloads from Microsoft's `*.dl.delivery.mp.microsoft.com` domain.
- Verifies both the SHA-1 value returned by the resolver and the MSIX digital signature; an invalid package is never installed.
- Compares the installed version automatically and avoids downloading an approximately 700 MB package when the latest version is already installed.
- Supports resumable downloads, download-only mode, and resolve-only testing.

## Usage

Download this repository, then double-click:

```text
Update-ChatGPT-Codex.bat
```

You can also run the script from PowerShell:

```powershell
# Check for an update, download it, and install it
.\Update-ChatGPT-Codex.ps1

# Resolve the latest package information without downloading
.\Update-ChatGPT-Codex.ps1 -ResolveOnly

# Download the package without installing it
.\Update-ChatGPT-Codex.ps1 -DownloadOnly

# Download the package even when the latest version is already installed
.\Update-ChatGPT-Codex.ps1 -ForceDownload
```

The default download directory is:

```text
%USERPROFILE%\Downloads
```

To use a different directory:

```powershell
.\Update-ChatGPT-Codex.ps1 -DownloadDirectory 'D:\Downloads'
```

## Requirements

- Windows 10 or Windows 11 x64
- Windows PowerShell 5.1 or PowerShell 7
- A system capable of running `curl.exe` and `Add-AppxPackage`
- Network access to rg-adguard and Microsoft's download servers

Administrator privileges are not required. The script may close a running ChatGPT window while installing an update.

## Why Does the Package Name Contain Codex?

The ChatGPT desktop app is currently returned by the Microsoft Store with the internal MSIX package name `OpenAI.Codex`, while its displayed application name remains ChatGPT. The script treats the Microsoft Store product URL and product ID as the application identity and does not hard-code `OpenAI.Codex` as a validation condition. The internal package name is extracted from each live response and is used only to check the installed version.

## Troubleshooting

If rg-adguard temporarily triggers a Cloudflare challenge, the script retries automatically three times. If it still fails, open [store.rg-adguard.net](https://store.rg-adguard.net/) in a browser, complete the verification, and run the script again. Temporary download links expire, so the script resolves a new link on every run and never stores an old one.

## Disclaimer

This is an unofficial community script and is not affiliated with OpenAI, Microsoft, or rg-adguard. It does not include or redistribute the ChatGPT installer; the actual package is supplied by Microsoft's download servers.
