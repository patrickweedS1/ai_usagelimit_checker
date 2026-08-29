//
//  NeurolyticsApp.swift
//  Neurolytics
//
//  Created by Devin
//  Co-Authored by Patrick Weed
//

import SwiftUI
import AppKit

@main
struct NeurolyticsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // We use a dummy Scene here since our app is primary managed as a status-bar popover and standalone preferences window.
        // This prevents macOS from creating an empty window on startup.
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var backgroundTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Initialise the Settings Popover containing our primary ContentView
        let contentView = ContentView()
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 450)
        popover.behavior = .transient // Closes automatically when clicking elsewhere
        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover
        
        // 2. Load cached quotas and run an initial concurrent sync on launch
        QuotaManager.shared.loadCachedSnapshots()
        QuotaManager.shared.refreshAll()
        
        // 3. Register Status Bar Item based on user preferences
        updateStatusItem()
        
        // 4. Register Notification observers for dynamic Preferences events
        NotificationCenter.default.addObserver(self, selector: #selector(onToolbarChanged), name: Notification.Name("ShowInToolbarChanged"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsWindowNotification), name: Notification.Name("OpenSettingsWindow"), object: nil)
        
        // 5. Setup background polling timer (default 15 minutes to respect rate limits)
        setupBackgroundTimer()
    }
    
    // MARK: - Status Bar Registration & Toggle
    
    @objc private func onToolbarChanged() {
        DispatchQueue.main.async {
            self.updateStatusItem()
        }
    }
    
    private func updateStatusItem() {
        if QuotaManager.shared.showInToolbar {
            if statusItem == nil {
                let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = statusItem.button {
                    // Use a clean template SF Symbol to support Light and Dark macOS menubars natively
                    button.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Neurolytics Quotas")
                    button.image?.isTemplate = true
                    
                    button.action = #selector(togglePopover(_:))
                    button.target = self
                }
                self.statusItem = statusItem
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            
            // If the toolbar is disabled, immediately open the Settings Window so the user isn't stranded!
            openSettingsWindow()
        }
    }
    
    // MARK: - Popover Actions
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if let popover = popover {
            if popover.isShown {
                popover.performClose(sender)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // Force popover window to be key so it captures keyboard events immediately
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }
    
    // MARK: - Standalone Settings Window Coordinator
    
    @objc private func openSettingsWindowNotification() {
        DispatchQueue.main.async {
            self.openSettingsWindow()
        }
    }
    
    private func openSettingsWindow() {
        // If settings window already exists, bring it to front
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Close popover if it's currently open
        popover?.performClose(nil)
        
        // Create standard App Window for Preferences
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Neurolytics Preferences"
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        // Host the SwiftUI SettingsView inside our window
        let settingsView = SettingsView()
        window.contentView = NSHostingView(rootView: settingsView)
        
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Background Sync Poller
    
    private func setupBackgroundTimer() {
        backgroundTimer?.invalidate()
        
        // Polls every 15 minutes (900 seconds)
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: 900.0, repeats: true) { _ in
            QuotaManager.shared.refreshAll()
        }
    }
}

// MARK: - App Window Delegate implementation
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Clean up settingsWindow reference when closed
        if let window = notification.object as? NSWindow, window == settingsWindow {
            settingsWindow = nil
        }
    }
}
