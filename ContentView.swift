//
//  ContentView.swift
//  Neurolytics
//
//  Created by Devin
//  Co-Authored by Patrick Weed
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var manager = QuotaManager.shared
    
    // Timer to update reset times descriptors dynamically every 10 seconds
    let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    @State private var forceUIUpdateToken = UUID()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Models & Quotas")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                
                Spacer()
                
                if manager.isRefreshing {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                } else {
                    Button(action: { manager.refreshAll() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false) // Disable focus highlight box (Feedback #2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
            
            Divider()
                .padding(.horizontal, 16)
            
            // Main content area
            if manager.snapshots.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(manager.snapshots) { snapshot in
                            if snapshot.status == "ok" {
                                providerQuotaCard(snapshot)
                            } else {
                                providerErrorCard(snapshot)
                            }
                        }
                    }
                    .padding(16)
                    .id(forceUIUpdateToken) // Re-renders list on timer tick
                }
                .frame(maxHeight: 450)
            }
            
            Divider()
            
            // Footer Control Toolbar
            HStack {
                if let lastRefreshed = manager.lastRefreshed {
                    Text("Synced \(timeAgoSince(lastRefreshed))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                } else {
                    Text("Not synced yet")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: openSettings) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                        Text("Settings")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .focusable(false) // Disable focus highlight box (Feedback #2)
                
                Button(action: quitApp) {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                        Text("Quit")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .focusable(false) // Disable focus highlight box (Feedback #2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.02))
        }
        .frame(width: 380)
        .preferredColorScheme(
            manager.themePreference == "light" ? .light :
            manager.themePreference == "dark" ? .dark :
            nil
        )
        .onReceive(timer) { _ in
            // Force a UI refresh to update "Refreshes in..." relative countdowns
            forceUIUpdateToken = UUID()
        }
    }
    
    // MARK: - Quota Card for Active Provider
    
    private func providerQuotaCard(_ snapshot: ProviderSnapshot) -> some View {
        let providerColor = colorForTheme(snapshot.themeColorName)
        
        return VStack(alignment: .leading, spacing: 14) {
            // Identity Header
            HStack(spacing: 6) {
                Circle()
                    .fill(providerColor)
                    .frame(width: 6, height: 6)
                
                Text(snapshot.provider.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(providerColor)
                
                Spacer()
                
                Text("Account: \(snapshot.accountName)")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            // Subsections for each Model Group
            ForEach(snapshot.groups) { group in
                let visibleBuckets = group.buckets.filter { manager.isBucketVisible(provider: snapshot.provider, bucketId: $0.bucketId) }
                
                if !visibleBuckets.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.displayName)
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .tracking(0.5)
                            
                            Text(group.description)
                                .font(.system(size: 8.5))
                                .foregroundColor(.secondary)
                        }
                        
                        // Buckets Progress Bars
                        VStack(spacing: 12) {
                            ForEach(visibleBuckets) { bucket in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bucket.displayName)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.primary.opacity(0.85))
                                    
                                    // Beautiful rounded pill progress bar
                                    HStack(spacing: 10) {
                                        CustomProgressBar(
                                            usedValue: bucket.usedPercent,
                                            warningThreshold: manager.warningThreshold,
                                            color: providerColor
                                        )
                                        
                                        Text("\(String(format: "%.2f", bucket.usedPercent))%")
                                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                            .frame(width: 54, alignment: .trailing)
                                    }
                                    
                                    // Metadata resetting description
                                    Text("\(String(format: "%.0f", bucket.usedPercent))% used · \(bucket.resetsAt?.relativeResetTimeDescription() ?? bucket.resetsDescription)")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.leading, 6)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.alternatingContentBackgroundColors[0]))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }
    
    // MARK: - Error Card for Offline Provider
    
    private func providerErrorCard(_ snapshot: ProviderSnapshot) -> some View {
        let providerColor = colorForTheme(snapshot.themeColorName)
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(snapshot.provider.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(providerColor.opacity(0.6))
                
                Spacer()
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.amber)
                    .font(.system(size: 10))
            }
            
            Text(snapshot.statusDetails ?? "Unknown Connection Error.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(3)
                .lineSpacing(1.5)
            
            Button(action: openSettings) {
                Text("Fix Connection")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(Color.amber.opacity(0.1))
                    .foregroundColor(.amber)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .padding(12)
        .background(Color(NSColor.alternatingContentBackgroundColors[0]))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.amber.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.top, 40)
            
            Text("No Active Quotas Connected")
                .font(.system(size: 13, weight: .bold))
            
            Text("Go to Settings to enable your Claude Code, Antigravity, ChatGPT, or Devin connections.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .lineSpacing(1.5)
            
            Button(action: openSettings) {
                Text("Open Settings")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 16)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Helpers
    
    private func colorForTheme(_ name: String) -> Color {
        switch name {
        case "orange": return .orange
        case "violet": return Color(red: 0.55, green: 0.25, blue: 0.95) // Custom Violet
        case "teal": return Color(red: 0.1, green: 0.72, blue: 0.65) // Custom Teal
        case "indigo": return .indigo
        default: return .blue
        }
    }
    
    private func timeAgoSince(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
    
    private func openSettings() {
        // Post notification to open preferences panel
        NotificationCenter.default.post(name: Notification.Name("OpenSettingsWindow"), object: nil)
    }
    
    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Custom Progress Bar

struct CustomProgressBar: View {
    let usedValue: Double // 0.0 - 100.0 (Used %)
    let warningThreshold: Double
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            let isOverThreshold = usedValue >= warningThreshold
            let fillColor = isOverThreshold ? Color.red : color
            
            ZStack(alignment: .leading) {
                // Background Track
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 12)
                
                // Active Fill
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(
                        colors: [fillColor, fillColor.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: CGFloat(usedValue / 100.0) * geo.size.width, height: 12)
                    .shadow(color: fillColor.opacity(0.15), radius: 1, x: 0, y: 1)
            }
        }
        .frame(height: 12)
    }
}

// Color asset helpers
public extension Color {
    static let amber = Color(red: 0.95, green: 0.6, blue: 0.1)
}
