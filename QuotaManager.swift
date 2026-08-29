//
//  QuotaManager.swift
//  Neurolytics
//
//  Created by Devin
//  Co-Authored by Patrick Weed
//

import Foundation
import WidgetKit

public class QuotaManager: ObservableObject {
    public static let shared = QuotaManager()
    
    @Published var snapshots: [ProviderSnapshot] = []
    @Published var isRefreshing: Bool = false
    @Published var lastRefreshed: Date? = nil
    
    private let cacheURL: URL
    private let configFolder: URL
    private let preferencesURL: URL
    
    @Published var visiblePreferences: [String: Bool] = [:]
    
    private init() {
        let homeDir = NSHomeDirectory()
        self.configFolder = URL(fileURLWithPath: homeDir).appendingPathComponent(".config/neurolytics")
        self.cacheURL = configFolder.appendingPathComponent("cache.json")
        self.preferencesURL = configFolder.appendingPathComponent("preferences.json")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: configFolder, withIntermediateDirectories: true, attributes: nil)
        
        // Proactively mirror cache and preferences to widget sandbox container on initialization
        let widgetConfigFolder = URL(fileURLWithPath: homeDir)
            .appendingPathComponent("Library/Containers/com.patrickweed.neurolytics.widget/Data/.config/neurolytics")
        try? FileManager.default.createDirectory(at: widgetConfigFolder, withIntermediateDirectories: true, attributes: nil)
        
        let widgetCacheURL = widgetConfigFolder.appendingPathComponent("cache.json")
        if FileManager.default.fileExists(atPath: cacheURL.path) && !FileManager.default.fileExists(atPath: widgetCacheURL.path) {
            try? FileManager.default.copyItem(at: cacheURL, to: widgetCacheURL)
        }
        
        let widgetPrefsURL = widgetConfigFolder.appendingPathComponent("preferences.json")
        if FileManager.default.fileExists(atPath: preferencesURL.path) && !FileManager.default.fileExists(atPath: widgetPrefsURL.path) {
            try? FileManager.default.copyItem(at: preferencesURL, to: widgetPrefsURL)
        }
        
        // Load cached snapshots on startup
        loadCachedSnapshots()
        loadPreferences()
    }
    
    // MARK: - Local Cache Management
    
    public func loadCachedSnapshots() {
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([ProviderSnapshot].self, from: data) else {
            return
        }
        DispatchQueue.main.async {
            self.snapshots = decoded
            if let latestFetch = decoded.map({ $0.fetchedAt }).max() {
                self.lastRefreshed = latestFetch
            }
        }
    }
    
    public func saveSnapshotsToCache(_ snapshots: [ProviderSnapshot]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(snapshots) else { return }
        
        // 1. Save to main app cache
        try? data.write(to: cacheURL)
        
        // 2. Mirror to widget's sandboxed container so the widget can access it
        let homeDir = NSHomeDirectory()
        let widgetConfigFolder = URL(fileURLWithPath: homeDir)
            .appendingPathComponent("Library/Containers/com.patrickweed.neurolytics.widget/Data/.config/neurolytics")
        
        try? FileManager.default.createDirectory(at: widgetConfigFolder, withIntermediateDirectories: true, attributes: nil)
        let widgetCacheURL = widgetConfigFolder.appendingPathComponent("cache.json")
        try? data.write(to: widgetCacheURL)
        
        // 3. Trigger a reload of all Widget timelines
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    public func loadPreferences() {
        if let data = try? Data(contentsOf: preferencesURL),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            DispatchQueue.main.async {
                self.visiblePreferences = decoded
            }
        } else {
            let defaults = [
                "claude-5h": true,
                "claude-weekly": true,
                "claude-extra": true,
                "antigravity-5h": true,
                "antigravity-weekly": true
            ]
            self.visiblePreferences = defaults
            savePreferences(defaults)
        }
    }
    
    public func savePreferences(_ prefs: [String: Bool]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(prefs) {
            try? data.write(to: preferencesURL)
            
            let homeDir = NSHomeDirectory()
            let widgetConfigFolder = URL(fileURLWithPath: homeDir)
                .appendingPathComponent("Library/Containers/com.patrickweed.neurolytics.widget/Data/.config/neurolytics")
            try? FileManager.default.createDirectory(at: widgetConfigFolder, withIntermediateDirectories: true, attributes: nil)
            let widgetPrefsURL = widgetConfigFolder.appendingPathComponent("preferences.json")
            try? data.write(to: widgetPrefsURL)
        }
        
        DispatchQueue.main.async {
            self.visiblePreferences = prefs
            self.objectWillChange.send()
        }
        
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    public func isBucketTypeVisible(provider: String, type: String) -> Bool {
        return visiblePreferences["\(provider)-\(type)"] ?? true
    }
    
    public func setBucketTypeVisible(provider: String, type: String, visible: Bool) {
        var prefs = visiblePreferences
        prefs["\(provider)-\(type)"] = visible
        savePreferences(prefs)
    }
    
    public func getBucketType(provider: String, bucketId: String) -> String {
        let bId = bucketId.lowercased()
        if provider == "claude" {
            if bId.contains("session") || bId.contains("5h") {
                return "5h"
            } else if bId.contains("weekly") {
                return "weekly"
            } else if bId.contains("extra") {
                return "extra"
            }
        } else if provider == "antigravity" {
            if bId.contains("five_hour") || bId.contains("session") || bId.contains("5h") || bId.contains("five-hour") {
                return "5h"
            } else if bId.contains("weekly") {
                return "weekly"
            }
        }
        return "other"
    }
    
    public func isBucketVisible(provider: String, bucketId: String) -> Bool {
        let type = getBucketType(provider: provider, bucketId: bucketId)
        if type == "other" { return true }
        return visiblePreferences["\(provider)-\(type)"] ?? true
    }
    
    // MARK: - Preferences & Settings Accessors
    
    public var themePreference: String {
        get { UserDefaults.standard.string(forKey: "ThemePreference") ?? "system" }
        set { 
            UserDefaults.standard.set(newValue, forKey: "ThemePreference")
            objectWillChange.send()
        }
    }
    
    public var showInToolbar: Bool {
        get { UserDefaults.standard.object(forKey: "ShowInToolbar") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "ShowInToolbar")
            objectWillChange.send()
            NotificationCenter.default.post(name: Notification.Name("ShowInToolbarChanged"), object: nil)
        }
    }
    
    public var warningThreshold: Double {
        get { UserDefaults.standard.double(forKey: "WarningThreshold") == 0 ? 85.0 : UserDefaults.standard.double(forKey: "WarningThreshold") }
        set {
            UserDefaults.standard.set(newValue, forKey: "WarningThreshold")
            objectWillChange.send()
        }
    }
    
    public func isProviderEnabled(_ provider: String) -> Bool {
        let enabled = UserDefaults.standard.array(forKey: "EnabledProviders") as? [String] ?? ["claude", "antigravity"]
        return enabled.contains(provider)
    }
    
    public func setProviderEnabled(_ provider: String, enabled: Bool) {
        var list = UserDefaults.standard.array(forKey: "EnabledProviders") as? [String] ?? ["claude", "antigravity"]
        if enabled && !list.contains(provider) {
            list.append(provider)
        } else if !enabled && list.contains(provider) {
            list.removeAll { $0 == provider }
        }
        UserDefaults.standard.set(list, forKey: "EnabledProviders")
        objectWillChange.send()
    }
    
    public func getManualToken(for provider: String) -> String? {
        guard provider == "claude" || provider == "antigravity" else { return nil }
        return KeychainHelper.shared.readPassword(service: "Neurolytics-\(provider)", account: "token")
    }
    
    public func setManualToken(for provider: String, token: String) {
        guard provider == "claude" || provider == "antigravity" else { return }
        if token.isEmpty {
            KeychainHelper.shared.deletePassword(service: "Neurolytics-\(provider)", account: "token")
        } else {
            KeychainHelper.shared.savePassword(service: "Neurolytics-\(provider)", account: "token", passwordString: token)
        }
        objectWillChange.send()
    }
    
    // MARK: - Dynamic Async Concurrent Quota Fetching
    
    public func refreshAll(completion: (([ProviderSnapshot]) -> Void)? = nil) {
        guard !isRefreshing else { return }
        
        DispatchQueue.main.async {
            self.isRefreshing = true
        }
        
        let dispatchGroup = DispatchGroup()
        var newSnapshots: [ProviderSnapshot] = []
        let snapshotQueue = DispatchQueue(label: "com.neurolytics.snapshots.sync")
        
        // 1. Claude Code
        if isProviderEnabled("claude") {
            dispatchGroup.enter()
            let token = getManualToken(for: "claude")
            ClaudeClient.fetchUsage(manualToken: token) { snapshot in
                snapshotQueue.async {
                    newSnapshots.append(snapshot)
                    dispatchGroup.leave()
                }
            }
        }
        
        // 2. Antigravity
        if isProviderEnabled("antigravity") {
            dispatchGroup.enter()
            let token = getManualToken(for: "antigravity")
            AntigravityClient.fetchUsage(manualToken: token) { snapshot in
                snapshotQueue.async {
                    newSnapshots.append(snapshot)
                    dispatchGroup.leave()
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            let order = ["claude", "antigravity"]
            newSnapshots.sort { (a, b) -> Bool in
                let idxA = order.firstIndex(of: a.provider) ?? 99
                let idxB = order.firstIndex(of: b.provider) ?? 99
                return idxA < idxB
            }
            
            self.snapshots = newSnapshots
            self.isRefreshing = false
            self.lastRefreshed = Date()
            
            // Save to JSON cache
            self.saveSnapshotsToCache(newSnapshots)
            
            // Notify widget to refresh if possible
            NotificationCenter.default.post(name: Notification.Name("QuotaRefreshed"), object: nil)
            
            completion?(newSnapshots)
        }
    }
}
