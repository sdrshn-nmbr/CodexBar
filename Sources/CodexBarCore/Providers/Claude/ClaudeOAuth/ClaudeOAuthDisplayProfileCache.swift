import Foundation

/// Display-only lookups never delay a usage refresh or establish widget ownership.
actor ClaudeOAuthDisplayProfileCache {
    private var entries: [String: (pending: Task<Void, Never>?, profile: OAuthProfileResponse?)] = [:]

    func profile(
        accessToken: String,
        fetch: @escaping @Sendable (String) async throws -> OAuthProfileResponse) -> OAuthProfileResponse?
    {
        let key = ClaudeOAuthCredentialsStore.sha256Hex(Data(accessToken.utf8))
        if let entry = self.entries[key] { return entry.profile }
        self.entries[key] = (Task(priority: .utility) {
            let request = Task { try await fetch(accessToken) }
            let outcome = await BoundedTaskJoin(sourceTask: request).value(joinGrace: .seconds(2))
            let profile: OAuthProfileResponse? = if case let .value(profile) = outcome {
                profile
            } else { nil }
            self.entries[key] = (nil, profile)
        }, nil)
        return nil
    }

    #if DEBUG
    func finishPendingForTesting() async {
        for entry in self.entries.values {
            await entry.pending?.value
        }
    }
    #endif
}
