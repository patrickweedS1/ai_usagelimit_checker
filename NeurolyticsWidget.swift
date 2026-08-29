//
//  NeurolyticsWidget.swift
//  NeurolyticsWidget
//
//  Created by Devin
//  Co-Authored by Patrick Weed
//

import WidgetKit
import SwiftUI

// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), snapshots: getMockSnapshots())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(date: Date(), snapshots: getLatestSnapshots())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let snapshots = getLatestSnapshots()
        let entry = SimpleEntry(date: Date(), snapshots: snapshots)
        
        // Re-evaluate every 5 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
    
    // MARK: - Local JSON Cache Reader
    
    private func getLatestSnapshots() -> [ProviderSnapshot] {
        let homeDir = NSHomeDirectory()
        let cacheURL = URL(fileURLWithPath: homeDir).appendingPathComponent(".config/neurolytics/cache.json")
        
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([ProviderSnapshot].self, from: data) else {
            return getMockSnapshots()
        }
        return decoded
    }
    
    private func getMockSnapshots() -> [ProviderSnapshot] {
        return [
            ProviderSnapshot(
                provider: "claude",
                themeColorName: "orange",
                accountName: "elisha.productions@gmail.com",
                status: "ok",
                statusDetails: nil,
                groups: [
                    ModelGroup(
                        displayName: "CLAUDE AND GPT MODELS",
                        description: "Claude Opus, Claude Sonnet, GPT-OSS",
                        buckets: [
                            QuotaBucket(
                                bucketId: "claude-weekly",
                                displayName: "Weekly Limit Remaining",
                                windowType: "weekly",
                                usedPercent: 61.03,
                                remainingPercent: 38.97,
                                resetsAt: nil,
                                resetsDescription: "39% remaining · Refreshes in 59h 9m"
                            ),
                            QuotaBucket(
                                bucketId: "claude-5h",
                                displayName: "Five Hour Limit Remaining",
                                windowType: "5h",
                                usedPercent: 0.0,
                                remainingPercent: 100.0,
                                resetsAt: nil,
                                resetsDescription: "Quota available"
                            )
                        ]
                    )
                ],
                fetchedAt: Date()
            )
        ]
    }
}

// MARK: - Entry Struct

struct SimpleEntry: TimelineEntry {
    let date: Date
    let snapshots: [ProviderSnapshot]
}

// MARK: - Widget View Entry

struct NeurolyticsWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let activeSnapshots = entry.snapshots.filter { $0.status == "ok" }
            
            if activeSnapshots.isEmpty {
                VStack(spacing: 8) {
                    Text("🧠 Neurolytics")
                        .font(.system(size: 12, weight: .bold))
                    Text("No connected accounts.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch family {
                case .systemSmall:
                    // Show top provider in compact layout
                    if let first = activeSnapshots.first {
                        smallWidgetView(first)
                    }
                default: // Medium and large
                    // Show up to 2 active providers side-by-side
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(activeSnapshots.prefix(2)) { snapshot in
                            mediumWidgetCard(snapshot)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .containerBackground(for: .widget) {
            Color(NSColor.windowBackgroundColor)
        }
    }
    
    // MARK: - Small Widget (1 Active Provider)
    
    private func smallWidgetView(_ snapshot: ProviderSnapshot) -> some View {
        let providerColor = colorForTheme(snapshot.themeColorName)
        
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(providerColor)
                    .frame(width: 5, height: 5)
                Text(snapshot.provider.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(providerColor)
                Spacer()
            }
            
            if let firstGroup = snapshot.groups.first {
                ForEach(firstGroup.buckets.prefix(2)) { bucket in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(bucket.displayName.replacingOccurrences(of: " Limit Remaining", with: ""))
                                .font(.system(size: 8, weight: .bold))
                            Spacer()
                            Text("\(Int(bucket.remainingPercent))%")
                                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        }
                        
                        WidgetProgressBar(remainingValue: bucket.remainingPercent, color: providerColor)
                        
                        Text(bucket.resetsDescription)
                            .font(.system(size: 7))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .padding(10)
    }
    
    // MARK: - Medium Widget Card
    
    private func mediumWidgetCard(_ snapshot: ProviderSnapshot) -> some View {
        let providerColor = colorForTheme(snapshot.themeColorName)
        
        return VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 4) {
                Circle()
                    .fill(providerColor)
                    .frame(width: 5, height: 5)
                Text(snapshot.provider.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(providerColor)
                Spacer()
                Text(snapshot.accountName)
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            // Render first group details
            if let group = snapshot.groups.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.displayName)
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(0.5)
                    
                    VStack(spacing: 8) {
                        ForEach(group.buckets.prefix(2)) { bucket in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(bucket.displayName)
                                        .font(.system(size: 8, weight: .bold))
                                    Spacer()
                                    Text("\(String(format: "%.1f", bucket.remainingPercent))%")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                }
                                
                                WidgetProgressBar(remainingValue: bucket.remainingPercent, color: providerColor)
                                
                                Text(bucket.resetsDescription)
                                    .font(.system(size: 7.5))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(8)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }
    
    // MARK: - Colors Mapping
    
    private func colorForTheme(_ name: String) -> Color {
        switch name {
        case "orange": return .orange
        case "violet": return Color(red: 0.55, green: 0.25, blue: 0.95)
        case "teal": return Color(red: 0.1, green: 0.72, blue: 0.65)
        case "indigo": return .indigo
        default: return .blue
        }
    }
}

// MARK: - Widget Progress Bar Helper

struct WidgetProgressBar: View {
    let remainingValue: Double
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 6)
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: CGFloat(remainingValue / 100.0) * geo.size.width, height: 6)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Widget Entry Point

@main
struct NeurolyticsWidget: Widget {
    let kind: String = "NeurolyticsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            NeurolyticsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Neurolytics Quotas")
        .description("Natively monitors and displays your rolling AI development usage quotas.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
