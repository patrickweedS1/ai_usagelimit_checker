//
//  KeychainHelper.swift
//  Neurolytics
//
//  Created by Devin
//  Co-Authored by Patrick Weed
//

import Foundation
import Security

public class KeychainHelper {
    public static let shared = KeychainHelper()
    
    private init() {}
    
    /// Reads a generic password item from the macOS system Keychain
    public func readPassword(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess else {
            return nil
        }
        
        guard let data = dataTypeRef as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return password
    }
    
    /// Saves or updates a generic password item in the macOS system Keychain
    @discardableResult
    public func savePassword(service: String, account: String, passwordString: String) -> Bool {
        guard let passwordData = passwordString.data(using: .utf8) else {
            return false
        }
        
        // Check if item already exists
        let checkQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemCopyMatching(checkQuery as CFDictionary, nil)
        
        if status == errSecSuccess {
            // Update existing item
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: passwordData
            ]
            let updateStatus = SecItemUpdate(checkQuery as CFDictionary, attributesToUpdate as CFDictionary)
            return updateStatus == errSecSuccess
        } else if status == errSecItemNotFound {
            // Add new item
            var addQuery = checkQuery
            addQuery[kSecValueData as String] = passwordData
            // Ensure accessible when unlocked
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            return addStatus == errSecSuccess
        }
        
        return false
    }
    
    /// Deletes a generic password item from the macOS system Keychain
    @discardableResult
    public func deletePassword(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
