//
//  SettingsView.swift
//  Neurolytics
//
//  Created by Devin
//  Co-Authored by Patrick Weed
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var manager = QuotaManager.shared
    @State private var activeTab: SettingsTab = .providers
    
    // Manual token input sheets states
    @State private var showTokenSheet: Bool = false
    @State private var selectedProviderForToken: String = ""
    @State private var tokenInput: String = ""
    @State private var devinOrgInput: String = ""
    @State private var devinHostInput: String = ""
    @State private var authErrorMessage: String = ""
    @State private var isAuthenticating: Bool = false
    
    // Google OAuth Custom Client States
    @State private var showGoogleCredentialsSheet: Bool = false
    @State private var googleClientIdInput: String = ""
    @State private var googleClientSecretInput: String = ""
    
    enum SettingsTab: String, CaseIterable, Identifiable {
        case providers = "Providers"
        case general = "General"
        case about = "About"
        
        var id: String { self.rawValue }
        
        var icon: String {
            switch self {
            case .providers: return "app.badge"
            case .general: return "gearshape"
            case .about: return "info.circle"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Segmented tab selector
            HStack(spacing: 12) {
                ForEach(SettingsTab.allCases) { tab in
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16))
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: activeTab == tab ? .semibold : .regular))
                    }
                    .foregroundColor(activeTab == tab ? .blue : .primary.opacity(0.7))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle()) // Make the entire padded box area clickable (Feedback #1)
                    .background(activeTab == tab ? Color.blue.opacity(0.08) : Color.clear)
                    .cornerRadius(6)
                    .onTapGesture {
                        activeTab = tab
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 6)
            
            Divider()
            
            // Tab content box
            ScrollView {
                VStack {
                    switch activeTab {
                    case .providers:
                        providersTab
                    case .general:
                        generalTab
                    case .about:
                        aboutTab
                    }
                }
                .padding(20)
            }
            .frame(width: 480, height: 350)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .preferredColorScheme(
            manager.themePreference == "light" ? .light :
            manager.themePreference == "dark" ? .dark :
            nil
        )
        .sheet(isPresented: $showTokenSheet) {
            tokenConfigurationSheet
        }
        .sheet(isPresented: $showGoogleCredentialsSheet) {
            googleCredentialsConfigurationSheet
        }
    }
    
    // MARK: - Providers Tab
    
    private var providersTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Providers & Quota Connections")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.gray)
                .padding(.bottom, 4)
            
            VStack(spacing: 12) {
                // Claude Card
                providerCard(
                    id: "claude",
                    name: "Claude Code",
                    subtitle: "Anthropic's CLI & API usage limits",
                    icon: "brain.head.profile",
                    color: .orange,
                    connectAction: {
                        isAuthenticating = true
                        authErrorMessage = ""
                        OAuthHelper.shared.startClaudeLoginFlow { result in
                            DispatchQueue.main.async {
                                self.isAuthenticating = false
                                switch result {
                                case .success:
                                    self.manager.setProviderEnabled("claude", enabled: true)
                                    self.manager.refreshAll()
                                case .failure(let error):
                                    self.authErrorMessage = error.localizedDescription
                                    self.selectedProviderForToken = "claude"
                                    self.tokenInput = ""
                                    self.showTokenSheet = true
                                }
                            }
                        }
                    }
                ) {
                    let isClaudeConnected = manager.snapshots.first(where: { $0.provider == "claude" })?.status == "ok"
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Divider()
                            .padding(.horizontal, 10)
                            .padding(.bottom, 6)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LIMIT OPTIONS TO DISPLAY:")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.secondary)
                                .tracking(0.5)
                            
                            HStack(spacing: 12) {
                                Toggle("Overage Credits", isOn: Binding(
                                    get: { self.manager.isBucketTypeVisible(provider: "claude", type: "extra") },
                                    set: { self.manager.setBucketTypeVisible(provider: "claude", type: "extra", visible: $0) }
                                ))
                                .disabled(!isClaudeConnected)
                            }
                            .toggleStyle(.checkbox)
                            .font(.system(size: 9.5))
                            .foregroundColor(isClaudeConnected ? .primary : .secondary.opacity(0.4))
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
                }
                
                // Antigravity Card
                providerCard(
                    id: "antigravity",
                    name: "Antigravity",
                    subtitle: "Google's AI IDE & API usage limits",
                    icon: "sparkles",
                    color: .purple,
                    connectAction: {
                        googleClientIdInput = manager.googleClientId
                        googleClientSecretInput = manager.googleClientSecret
                        authErrorMessage = ""
                        showGoogleCredentialsSheet = true
                    }
                ) {
                    let isAntigravityConnected = manager.snapshots.first(where: { $0.provider == "antigravity" })?.status == "ok"
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Divider()
                            .padding(.horizontal, 10)
                            .padding(.bottom, 6)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("GEMINI MODELS LIMITS:")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .tracking(0.5)
                                
                                HStack(spacing: 12) {
                                    Toggle("5-Hour Limit", isOn: Binding(
                                        get: { self.manager.isBucketTypeVisible(provider: "antigravity", type: "gemini-5h") },
                                        set: { self.manager.setBucketTypeVisible(provider: "antigravity", type: "gemini-5h", visible: $0) }
                                    ))
                                    .disabled(!isAntigravityConnected)
                                    
                                    Toggle("Weekly Limit", isOn: Binding(
                                        get: { self.manager.isBucketTypeVisible(provider: "antigravity", type: "gemini-weekly") },
                                        set: { self.manager.setBucketTypeVisible(provider: "antigravity", type: "gemini-weekly", visible: $0) }
                                    ))
                                    .disabled(!isAntigravityConnected)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("CLAUDE & GPT MODELS LIMITS:")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .tracking(0.5)
                                
                                HStack(spacing: 12) {
                                    Toggle("5-Hour Limit", isOn: Binding(
                                        get: { self.manager.isBucketTypeVisible(provider: "antigravity", type: "claude-5h") },
                                        set: { self.manager.setBucketTypeVisible(provider: "antigravity", type: "claude-5h", visible: $0) }
                                    ))
                                    .disabled(!isAntigravityConnected)
                                    
                                    Toggle("Weekly Limit", isOn: Binding(
                                        get: { self.manager.isBucketTypeVisible(provider: "antigravity", type: "claude-weekly") },
                                        set: { self.manager.setBucketTypeVisible(provider: "antigravity", type: "claude-weekly", visible: $0) }
                                    ))
                                    .disabled(!isAntigravityConnected)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .font(.system(size: 9.5))
                        .foregroundColor(isAntigravityConnected ? .primary : .secondary.opacity(0.4))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    }
                }
            }
        }
    }
    
    private func providerCard<Content: View>(
        id: String,
        name: String,
        subtitle: String,
        icon: String,
        color: Color,
        connectAction: @escaping () -> Void,
        @ViewBuilder extraContent: @escaping () -> Content
    ) -> some View {
        let isEnabled = manager.isProviderEnabled(id)
        let isConnected = manager.snapshots.first(where: { $0.provider == id })?.status == "ok"
        
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(color)
                }
                
                // Text Details
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 12, weight: .bold))
                        
                        if isConnected && isEnabled {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 10))
                        }
                    }
                    
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Connect Button styled with TapGesture to resolve SwiftUI row-clamping & focus ring bugs (Feedback #2 & #5)
                Text(isConnected ? "Connected" : "Connect")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(isConnected ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                    .foregroundColor(isConnected ? .green : .blue)
                    .cornerRadius(4)
                    .contentShape(Rectangle()) // Make the entire capsule area clickable
                    .onTapGesture {
                        if !isAuthenticating {
                            connectAction()
                        }
                    }
                
                // Toggle Switch
                Toggle("", isOn: Binding(
                    get: { self.manager.isProviderEnabled(id) },
                    set: { 
                        self.manager.setProviderEnabled(id, enabled: $0)
                        self.manager.refreshAll()
                    }
                ))
                .toggleStyle(.switch)
                .scaleEffect(0.7)
                .frame(width: 40)
                .buttonStyle(.borderless) // Borderless prevents conflict with tap gestures in the same HStack (Feedback #2)
            }
            .padding(10)
            
            extraContent()
        }
        .background(Color(NSColor.alternatingContentBackgroundColors[0]))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Application Preferences")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.gray)
                .padding(.bottom, 4)
            
            // 1. Theme Configuration
            VStack(alignment: .leading, spacing: 6) {
                Text("App Theme Mode")
                    .font(.system(size: 11, weight: .bold))
                
                Picker("", selection: Binding(
                    get: { self.manager.themePreference },
                    set: { self.manager.themePreference = $0 }
                )) {
                    Text("System Settings").tag("system")
                    Text("Light Mode").tag("light")
                    Text("Dark Mode").tag("dark")
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGrouping() // Modern layout helper
                .padding(.leading, -8)
            }
            
            Divider()
            
            // 2. Toolbar Option
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Menu Bar Integration")
                        .font(.system(size: 11, weight: .bold))
                    Text("Display Neurolytics capsule gauges directly in your macOS Menu Bar")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { self.manager.showInToolbar },
                    set: { self.manager.showInToolbar = $0 }
                ))
                .toggleStyle(.switch)
                .scaleEffect(0.8)
            }
            
            Divider()
            
            // 3. Warning Threshold slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Quota Alert Warning Threshold")
                        .font(.system(size: 11, weight: .bold))
                    Spacer()
                    Text("\(Int(manager.warningThreshold))% used")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.red)
                }
                Text("Highlights progress bars in red/orange when remaining limits run low")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                
                Slider(value: Binding(
                    get: { self.manager.warningThreshold },
                    set: { self.manager.warningThreshold = $0 }
                ), in: 50...95, step: 5)
            }
        }
    }
    
    // MARK: - About Tab
    
    private var aboutTab: some View {
        VStack(spacing: 12) {
            // Load app logo beautifully
            if let imageURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let image = NSImage(contentsOf: imageURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .shadow(radius: 4)
            } else {
                // Swift fallback logo drawing if icns isn't compiled yet in test
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 80, height: 80)
                        .shadow(radius: 4)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                }
            }
            
            Text("NEUROLYTICS")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .tracking(2)
            
            Text("AI MONITORING APP")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.blue)
                .padding(.top, -6)
            
            Text("Version 1.0 (Build 100)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            Divider()
                .frame(width: 200)
                .padding(.vertical, 4)
            
            Text("A professional, serverless dashboard to monitor rolling 5-hour, weekly, and daily usage limits for AI developers in real-time.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 30)
            
            Spacer()
            
            VStack(spacing: 2) {
                Text("Created by Patrick Weed")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary.opacity(0.8))
                
                Text("Copyright © 2026 Neurolytics. All rights reserved.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Manual Token Inputs Sheet
    
    private var tokenConfigurationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure \(selectedProviderForToken.capitalized) Token")
                .font(.system(size: 14, weight: .bold))
            
            Text("Paste your manual Authorization / Session Bearer token below. This token remains locally encrypted in your macOS system Keychain.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineSpacing(1.5)
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Bearer Token / API Key")
                    .font(.system(size: 10, weight: .bold))
                
                TextEditor(text: $tokenInput)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(height: 70)
                    .border(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
            
            if !authErrorMessage.isEmpty {
                Text(authErrorMessage)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
            
            HStack {
                Spacer()
                
                Button("Cancel") {
                    showTokenSheet = false
                }
                .buttonStyle(.bordered)
                
                Button("Save and Connect") {
                    manager.setManualToken(for: selectedProviderForToken, token: tokenInput)
                    manager.setProviderEnabled(selectedProviderForToken, enabled: true)
                    manager.refreshAll()
                    showTokenSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
    
    // MARK: - Custom Google Credentials Input Sheet
    
    private var googleCredentialsConfigurationSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Google OAuth Client Setup")
                .font(.system(size: 14, weight: .bold))
            
            Text("To monitor your Antigravity quotas, please provide your own custom Google Cloud Platform OAuth credentials. You can create a 'Desktop Application' OAuth Client in the Google Cloud Console, enable the Cloud Code API, and paste the values below:")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineSpacing(1.5)
            
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OAuth Client ID")
                        .font(.system(size: 10, weight: .bold))
                    
                    TextField("Enter Google Client ID", text: $googleClientIdInput)
                        .font(.system(size: 10, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("OAuth Client Secret")
                        .font(.system(size: 10, weight: .bold))
                    
                    SecureField("Enter Google Client Secret", text: $googleClientSecretInput)
                        .font(.system(size: 10, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            if !authErrorMessage.isEmpty {
                Text(authErrorMessage)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
            
            HStack {
                Spacer()
                
                Button("Cancel") {
                    showGoogleCredentialsSheet = false
                }
                .buttonStyle(.bordered)
                
                Button("Connect & Sign In") {
                    manager.googleClientId = googleClientIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    manager.googleClientSecret = googleClientSecretInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    showGoogleCredentialsSheet = false
                    
                    isAuthenticating = true
                    authErrorMessage = ""
                    OAuthHelper.shared.startGoogleLoginFlow { result in
                        DispatchQueue.main.async {
                            self.isAuthenticating = false
                            switch result {
                            case .success:
                                self.manager.setProviderEnabled("antigravity", enabled: true)
                                self.manager.refreshAll()
                            case .failure(let error):
                                self.authErrorMessage = error.localizedDescription
                                self.selectedProviderForToken = "antigravity"
                                self.tokenInput = ""
                                self.showTokenSheet = true
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(googleClientIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || googleClientSecretInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

// MARK: - Radio Group Layout Helper
public extension View {
    func horizontalRadioGrouping() -> some View {
        #if os(macOS)
        return self.pickerStyle(.radioGroup)
        #else
        return self
        #endif
    }
}
