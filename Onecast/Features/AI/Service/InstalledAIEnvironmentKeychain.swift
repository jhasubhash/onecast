import Foundation

extension InstalledAIEnvironmentStore {
    /// One Keychain item per tool, as JSON; a failed read throws, a garbled item reads as none.
    static let keychain = InstalledAIEnvironmentStore(
        values: { kind in
            guard
                let stored = try KeychainSecretStore.installedAIEnvironment.secret(
                    for: kind.keychainAccount)
            else { return [:] }
            let values = try? JSONDecoder().decode([String: String].self, from: Data(stored.utf8))
            return values ?? [:]
        },
        save: { values, kind in
            guard !values.isEmpty else {
                try KeychainSecretStore.installedAIEnvironment.removeSecret(
                    for: kind.keychainAccount)
                return
            }
            let data = try JSONEncoder().encode(values)
            guard let encoded = String(bytes: data, encoding: .utf8) else {
                throw KeychainSecretStore.StoreError.invalidEncoding
            }
            try KeychainSecretStore.installedAIEnvironment.setSecret(
                encoded, for: kind.keychainAccount)
        })
}

extension InstalledAIKind {
    /// The Keychain store names an item by UUID, so each tool has one that never changes.
    fileprivate var keychainAccount: UUID {
        let value =
            switch self {
            case .codex: "559A2B35-A0EE-45DF-8E97-A87052450350"
            case .claude: "06C43DBE-F304-4E64-BBC5-F4A2AB00264B"
            case .openCode: "AF4DC1E6-7D9C-4C65-B278-CDB141C89DD3"
            case .copilot: "3E1B7C52-9D4A-4F0B-8C21-6A5E0D7F9B13"
            }
        return UUID(uuidString: value) ?? UUID()
    }
}
