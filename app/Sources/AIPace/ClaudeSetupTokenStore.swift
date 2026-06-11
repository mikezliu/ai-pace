import Foundation
import Security

enum ClaudeSetupTokenStoreIssue: Error, Equatable, Sendable {
    case accessDenied
    case invalidStoredToken
    case keychainFailure(OSStatus)

    var message: String {
        switch self {
        case .accessDenied:
            return "AIPace Claude setup-token Keychain access denied."
        case .invalidStoredToken:
            return "AIPace Claude setup-token Keychain item is invalid."
        case .keychainFailure(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "AIPace Claude setup-token Keychain failed: \(detail)"
        }
    }
}

struct ClaudeSetupTokenStore: Sendable {
    let loadToken: @Sendable () -> Result<String?, ClaudeSetupTokenStoreIssue>
    let saveToken: @Sendable (String) -> Result<Void, ClaudeSetupTokenStoreIssue>
    let deleteToken: @Sendable () -> Result<Void, ClaudeSetupTokenStoreIssue>

    static let empty = ClaudeSetupTokenStore(
        loadToken: { .success(nil) },
        saveToken: { _ in .success(()) },
        deleteToken: { .success(()) }
    )

    static let live = ClaudeSetupTokenStore(
        loadToken: {
            liveLoadToken()
        },
        saveToken: { token in
            liveSaveToken(token)
        },
        deleteToken: {
            liveDeleteToken()
        }
    )

    private static let service = "AIPace Claude Setup Token"
    private static let account = "Claude setup-token"
    private static let label = "AIPace Claude Setup Token"

    private static func liveLoadToken() -> Result<String?, ClaudeSetupTokenStoreIssue> {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else {
            return .success(nil)
        }
        guard status == errSecSuccess else {
            return .failure(issue(for: status))
        }
        guard
            let data = item as? Data,
            let token = String(data: data, encoding: .utf8)
        else {
            return .failure(.invalidStoredToken)
        }

        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(trimmed.isEmpty ? nil : trimmed)
    }

    private static func liveSaveToken(_ rawToken: String) -> Result<Void, ClaudeSetupTokenStoreIssue> {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return liveDeleteToken()
        }
        guard let data = token.data(using: .utf8) else {
            return .failure(.invalidStoredToken)
        }

        let query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return .success(())
        }
        guard updateStatus == errSecItemNotFound else {
            return .failure(issue(for: updateStatus))
        }

        var addQuery = query
        addQuery[kSecAttrLabel as String] = label
        addQuery[kSecValueData as String] = data
        if let access = makeCurrentApplicationAccess() {
            addQuery[kSecAttrAccess as String] = access
        }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            return .failure(issue(for: addStatus))
        }
        return .success(())
    }

    private static func liveDeleteToken() -> Result<Void, ClaudeSetupTokenStoreIssue> {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            return .failure(issue(for: status))
        }
        return .success(())
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func makeCurrentApplicationAccess() -> SecAccess? {
        var access: SecAccess?
        let status = SecAccessCreate(label as CFString, nil, &access)
        guard status == errSecSuccess else {
            return nil
        }
        return access
    }

    private static func issue(for status: OSStatus) -> ClaudeSetupTokenStoreIssue {
        if status == errSecInteractionNotAllowed
            || status == errSecAuthFailed
            || status == errSecUserCanceled {
            return .accessDenied
        }
        return .keychainFailure(status)
    }
}
