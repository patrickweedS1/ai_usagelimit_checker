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
    
    private init() {
        let homeDir = NSHomeDirectory()
        self.configFolder = URL(fileURLWithPath: homeDir).appendingPathComponent(".config/neurolytics")
        self.cacheURL = configFolder.appendingPathComponent("cache.json")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: configFolder, withIntermediateDirectories: true, attributes: nil)
        
        // Proactively mirror cache to widget sandbox container on initialization
        let widgetConfigFolder = URL(fileURLWithPath: homeDir)
            .appendingPathComponent("Library/Containers/com.patrickweed.neurolytics.widget/Data/.config/neurolytics")
        try? FileManager.default.createDirectory(at: widgetConfigFolder, withIntermediateDirectories: true, attributes: nil)
        
        let widgetCacheURL = widgetConfigFolder.appendingPathComponent("cache.json")
        if FileManager.default.fileExists(atPath: cacheURL.path) && !FileManager.default.fileExists(atPath: widgetCacheURL.path) {
            try? FileManager.default.copyItem(at: cacheURL, to: widgetCacheURL)
        }
        
        // Load cached snapshots on startup
        loadCachedSnapshots()
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
        return provider == "claude"
    }
    
    public func setProviderEnabled(_ provider: String, enabled: Bool) {
        // Only Claude is supported now
    }
    
    public func getManualToken(for provider: String) -> String? {
        guard provider == "claude" else { return nil }
        return KeychainHelper.shared.readPassword(service: "Neurolytics-\(provider)", account: "token")
    }
    
    public func setManualToken(for provider: String, token: String) {
        guard provider == "claude" else { return }
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
        
        let token = getManualToken(for: "claude")
        ClaudeClient.fetchUsage(manualToken: token) { snapshot in
            DispatchQueue.main.async {
                let newSnapshots = [snapshot]
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
}
