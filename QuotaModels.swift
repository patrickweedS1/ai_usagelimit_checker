//
//  QuotaModels.swift
//  Neurolytics
//
//  Created by Devin
//  Co-Authored by Patrick Weed
//

import Foundation

/// Represents a single quota limit (e.g. 5-hour rolling, 7-day weekly, or model-scoped)
public struct QuotaBucket: Codable, Identifiable, Hashable {
    public var id: String { bucketId }
    public let bucketId: String              // Unique identifier (e.g., "gemini-weekly", "claude-5h")
    public let displayName: String           // e.g. "Weekly Limit Remaining", "Five Hour Limit Remaining"
    public let windowType: String            // "5h" | "weekly" | "monthly" | "other"
    public let usedPercent: Double           // 0.0 - 100.0 (Percent used)
    public let remainingPercent: Double      // 0.0 - 100.0 (Percent remaining)
    public let resetsAt: Date?               // Exact reset date
    public let resetsDescription: String     // Human-readable reset text (e.g. "Refreshes in 4h 21m" or "Quota available")
    
    public init(bucketId: String, displayName: String, windowType: String, usedPercent: Double, remainingPercent: Double, resetsAt: Date?, resetsDescription: String) {
        self.bucketId = bucketId
        self.displayName = displayName
        self.windowType = windowType
        self.usedPercent = usedPercent
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.resetsDescription = resetsDescription
    }
}

/// Represents a grouped set of models sharing limits (like Gemini Models, or Claude & GPT)
public struct ModelGroup: Codable, Identifiable, Hashable {
    public var id: String { displayName }
    public let displayName: String           // e.g. "GEMINI MODELS"
    public let description: String           // e.g. "Models within this group: Gemini Flash, Gemini Pro"
    public let buckets: [QuotaBucket]        // List of rolling limit buckets associated with this group
    
    public init(displayName: String, description: String, buckets: [QuotaBucket]) {
        self.displayName = displayName
        self.description = description
        self.buckets = buckets
    }
}

/// Represents the completed quota snapshot for a single provider
public struct ProviderSnapshot: Codable, Identifiable, Hashable {
    public var id: String { provider }
    public let provider: String              // "claude" | "antigravity" | "chatgpt" | "devin"
    public let themeColorName: String        // "orange" | "violet" | "teal" | "indigo"
    public let accountName: String           // Account email or identifier
    public let status: String                // "ok" | "auth_missing" | "error"
    public let statusDetails: String?        // Specific details on errors or warnings
    public let groups: [ModelGroup]          // Grouped sections
    public let fetchedAt: Date               // Last synced timestamp
    
    public init(provider: String, themeColorName: String, accountName: String, status: String, statusDetails: String?, groups: [ModelGroup], fetchedAt: Date) {
        self.provider = provider
        self.themeColorName = themeColorName
        self.accountName = accountName
        self.status = status
        self.statusDetails = statusDetails
        self.groups = groups
        self.fetchedAt = fetchedAt
    }
}

/// Helper extension to calculate remaining time descriptors dynamically
public extension Date {
    func relativeResetTimeDescription() -> String {
        let diff = self.timeIntervalSinceNow
        if diff <= 0 {
            return "Quota available"
        }
        
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        
        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "Refreshes in \(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "Refreshes in \(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "Refreshes in \(minutes)m"
        } else {
            return "Refreshes in <1m"
        }
    }
}
