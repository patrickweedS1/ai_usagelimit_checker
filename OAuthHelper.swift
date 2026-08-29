//
//  OAuthHelper.swift
//  Neurolytics
//
//  Created by Devin
//  Co-Authored by Patrick Weed
//

import Foundation
import Network
import CryptoKit
import AppKit

public class OAuthHelper {
    public static let shared = OAuthHelper()
    
    private let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let port: UInt16 = 54321
    private var callbackServer: LocalCallbackServer?
    
    private var currentVerifier: String?
    private var currentState: String?
    
    private init() {}
    
    // MARK: - PKCE Strings Generation
    
    private func generateRandomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<length).map { _ in letters.randomElement()! })
    }
    
    private func sha256Base64URLEncoded(string: String) -> String {
        let inputData = Data(string.utf8)
        let hashed = SHA256.hash(data: inputData)
        let hashData = Data(hashed)
        var base64 = hashData.base64EncodedString()
        base64 = base64.replacingOccurrences(of: "+", with: "-")
        base64 = base64.replacingOccurrences(of: "/", with: "_")
        base64 = base64.replacingOccurrences(of: "=", with: "")
        return base64
    }
    
    // MARK: - Authorization Flow
    
    public func startClaudeLoginFlow(completion: @escaping (Result<String, Error>) -> Void) {
        // Generate security context
        let verifier = generateRandomString(length: 64)
        let challenge = sha256Base64URLEncoded(string: verifier)
        let state = generateRandomString(length: 16)
        
        self.currentVerifier = verifier
        self.currentState = state
        
        // Stop any old listener
        callbackServer?.stop()
        
        // Setup local HTTP server to capture callback code
        callbackServer = LocalCallbackServer(port: port) { [weak self] code, returnedState in
            guard let self = self else { return }
            self.callbackServer?.stop()
            self.callbackServer = nil
            
            // Validate state parameter to prevent CSRF attacks
            guard returnedState == self.currentState else {
                completion(.failure(NSError(domain: "OAuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "State parameter mismatch. Security check failed."])))
                return
            }
            
            // Exchange code for Access/Refresh Tokens
            self.exchangeCodeForTokens(code: code, verifier: verifier, completion: completion)
        }
        
        callbackServer?.start()
        
        // Build Auth URL
        // Bounces through claude.com/cai/* as officially specified
        var authComponents = URLComponents(string: "https://claude.com/cai/oauth/authorize")!
        authComponents.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: "http://localhost:\(port)/callback"),
            URLQueryItem(name: "scope", value: "user:profile org:inference user:sessions:claude_code"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        
        if let authUrl = authComponents.url {
            // Open user's browser to authenticate
            NSWorkspace.shared.open(authUrl)
        } else {
            completion(.failure(NSError(domain: "OAuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not build Auth URL."])))
        }
    }
    
    private func exchangeCodeForTokens(code: String, verifier: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let tokenUrl = URL(string: "https://platform.claude.com/v1/oauth/token") else { return }
        
        let bodyJson: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": "http://localhost:\(port)/callback"
        ]
        
        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyJson) else { return }
        
        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let data = data else {
                completion(.failure(NSError(domain: "OAuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Token exchange request failed."])))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let accessToken = json["access_token"] as? String {
                    
                    // Store natively under Neurolytics Keychain service
                    QuotaManager.shared.setManualToken(for: "claude", token: accessToken)
                    
                    completion(.success(accessToken))
                } else {
                    completion(.failure(NSError(domain: "OAuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing access token in exchange response."])))
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
    
    // MARK: - Google (Antigravity) OAuth PKCE Flow
    
    public func startGoogleLoginFlow(completion: @escaping (Result<String, Error>) -> Void) {
        let verifier = generateRandomString(length: 64)
        let challenge = sha256Base64URLEncoded(string: verifier)
        let state = generateRandomString(length: 16)
        
        self.currentVerifier = verifier
        self.currentState = state
        
        callbackServer?.stop()
        
        callbackServer = LocalCallbackServer(port: port) { [weak self] code, returnedState in
            guard let self = self else { return }
            self.callbackServer?.stop()
            self.callbackServer = nil
            
            guard returnedState == self.currentState else {
                completion(.failure(NSError(domain: "OAuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "State parameter mismatch. Security check failed."])))
                return
            }
            
            self.exchangeGoogleCodeForTokens(code: code, verifier: verifier, completion: completion)
        }
        
        callbackServer?.start()
        
        var authComponents = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        authComponents.queryItems = [
            URLQueryItem(name: "client_id", value: "32555940559.apps.googleusercontent.com"), // Standard Google Cloud SDK Client
            URLQueryItem(name: "redirect_uri", value: "http://localhost:\(port)/callback"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        if let authUrl = authComponents.url {
            NSWorkspace.shared.open(authUrl)
        } else {
            completion(.failure(NSError(domain: "OAuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not build Google Auth URL."])))
        }
    }
    
    private func exchangeGoogleCodeForTokens(code: String, verifier: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let tokenUrl = URL(string: "https://oauth2.googleapis.com/token") else { return }
        
        let bodyComponents = [
            "grant_type=authorization_code",
            "client_id=32555940559.apps.googleusercontent.com",
            "code=\(code)",
            "code_verifier=\(verifier)",
            "redirect_uri=http://localhost:\(port)/callback"
        ]
        
        let bodyString = bodyComponents.joined(separator: "&")
        guard let bodyData = bodyString.data(using: .utf8) else { return }
        
        var request = URLRequest(url: tokenUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                  let data = data else {
                completion(.failure(NSError(domain: "OAuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Google token exchange failed."])))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let accessToken = json["access_token"] as? String {
                    
                    // Store natively under Neurolytics Keychain service
                    QuotaManager.shared.setManualToken(for: "antigravity", token: accessToken)
                    
                    completion(.success(accessToken))
                } else {
                    completion(.failure(NSError(domain: "OAuthError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing access token in Google response."])))
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
}

// MARK: - Local Callback Server using Apple Network Framework
internal class LocalCallbackServer {
    private var listener: NWListener?
    private let port: UInt16
    private let onCodeReceived: (String, String) -> Void
    
    init(port: UInt16, onCodeReceived: @escaping (String, String) -> Void) {
        self.port = port
        self.onCodeReceived = onCodeReceived
    }
    
    func start() {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let parameters = NWParameters.tcp
        
        do {
            listener = try NWListener(using: parameters, on: nwPort)
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.start(queue: .global())
        } catch {
            print("Failed to start listener: \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = data, !data.isEmpty,
               let request = String(data: data, encoding: .utf8) {
                
                // Parse GET line
                if let firstLine = request.components(separatedBy: "\r\n").first,
                   firstLine.hasPrefix("GET ") {
                    let parts = firstLine.components(separatedBy: " ")
                    if parts.count > 1 {
                        let path = parts[1]
                        if let urlComponents = URLComponents(string: "http://localhost\(path)") {
                            let code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value
                            let state = urlComponents.queryItems?.first(where: { $0.name == "state" })?.value
                            
                            // Return successful landing page
                            let html = """
                            HTTP/1.1 200 OK\r
                            Content-Type: text/html; charset=utf-8\r
                            Connection: close\r
                            \r
                            <!DOCTYPE html>
                            <html>
                            <head>
                                <meta charset="utf-8">
                                <meta name="viewport" content="width=device-width, initial-scale=1">
                                <title>Neurolytics Connected</title>
                                <style>
                                    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; text-align: center; padding: 60px 20px; background-color: #f4f6f9; margin: 0; }
                                    .card { background: white; padding: 40px; border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.06); max-width: 450px; margin: 0 auto; }
                                    h1 { color: #1e3a8a; margin-top: 20px; margin-bottom: 10px; font-size: 24px; }
                                    p { color: #4b5563; font-size: 14px; line-height: 1.6; margin-bottom: 24px; }
                                </style>
                            </head>
                            <body>
                                <div class="card">
                                    <div style="font-size: 54px;">🧠</div>
                                    <h1>Neurolytics Connected!</h1>
                                    <p>Your Claude account has been successfully authenticated.<br><br>You can now safely <b>close this tab</b> and return to the Neurolytics app.</p>
                                </div>
                            </body>
                            </html>
                            """
                            
                            if let responseData = html.data(using: .utf8) {
                                connection.send(content: responseData, completion: .contentProcessed({ _ in
                                    connection.cancel()
                                    if let code = code, let state = state {
                                        self.onCodeReceived(code, state)
                                    }
                                }))
                            }
                            return
                        }
                    }
                }
            }
            connection.cancel()
        }
    }
}
