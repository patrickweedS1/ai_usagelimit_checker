# 🧠 Neurolytics — AI Monitoring App

A native macOS menu bar status item, standalone application window, and desktop widget to monitor real-time AI usage limits for:
1. **Claude (Claude Code / Anthropic)**

---

## 📂 Project Structure

- `generate_icons.sh`: Bash utility to resize the high-resolution logo JPEG into standard macOS dimensions.
- `build_app.sh`: Automated Swift compiler wrapper to compile all Swift files, generate appropriate `Info.plist` entries, and bundle them into the standalone `Neurolytics.app`.
- `QuotaModels.swift`: Unified data structures representing limits, model groups, and provider snapshots.
- `KeychainHelper.swift`: Secure macOS system Keychain reader and writer.
- `APIClients.swift`: Concurrent async HTTP client connecting to the Anthropic API.
- `QuotaManager.swift`: Coordinator class managing fetches, standard user defaults (themes, alerts), and local JSON cache mapping (`~/.config/neurolytics/cache.json`).
- `OAuthHelper.swift`: Fully-integrated local loopback socket server on port 54321 handling native PKCE browser redirects.
- `ContentView.swift`: SwiftUI layout featuring your custom, clean, gradient horizontal progress bars, percentage indicators, and countdown labels.
- `SettingsView.swift`: Modular TabView managing the Claude provider connection, Light/Dark/System themes, status item visibility, and the About section credited to Patrick Weed.
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

Support for Claude Code **Dual-Mode** connection design:

### 1. Claude Code
- **Auto-Detect:** If you are already logged in to Claude Code, Neurolytics will silently extract the OAuth token from your macOS Keychain (service `Claude Code-credentials` under your active `$USER` account).
- **On-Demand:** If Claude Code is missing, simply click **Connect** in the Providers Tab. It starts our local socket listener, opens your default browser to `claude.com/cai/oauth/authorize`, and natively completes the PKCE handshake upon authorization—storing the token securely.

---

## 🎨 Settings & Customization
- **Theme Selection:** Set the interface to **Light Mode**, **Dark Mode**, or let it copy your macOS system state dynamically (default).
- **Toolbar Optional:** Toggle `"Show in toolbar"`. If unchecked, Neurolytics runs silently in the background, feeding the Desktop Widget and open settings windows without cluttering your Mac's Menu Bar.
- **Warning Indicator:** Set your warning slider (default 85%). If your remaining quota dips below this, progress bars glow red to alert you!

---

## 📥 AirDrop / Gatekeeper Quarantine ("App is Damaged")

When you build a native, unsigned macOS `.app` bundle on one Mac and send it over **AirDrop, Slack, or Email** to another Mac, macOS's security layer (Gatekeeper) automatically attaches an extended attribute called a **quarantine flag** to the bundle.

On the receiving Mac, when you double-click the app, macOS will display an alarm: 
> **"Neurolytics" is damaged and can't be opened. You should move it to the Trash.**

### **The 5-Second Fix:**
This is completely normal for local, unsigned developer app bundles. You simply need to clear the quarantine flag in your terminal on the receiving Mac:

1. Open your terminal on your personal laptop.
2. Run this single command (replace with your actual folder path where you dropped the app, e.g. `~/Downloads` or `/Applications`):
   ```bash
   xattr -rd com.apple.quarantine /Applications/Neurolytics.app
   ```
3. **Success!** Double-click the app, and it will open and run natively and beautifully!

---

## 📦 Easy Distribution (No Quarantine Bypasses Needed)

If you want to share Neurolytics with friends or colleagues without forcing them to manually run any terminal commands or bypass the macOS Gatekeeper blocks in System Settings, you can distribute the app via an **auto-installer script using `curl`**.

Because macOS's browser/download layer does not attach the `com.apple.quarantine` extended attribute to files downloaded via terminal command-line clients like `curl`, downloading and extracting the app through `curl` allows users to double-click and run the app immediately upon installation.

### How to Package & Share:

1. **Build and Package the App:**
   Run the packaging script in this directory. This script compiles the app, applies an ad-hoc signature (mandatory for modern macOS), and compresses the app into a secure ZIP using `ditto`:
   ```bash
   ./package_app.sh
   ```
   This generates:
   - `build/Neurolytics.app`
   - `build/Neurolytics.zip`

2. **Host the ZIP and the Installer:**
   Upload both `build/Neurolytics.zip` and `install.sh` to your web server, an S3 bucket, or your project's GitHub Releases page.

3. **Update the Installer Configuration:**
   Open `install.sh` and set `DEFAULT_DOWNLOAD_URL` to point to where you are hosting `Neurolytics.zip` on the web.

4. **Share the Installation Command:**
   Provide others with a single command to run in their Terminal:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/patrickweedS1/ai_usagelimit_checker/main/install.sh | bash
   ```
   *(Alternatively, users can override the zip URL dynamically without modifying the script):*
   ```bash
   curl -fsSL https://raw.githubusercontent.com/patrickweedS1/ai_usagelimit_checker/main/install.sh | NEUROLYTICS_ZIP_URL="https://example.com/Neurolytics.zip" bash
   ```

Upon completion, the app is moved directly to their `/Applications` (or user-specific `~/Applications` as fallback) folder and can be launched directly via double-click or Spotlight without any security warnings!


---

## ⚡ Google Antigravity Support (Experimental Branch)

In the `feature/antigravity` branch, we have restored robust support for side-by-side monitoring of **Google Antigravity**:

### How Connection & Auth Works (Antigravity):
1. **Auto-Detect:** Neurolytics will automatically seek active local Antigravity credentials in:
   - Your local `.codexbar/antigravity/oauth_creds.json` configuration file.
   - Your macOS Keychain (service `"gemini"`, account `"antigravity"` or service `"Antigravity Safe Storage"`).
2. **On-Demand:** If local credentials are not found, clicking **Connect** in Settings starts our local loopback server on port `51121` (whitelisted for Google OAuth redirects) and initiates a Google PKCE authorization flow using public plugin credentials.
3. **Automatic Token Refreshing:** Google OAuth access tokens are valid for 1 hour. The application automatically refreshes your token in the background using the secure refresh token, ensuring continuous and seamless updates.



