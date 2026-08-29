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
    @State private var authErrorMessage: String = ""
    @State private var isAuthenticating: Bool = false
    
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
                    Button(action: { activeTab = tab }) {
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
                    }
                    .buttonStyle(.plain)
                    .focusable(false) // Disable keyboard focus highlight boxes (Feedback #2)
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
                providerRow(
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
                )
                
                // Antigravity Card
                providerRow(
                    id: "antigravity",
                    name: "Antigravity CLI (Gemini)",
                    subtitle: "Google Code Assist rolling daily/weekly quotas",
                    icon: "sparkles",
                    color: .purple,
                    connectAction: {
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
                )
                
                // ChatGPT Card
                providerRow(
                    id: "chatgpt",
                    name: "ChatGPT (Codex)",
                    subtitle: "OpenAI ChatGPT Plus/Pro session rate limits",
                    icon: "text.bubble",
                    color: .teal,
                    connectAction: {
                        // Open ChatGPT natively in the user's browser (Feedback #5)
                        if let url = URL(string: "https://chatgpt.com") {
                            NSWorkspace.shared.open(url)
                        }
                        selectedProviderForToken = "chatgpt"
                        tokenInput = manager.getManualToken(for: "chatgpt") ?? ""
                        authErrorMessage = "Opened ChatGPT in your default browser. Please log in, copy your session token, and paste it below."
                        showTokenSheet = true
                    }
                )
                
                // Devin Card
                providerRow(
                    id: "devin",
                    name: "Devin (Cognition)",
                    subtitle: "Devin autonomous agent daily/monthly billing spent",
                    icon: "square.grid.3x1.below.line.grid.1x2",
                    color: .indigo,
                    connectAction: {
                        // Open Devin settings natively in the user's browser (Feedback #5)
                        if let url = URL(string: "https://devin.ai/settings") {
                            NSWorkspace.shared.open(url)
                        }
                        selectedProviderForToken = "devin"
                        tokenInput = manager.getManualToken(for: "devin") ?? ""
                        devinOrgInput = UserDefaults.standard.string(forKey: "DevinOrgId") ?? ""
                        authErrorMessage = "Opened Devin Settings in your browser. Generate or copy your API Key and paste it below."
                        showTokenSheet = true
                    }
                )
            }
        }
    }
    
    private func providerRow(
        id: String,
        name: String,
        subtitle: String,
        icon: String,
        color: Color,
        connectAction: @escaping () -> Void
    ) -> some View {
        let isEnabled = manager.isProviderEnabled(id)
        let isConnected = manager.snapshots.first(where: { $0.provider == id })?.status == "ok"
        
        return HStack(spacing: 12) {
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
            
            // Connect Button
            Button(action: connectAction) {
                Text(isConnected ? "Connected" : "Connect")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(isConnected ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                    .foregroundColor(isConnected ? .green : .blue)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .disabled(isAuthenticating)
            
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
        }
        .padding(10)
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
            
            if selectedProviderForToken == "devin" {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Organization ID (Optional)")
                        .font(.system(size: 10, weight: .bold))
                    TextField("your_org_id (starts with org-)", text: $devinOrgInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10))
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
                    showTokenSheet = false
                }
                .buttonStyle(.bordered)
                
                Button("Save and Connect") {
                    manager.setManualToken(for: selectedProviderForToken, token: tokenInput)
                    if selectedProviderForToken == "devin" {
                        UserDefaults.standard.set(devinOrgInput, forKey: "DevinOrgId")
                    }
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
