//
//  APIClients.swift
//  Neurolytics
//
//  Created by Devin
//  Co-Authored by Patrick Weed
//

import Foundation

/// Base utility for HTTP requests
internal class NetworkHelper {
    static func performRequest(
        url: URL,
        method: String = "GET",
        headers: [String: String],
        body: Data? = nil,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15.0
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "NetworkError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])))
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMsg = "HTTP Status \(httpResponse.statusCode)"
                completion(.failure(NSError(domain: "NetworkError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "NetworkError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Empty server response"])))
                return
            }
            
            completion(.success(data))
        }
        task.resume()
    }
}

/// Helper to parse JWT payload (no signature verification needed for client metadata)
internal struct JWTDecoder {
    static func decodeAccountID(from token: String) -> String? {
        let parts = token.components(separatedBy: ".")
        guard parts.count > 1 else { return nil }
        let payloadPart = parts[1]
        
        var base64 = payloadPart
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        if let authClaim = json["https://api.openai.com/auth"] as? [String: Any],
           let accountID = authClaim["chatgpt_account_id"] as? String {
            return accountID
        }
        
        if let accountID = json["account_id"] as? String {
            return accountID
        }
        
        return nil
    }
}

// MARK: - Claude Client
public class ClaudeClient {
    public static func fetchUsage(manualToken: String? = nil, completion: @escaping (ProviderSnapshot) -> Void) {
        let fetchedAt = Date()
        var resolvedToken = manualToken
        var resolvedRefreshToken: String? = nil
        var isFromKeychain = false
        let username = ProcessInfo.processInfo.environment["USER"] ?? "patrick.weed"
        
        // Auto-detect local credentials if manual token is nil
        if resolvedToken == nil {
            if let keychainCreds = KeychainHelper.shared.readPassword(service: "Claude Code-credentials", account: username) {
                // Parse Keychain JSON (Feedback #1: Parse nested 'claudeAiOauth' structure)
                if let data = keychainCreds.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let oauth = json["claudeAiOauth"] as? [String: Any] {
                        resolvedToken = oauth["accessToken"] as? String ?? oauth["access_token"] as? String
                        resolvedRefreshToken = oauth["refreshToken"] as? String ?? oauth["refresh_token"] as? String
                        isFromKeychain = true
                    }
                    if resolvedToken == nil {
                        resolvedToken = json["access_token"] as? String ?? json["accessToken"] as? String
                        resolvedRefreshToken = json["refresh_token"] as? String ?? json["refreshToken"] as? String
                    }
                }
            }
        }
        
        // Fallback to local credentials file if still nil
        if resolvedToken == nil {
            let homeDir = NSHomeDirectory()
            let credentialsPath = URL(fileURLWithPath: homeDir).appendingPathComponent(".claude/.credentials.json")
            if let data = try? Data(contentsOf: credentialsPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                resolvedToken = json["access_token"] as? String ?? json["accessToken"] as? String
                resolvedRefreshToken = json["refresh_token"] as? String ?? json["refreshToken"] as? String
            }
        }
        
        guard let token = resolvedToken, !token.isEmpty else {
            completion(ProviderSnapshot(
                provider: "claude",
                themeColorName: "orange",
                accountName: "Claude Account",
                status: "auth_missing",
                statusDetails: "No Claude Code credentials found. Please log in via 'claude' CLI or connect in Settings.",
                groups: [],
                fetchedAt: fetchedAt
            ))
            return
        }
        
        // Fetch usage and auto-refresh token silently if expired (Feedback #1)
        fetchUsageWithToken(
            token: token,
            refreshToken: resolvedRefreshToken,
            isFromKeychain: isFromKeychain,
            username: username,
            fetchedAt: fetchedAt,
            retryOnAuthFailure: true,
            completion: completion
        )
    }
    
    private static func fetchUsageWithToken(
        token: String,
        refreshToken: String?,
        isFromKeychain: Bool,
        username: String,
        fetchedAt: Date,
        retryOnAuthFailure: Bool,
        completion: @escaping (ProviderSnapshot) -> Void
    ) {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return }
        
        let headers = [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
            "Content-Type": "application/json"
        ]
        
        NetworkHelper.performRequest(url: url, headers: headers) { result in
            switch result {
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(ProviderSnapshot(
                        provider: "claude",
                        themeColorName: "orange",
                        accountName: "Claude Account",
                        status: "error",
                        statusDetails: "Invalid JSON response from Anthropic.",
                        groups: [],
                        fetchedAt: fetchedAt
                    ))
                    return
                }
                
                // If it returned an OAuth authentication_error, we can attempt a refresh!
                if let errorObj = json["error"] as? [String: Any],
                   let errorType = errorObj["type"] as? String,
                   errorType == "authentication_error" {
                    
                    if retryOnAuthFailure, let rToken = refreshToken, !rToken.isEmpty {
                        performTokenRefresh(refreshToken: rToken, isFromKeychain: isFromKeychain, username: username) { refreshedToken in
                            if let refreshedToken = refreshedToken {
                                // Retry once with the new access token!
                                fetchUsageWithToken(
                                    token: refreshedToken,
                                    refreshToken: rToken,
                                    isFromKeychain: isFromKeychain,
                                    username: username,
                                    fetchedAt: fetchedAt,
                                    retryOnAuthFailure: false,
                                    completion: completion
                                )
                            } else {
                                completion(ProviderSnapshot(
                                    provider: "claude",
                                    themeColorName: "orange",
                                    accountName: "Claude Account",
                                    status: "error",
                                    statusDetails: errorObj["message"] as? String ?? "OAuth access token expired and refresh failed.",
                                    groups: [],
                                    fetchedAt: fetchedAt
                                ))
                            }
                        }
                    } else {
                        completion(ProviderSnapshot(
                            provider: "claude",
                            themeColorName: "orange",
                            accountName: "Claude Account",
                            status: "error",
                            statusDetails: errorObj["message"] as? String ?? "OAuth access token expired.",
                            groups: [],
                            fetchedAt: fetchedAt
                        ))
                    }
                    return
                }
                
                var buckets: [QuotaBucket] = []
                
                // Parse legacy flat limits if present
                if let fiveHour = json["five_hour"] as? [String: Any],
                   let util = fiveHour["utilization"] as? Double,
                   let resetStr = fiveHour["resets_at"] as? String {
                    let resetsAt = ISO8601DateFormatter().date(from: resetStr)
                    buckets.append(QuotaBucket(
                        bucketId: "claude-5h",
                        displayName: "Five Hour Limit Remaining",
                        windowType: "5h",
                        usedPercent: util,
                        remainingPercent: max(0.0, 100.0 - util),
                        resetsAt: resetsAt,
                        resetsDescription: resetsAt?.relativeResetTimeDescription() ?? "Quota available"
                    ))
                }
                
                if let sevenDay = json["seven_day"] as? [String: Any],
                   let util = sevenDay["utilization"] as? Double,
                   let resetStr = sevenDay["resets_at"] as? String {
                    let resetsAt = ISO8601DateFormatter().date(from: resetStr)
                    buckets.append(QuotaBucket(
                        bucketId: "claude-weekly",
                        displayName: "Weekly Limit Remaining",
                        windowType: "weekly",
                        usedPercent: util,
                        remainingPercent: max(0.0, 100.0 - util),
                        resetsAt: resetsAt,
                        resetsDescription: resetsAt?.relativeResetTimeDescription() ?? "Quota available"
                    ))
                }
                
                // Parse new structured 'limits' array if present (takes precedence)
                if let limits = json["limits"] as? [[String: Any]] {
                    var structuredBuckets: [QuotaBucket] = []
                    for limit in limits {
                        guard let kind = limit["kind"] as? String,
                              let percentUsed = limit["percent"] as? Double,
                              let resetStr = limit["resets_at"] as? String else { continue }
                        
                        let resetsAt = ISO8601DateFormatter().date(from: resetStr)
                        let bucketId = "claude-limit-\(kind)"
                        let windowType = (kind == "session" ? "5h" : "weekly")
                        
                        var displayName = "Claude Quota Remaining"
                        if kind == "session" {
                            displayName = "Five Hour Limit Remaining"
                        } else if kind == "weekly_all" {
                            displayName = "Weekly Limit Remaining"
                        } else if kind == "weekly_scoped",
                                  let scope = limit["scope"] as? [String: Any],
                                  let modelObj = scope["model"] as? [String: Any],
                                  let modelName = modelObj["display_name"] as? String {
                            displayName = "Weekly \(modelName) Limit Remaining"
                        }
                        
                        structuredBuckets.append(QuotaBucket(
                            bucketId: bucketId,
                            displayName: displayName,
                            windowType: windowType,
                            usedPercent: percentUsed,
                            remainingPercent: max(0.0, 100.0 - percentUsed),
                            resetsAt: resetsAt,
                            resetsDescription: resetsAt?.relativeResetTimeDescription() ?? "Quota available"
                        ))
                    }
                    if !structuredBuckets.isEmpty {
                        buckets = structuredBuckets
                    }
                }
                
                // If extra/overage credits exist, parse them
                if let extra = json["extra_usage"] as? [String: Any],
                   let isEnabled = extra["is_enabled"] as? Bool, isEnabled,
                   let usedCredits = extra["used_credits"] as? Double,
                   let monthlyLimit = extra["monthly_limit"] as? Double, monthlyLimit > 0 {
                    let percent = (usedCredits / monthlyLimit) * 100.0
                    buckets.append(QuotaBucket(
                        bucketId: "claude-extra",
                        displayName: "Overage Credit Spending",
                        windowType: "monthly",
                        usedPercent: percent,
                        remainingPercent: max(0.0, 100.0 - percent),
                        resetsAt: nil,
                        resetsDescription: "$\(String(format: "%.2f", usedCredits / 100.0)) / $\(String(format: "%.2f", monthlyLimit / 100.0)) spent"
                    ))
                }
                
                // Check if we can parse the account email from the token payload (claims)
                var email = "Claude Account"
                let parts = token.components(separatedBy: ".")
                if parts.count > 1,
                   let payloadData = Data(base64Encoded: parts[1] + String(repeating: "=", count: (4 - parts[1].count % 4) % 4)),
                   let payloadJson = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                    email = payloadJson["email"] as? String ?? payloadJson["sub"] as? String ?? "Claude Account"
                }
                
                let group = ModelGroup(
                    displayName: "CLAUDE AND GPT MODELS",
                    description: "Models within this group: Claude Opus, Claude Sonnet, GPT-OSS",
                    buckets: buckets
                )
                
                completion(ProviderSnapshot(
                    provider: "claude",
                    themeColorName: "orange",
                    accountName: email,
                    status: "ok",
                    statusDetails: nil,
                    groups: [group],
                    fetchedAt: fetchedAt
                ))
                
            case .failure(let error):
                // If the status is 401 or 403, standard URLSession returns .failure. We attempt refresh!
                let code = (error as NSError).code
                if retryOnAuthFailure && (code == 401 || code == 403), let rToken = refreshToken, !rToken.isEmpty {
                    performTokenRefresh(refreshToken: rToken, isFromKeychain: isFromKeychain, username: username) { refreshedToken in
                        if let refreshedToken = refreshedToken {
                            fetchUsageWithToken(
                                token: refreshedToken,
                                refreshToken: rToken,
                                isFromKeychain: isFromKeychain,
                                username: username,
                                fetchedAt: fetchedAt,
                                retryOnAuthFailure: false,
                                completion: completion
                            )
                        } else {
                            completion(ProviderSnapshot(
                                provider: "claude",
                                themeColorName: "orange",
                                accountName: "Claude Account",
                                status: "error",
                                statusDetails: "OAuth access token expired and refresh failed.",
                                groups: [],
                                fetchedAt: fetchedAt
                            ))
                        }
                    }
                } else {
                    completion(ProviderSnapshot(
                        provider: "claude",
                        themeColorName: "orange",
                        accountName: "Claude Account",
                        status: "error",
                        statusDetails: error.localizedDescription,
                        groups: [],
                        fetchedAt: fetchedAt
                    ))
                }
            }
        }
    }
    
    private static func performTokenRefresh(refreshToken: String, isFromKeychain: Bool, username: String, completion: @escaping (String?) -> Void) {
        guard let tokenUrl = URL(string: "https://platform.claude.com/v1/oauth/token") else {
            completion(nil)
            return
        }
        
        let bodyJson: [String: Any] = [
            "grant_type": "refresh_token",
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
            "refresh_token": refreshToken
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyJson) else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 15.0
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String else {
                completion(nil)
                return
            }
            
            let newRefreshToken = json["refresh_token"] as? String ?? refreshToken
            let expiresAt = (json["expires_in"] as? Double ?? 3600.0) * 1000.0 + Date().timeIntervalSince1970 * 1000.0
            
            // Save back to Keychain or config
            if isFromKeychain {
                let updatedJson: [String: Any] = [
                    "claudeAiOauth": [
                        "accessToken": accessToken,
                        "refreshToken": newRefreshToken,
                        "expiresAt": expiresAt,
                        "scopes": ["user:file_upload", "user:inference", "user:mcp_servers", "user:profile", "user:sessions:claude_code"],
                        "subscriptionType": "enterprise",
                        "rateLimitTier": "default_claude_zero"
                    ]
                ]
                if let updatedData = try? JSONSerialization.data(withJSONObject: updatedJson, options: .prettyPrinted),
                   let updatedString = String(data: updatedData, encoding: .utf8) {
                    KeychainHelper.shared.savePassword(service: "Claude Code-credentials", account: username, passwordString: updatedString)
                }
            } else {
                // Save manually to our own app's manual token cache
                QuotaManager.shared.setManualToken(for: "claude", token: accessToken)
            }
            
            completion(accessToken)
        }
        task.resume()
    }
}

// MARK: - Antigravity Client
public class AntigravityClient {
    public static func fetchUsage(manualToken: String? = nil, completion: @escaping (ProviderSnapshot) -> Void) {
        let fetchedAt = Date()
        var resolvedToken = manualToken
        var projectId: String? = nil
        
        // Auto-detect local credentials if manual token is nil
        if resolvedToken == nil {
            let homeDir = NSHomeDirectory()
            let oauthCredsPath = URL(fileURLWithPath: homeDir).appendingPathComponent(".codexbar/antigravity/oauth_creds.json")
            if let data = try? Data(contentsOf: oauthCredsPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                resolvedToken = json["access_token"] as? String ?? json["accessToken"] as? String
                projectId = json["projectId"] as? String ?? json["project_id"] as? String
            }
        }
        
        guard let token = resolvedToken, !token.isEmpty else {
            completion(ProviderSnapshot(
                provider: "antigravity",
                themeColorName: "violet",
                accountName: "Antigravity Account",
                status: "auth_missing",
                statusDetails: "No Antigravity credentials found. Please run 'agy' CLI first or connect in Settings.",
                groups: [],
                fetchedAt: fetchedAt
            ))
            return
        }
        
        guard let url = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary") else { return }
        
        let headers = [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json",
            "User-Agent": "antigravity"
        ]
        
        let bodyJson: [String: Any] = projectId != nil ? ["project": projectId!] : [:]
        let bodyData = try? JSONSerialization.data(withJSONObject: bodyJson)
        
        NetworkHelper.performRequest(url: url, method: "POST", headers: headers, body: bodyData) { result in
            switch result {
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let groupsArray = json["groups"] as? [[String: Any]] else {
                    completion(ProviderSnapshot(
                        provider: "antigravity",
                        themeColorName: "violet",
                        accountName: "Antigravity Account",
                        status: "error",
                        statusDetails: "Invalid retrieveUserQuotaSummary JSON response from Google.",
                        groups: [],
                        fetchedAt: fetchedAt
                    ))
                    return
                }
                
                var modelGroups: [ModelGroup] = []
                
                for groupObj in groupsArray {
                    guard let displayName = groupObj["displayName"] as? String,
                          let description = groupObj["description"] as? String,
                          let bucketsArray = groupObj["buckets"] as? [[String: Any]] else { continue }
                    
                    var buckets: [QuotaBucket] = []
                    
                    for bucketObj in bucketsArray {
                        guard let bucketId = bucketObj["bucketId"] as? String,
                              let bDisplayName = bucketObj["displayName"] as? String,
                              let window = bucketObj["window"] as? String,
                              let remainingFraction = bucketObj["remainingFraction"] as? Double else { continue }
                        
                        let resetTimeStr = bucketObj["resetTime"] as? String
                        let resetsAt = resetTimeStr != nil ? ISO8601DateFormatter().date(from: resetTimeStr!) : nil
                        
                        let remainingPercent = remainingFraction * 100.0
                        let usedPercent = max(0.0, 100.0 - remainingPercent)
                        
                        buckets.append(QuotaBucket(
                            bucketId: bucketId,
                            displayName: bDisplayName,
                            windowType: window,
                            usedPercent: usedPercent,
                            remainingPercent: remainingPercent,
                            resetsAt: resetsAt,
                            resetsDescription: resetsAt?.relativeResetTimeDescription() ?? "Quota available"
                        ))
                    }
                    
                    modelGroups.append(ModelGroup(
                        displayName: displayName.uppercased(),
                        description: description,
                        buckets: buckets
                    ))
                }
                
                // Attempt to decode account email from JWT
                var email = "Antigravity Account"
                let parts = token.components(separatedBy: ".")
                if parts.count > 1,
                   let payloadData = Data(base64Encoded: parts[1] + String(repeating: "=", count: (4 - parts[1].count % 4) % 4)),
                   let payloadJson = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                    email = payloadJson["email"] as? String ?? payloadJson["sub"] as? String ?? "Antigravity Account"
                }
                
                completion(ProviderSnapshot(
                    provider: "antigravity",
                    themeColorName: "violet",
                    accountName: email,
                    status: "ok",
                    statusDetails: nil,
                    groups: modelGroups,
                    fetchedAt: fetchedAt
                ))
                
            case .failure(let error):
                completion(ProviderSnapshot(
                    provider: "antigravity",
                    themeColorName: "violet",
                    accountName: "Antigravity Account",
                    status: "error",
                    statusDetails: error.localizedDescription,
                    groups: [],
                    fetchedAt: fetchedAt
                ))
            }
        }
    }
}

// MARK: - ChatGPT Client
public class ChatGPTClient {
    public static func fetchUsage(manualToken: String? = nil, completion: @escaping (ProviderSnapshot) -> Void) {
        let fetchedAt = Date()
        var resolvedToken = manualToken
        
        // Auto-detect local credentials if manual token is nil
        if resolvedToken == nil {
            let homeDir = NSHomeDirectory()
            let codexAuthPath = URL(fileURLWithPath: homeDir).appendingPathComponent(".codex/auth.json")
            if let data = try? Data(contentsOf: codexAuthPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                resolvedToken = json["access_token"] as? String ?? (json["tokens"] as? [String: Any])?["access_token"] as? String
            }
        }
        
        guard let token = resolvedToken, !token.isEmpty else {
            completion(ProviderSnapshot(
                provider: "chatgpt",
                themeColorName: "teal",
                accountName: "ChatGPT Account",
                status: "auth_missing",
                statusDetails: "No ChatGPT/Codex credentials found. Please log in to ChatGPT or input access token in Settings.",
                groups: [],
                fetchedAt: fetchedAt
            ))
            return
        }
        
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else { return }
        
        let accountId = JWTDecoder.decodeAccountID(from: token)
        var headers = [
            "Authorization": "Bearer \(token)",
            "User-Agent": "thin-codex-usage/0.1"
        ]
        if let accountId = accountId {
            headers["ChatGPT-Account-Id"] = accountId
        }
        
        NetworkHelper.performRequest(url: url, headers: headers) { result in
            switch result {
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rateLimit = json["rate_limit"] as? [String: Any] else {
                    completion(ProviderSnapshot(
                        provider: "chatgpt",
                        themeColorName: "teal",
                        accountName: "ChatGPT Account",
                        status: "error",
                        statusDetails: "Invalid response schema from ChatGPT backend-api.",
                        groups: [],
                        fetchedAt: fetchedAt
                    ))
                    return
                }
                
                var buckets: [QuotaBucket] = []
                
                if let primary = rateLimit["primary_window"] as? [String: Any],
                   let usedPct = primary["used_percent"] as? Double,
                   let resetTimestamp = primary["reset_at"] as? Double {
                    let resetsAt = Date(timeIntervalSince1970: resetTimestamp)
                    buckets.append(QuotaBucket(
                        bucketId: "chatgpt-primary",
                        displayName: "Five Hour Limit Remaining",
                        windowType: "5h",
                        usedPercent: usedPct,
                        remainingPercent: max(0.0, 100.0 - usedPct),
                        resetsAt: resetsAt,
                        resetsDescription: resetsAt.relativeResetTimeDescription()
                    ))
                }
                
                if let secondary = rateLimit["secondary_window"] as? [String: Any],
                   let usedPct = secondary["used_percent"] as? Double,
                   let resetTimestamp = secondary["reset_at"] as? Double {
                    let resetsAt = Date(timeIntervalSince1970: resetTimestamp)
                    buckets.append(QuotaBucket(
                        bucketId: "chatgpt-secondary",
                        displayName: "Weekly Limit Remaining",
                        windowType: "weekly",
                        usedPercent: usedPct,
                        remainingPercent: max(0.0, 100.0 - usedPct),
                        resetsAt: resetsAt,
                        resetsDescription: resetsAt.relativeResetTimeDescription()
                    ))
                }
                
                let email = json["email"] as? String ?? "ChatGPT Account"
                
                let group = ModelGroup(
                    displayName: "CHATGPT AND CODEX MODELS",
                    description: "Usage of Plus/Pro rolling limits and API models.",
                    buckets: buckets
                )
                
                completion(ProviderSnapshot(
                    provider: "chatgpt",
                    themeColorName: "teal",
                    accountName: email,
                    status: "ok",
                    statusDetails: nil,
                    groups: [group],
                    fetchedAt: fetchedAt
                ))
                
            case .failure(let error):
                completion(ProviderSnapshot(
                    provider: "chatgpt",
                    themeColorName: "teal",
                    accountName: "ChatGPT Account",
                    status: "error",
                    statusDetails: error.localizedDescription,
                    groups: [],
                    fetchedAt: fetchedAt
                ))
            }
        }
    }
}

// MARK: - Devin Client
public class DevinClient {
    public static func fetchUsage(manualToken: String? = nil, manualOrgId: String? = nil, customHost: String? = nil, completion: @escaping (ProviderSnapshot) -> Void) {
        let fetchedAt = Date()
        var resolvedToken = manualToken
        var resolvedOrgId = manualOrgId
        
        // Auto-detect local credentials if manual token is nil
        if resolvedToken == nil {
            resolvedToken = ProcessInfo.processInfo.environment["DEVIN_API_KEY"]
        }
        
        // Fallback to reading config
        if resolvedToken == nil || resolvedOrgId == nil {
            let homeDir = NSHomeDirectory()
            let configPath = URL(fileURLWithPath: homeDir).appendingPathComponent(".config/devin/config.json")
            if let data = try? Data(contentsOf: configPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let devinSection = json["devin"] as? [String: Any] {
                    resolvedOrgId = devinSection["org_id"] as? String
                }
            }
        }
        
        guard let token = resolvedToken, !token.isEmpty else {
            completion(ProviderSnapshot(
                provider: "devin",
                themeColorName: "indigo",
                accountName: "Devin Account",
                status: "auth_missing",
                statusDetails: "No Devin API Key found. Set DEVIN_API_KEY in environment or Settings.",
                groups: [],
                fetchedAt: fetchedAt
            ))
            return
        }
        
        // Resolve custom base host (e.g. sentinelone.devinenterprise.com -> api.sentinelone.devinenterprise.com) (Feedback #3)
        var baseHost = customHost ?? "api.devin.ai"
        if baseHost != "api.devin.ai" && !baseHost.hasPrefix("api.") {
            baseHost = "api." + baseHost
        }
        
        // Sum Devin consumption for the current month
        let calendar = Calendar.current
        let now = Date()
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) else { return }
        
        let startTimestamp = Int(startOfMonth.timeIntervalSince1970)
        let endTimestamp = Int(endOfMonth.timeIntervalSince1970)
        
        guard let url = URL(string: "https://\(baseHost)/v3/enterprise/consumption/daily?time_after=\(startTimestamp)&time_before=\(endTimestamp)") else { return }
        
        let headers = [
            "Authorization": "Bearer \(token)"
        ]
        
        NetworkHelper.performRequest(url: url, headers: headers) { result in
            switch result {
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let consumptionArray = json["consumption"] as? [[String: Any]] else {
                    completion(ProviderSnapshot(
                        provider: "devin",
                        themeColorName: "indigo",
                        accountName: "Devin Account",
                        status: "error",
                        statusDetails: "Invalid response from Devin enterprise/consumption.",
                        groups: [],
                        fetchedAt: fetchedAt
                    ))
                    return
                }
                
                // Sum total spent in dollars/cents (Devin API cost is returned as decimal strings or numbers)
                var totalSpent: Double = 0.0
                for daily in consumptionArray {
                    if let cost = daily["cost"] as? Double {
                        totalSpent += cost
                    } else if let costStr = daily["cost"] as? String, let costVal = Double(costStr) {
                        totalSpent += costVal
                    }
                }
                
                // Retrieve Devin user profile info if we can, or fallback
                var accountName = resolvedOrgId ?? "Devin Account"
                if accountName.hasPrefix("org-") {
                    accountName = String(accountName.prefix(12)) + "..."
                }
                
                let limit: Double = 300.0 // Default work monthly limit budget
                let percentUsed = min(100.0, (totalSpent / limit) * 100.0)
                
                let bucket = QuotaBucket(
                    bucketId: "devin-monthly",
                    displayName: "Monthly Consumption",
                    windowType: "monthly",
                    usedPercent: percentUsed,
                    remainingPercent: max(0.0, 100.0 - percentUsed),
                    resetsAt: endOfMonth,
                    resetsDescription: "$\(String(format: "%.2f", totalSpent)) / $\(String(format: "%.2f", limit)) spent"
                )
                
                let group = ModelGroup(
                    displayName: "DEVIN COGNITION METRICS",
                    description: "Tracks active session count and aggregate organization usage.",
                    buckets: [bucket]
                )
                
                completion(ProviderSnapshot(
                    provider: "devin",
                    themeColorName: "indigo",
                    accountName: accountName,
                    status: "ok",
                    statusDetails: nil,
                    groups: [group],
                    fetchedAt: fetchedAt
                ))
                
            case .failure(let error):
                // If it's a 403, standard non-enterprise service keys cannot call the /enterprise endpoint.
                // We fallback to standard session queries to just report status as OK
                let is403 = (error as NSError).code == 403
                if is403 {
                    // Make fallback call to list sessions to verify status is active/OK
                    let fallbackUrl = URL(string: "https://\(baseHost)/v3/self")!
                    NetworkHelper.performRequest(url: fallbackUrl, headers: headers) { fallbackResult in
                        switch fallbackResult {
                        case .success:
                            completion(ProviderSnapshot(
                                provider: "devin",
                                themeColorName: "indigo",
                                accountName: "Devin Account (Active)",
                                status: "ok",
                                statusDetails: nil,
                                groups: [ModelGroup(
                                    displayName: "DEVIN COGNITION METRICS",
                                    description: "Credentials Verified. Custom Billing Limits require Enterprise Service User Key.",
                                    buckets: [QuotaBucket(
                                        bucketId: "devin-status",
                                        displayName: "API Key Integration",
                                        windowType: "other",
                                        usedPercent: 0,
                                        remainingPercent: 100.0,
                                        resetsAt: nil,
                                        resetsDescription: "Verified & Connected"
                                    )]
                                )],
                                fetchedAt: fetchedAt
                            ))
                        case .failure(let fallbackErr):
                            completion(ProviderSnapshot(
                                provider: "devin",
                                themeColorName: "indigo",
                                accountName: "Devin Account",
                                status: "error",
                                statusDetails: fallbackErr.localizedDescription,
                                groups: [],
                                fetchedAt: fetchedAt
                            ))
                        }
                    }
                } else {
                    completion(ProviderSnapshot(
                        provider: "devin",
                        themeColorName: "indigo",
                        accountName: "Devin Account",
                        status: "error",
                        statusDetails: error.localizedDescription,
                        groups: [],
                        fetchedAt: fetchedAt
                    ))
                }
            }
        }
    }
}
