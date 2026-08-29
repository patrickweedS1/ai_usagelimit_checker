# 🧠 Neurolytics — AI Monitoring App

A native macOS menu bar status item, standalone application window, and desktop widget to monitor real-time AI usage limits for:
1. **Claude (Claude Code / Anthropic)**
2. **Antigravity (Google Code Assist / Gemini)**
3. **ChatGPT (Codex / OpenAI)**
4. **Devin (Cognition)**

---

## 📂 Project Structure

- `generate_icons.sh`: Bash utility to resize the high-resolution logo JPEG into standard macOS dimensions.
- `build_app.sh`: Automated Swift compiler wrapper to compile all Swift files, generate appropriate `Info.plist` entries, and bundle them into the standalone `Neurolytics.app`.
- `QuotaModels.swift`: Unified data structures representing limits, model groups, and provider snapshots.
- `KeychainHelper.swift`: Secure macOS system Keychain reader and writer.
- `APIClients.swift`: Concurrent async HTTP clients connecting to Anthropic, Google CloudCode, OpenAI ChatGPT backend, and Devin Cognition APIs.
- `QuotaManager.swift`: Coordinator class managing DispatchGroup fetches, standard user defaults (themes, alerts), and local JSON cache mapping (`~/.config/neurolytics/cache.json`).
- `OAuthHelper.swift`: Fully-integrated local loopback socket server on port 54321 handling native PKCE browser redirects.
- `ContentView.swift`: SwiftUI layout featuring your custom, clean, gradient horizontal progress bars, percentage indicators, and countdown labels.
- `SettingsView.swift`: Modular TabView managing connected providers, Light/Dark/System themes, status item visibility, and the About section credited to Patrick Weed.
- `NeurolyticsApp.swift`: macOS main App entry point and delegate handling StatusItem pops, NSPopovers, and Settings Window actions.
- `NeurolyticsWidget.swift`: Standalone WidgetKit desktop/notification extension target displaying progress pills.

---

## 🚀 Building & Packaging

Compiling Neurolytics on any macOS Sequoia or Sonoma machine with Swift/Xcode Command Line Tools installed is incredibly simple:

1. Open your terminal in this repository.
2. If you want to regenerate the icon bundle from a custom source image, run:
   ```bash
   ./generate_icons.sh
   ```
3. Compile the standalone app bundle:
   ```bash
   ./build_app.sh
   ```
4. **Success!** Your completed native app bundle is compiled at:
   `build/Neurolytics.app`

---

## ⚡ How Connection & Auth Works

Each provider supports a **Dual-Mode** connection design:

### 1. Claude Code
- **Auto-Detect:** If you are already logged in to Claude Code, Neurolytics will silently extract the OAuth token from your macOS Keychain (service `Claude Code-credentials` under your active `$USER` account).
- **On-Demand:** If Claude Code is missing, simply click **Connect** in the Providers Tab. It starts our local socket listener, opens your default browser to `claude.com/cai/oauth/authorize`, and natively completes the PKCE handshake upon authorization—storing the token securely.

### 2. Antigravity CLI (Gemini)
- **Auto-Detect:** If you use Antigravity, Neurolytics automatically loads credentials from `~/.codexbar/antigravity/oauth_creds.json`.
- **On-Demand:** Click **Connect** in Settings and paste your Google Developer Account access token to connect natively.

### 3. ChatGPT (Codex)
- **Auto-Detect:** Neurolytics automatically reads your OpenAI session token from `~/.codex/auth.json`.
- **On-Demand:** Click **Connect** and paste your Web Session access token. Neurolytics includes a built-in JWT parser that dynamically extracts your proper `ChatGPT-Account-Id` from your token payload!

### 4. Devin CLI
- **Auto-Detect:** Reads `DEVIN_API_KEY` from your environment variables or `~/.config/devin/config.json`.
- **On-Demand:** Paste your Cognition Service User API key (starts with `cog_`) directly into Settings.

---

## 🎨 Settings & Customization
- **Theme Selection:** Set the interface to **Light Mode**, **Dark Mode**, or let it copy your macOS system state dynamically (default).
- **Toolbar Optional:** Toggle `"Show in toolbar"`. If unchecked, Neurolytics runs silently in the background, feeding the Desktop Widget and open settings windows without cluttering your Mac's Menu Bar.
- **Warning Indicator:** Set your warning slider (default 85%). If your remaining quota dips below this, progress bars glow red to alert you!
