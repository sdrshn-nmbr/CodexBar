import Foundation

public enum ClaudePlan: String, CaseIterable, Sendable {
    case max
    case pro
    case team
    case enterprise
    case ultra

    public var brandedLoginMethod: String {
        switch self {
        case .max:
            "Claude Max"
        case .pro:
            "Claude Pro"
        case .team:
            "Claude Team"
        case .enterprise:
            "Claude Enterprise"
        case .ultra:
            "Claude Ultra"
        }
    }

    public var compactLoginMethod: String {
        switch self {
        case .max:
            "Max"
        case .pro:
            "Pro"
        case .team:
            "Team"
        case .enterprise:
            "Enterprise"
        case .ultra:
            "Ultra"
        }
    }

    public var countsAsSubscription: Bool {
        switch self {
        case .max, .pro, .team, .ultra:
            true
        case .enterprise:
            false
        }
    }

    public static func fromOAuthRateLimitTier(_ rateLimitTier: String?) -> Self? {
        self.fromRateLimitTier(rateLimitTier)
    }

    public static func fromOAuthCredentials(subscriptionType: String?, rateLimitTier: String?) -> Self? {
        let subscription = self.fromCompatibilityLoginMethod(subscriptionType)
        let tier = self.fromOAuthRateLimitTier(rateLimitTier)
        if subscription == .max, tier == .ultra {
            return .ultra
        }
        return subscription ?? tier
    }

    public static func fromWebAccount(rateLimitTier: String?, billingType: String?) -> Self? {
        if let plan = self.fromRateLimitTier(rateLimitTier) {
            return plan
        }

        let tier = Self.normalized(rateLimitTier)
        let billing = Self.normalized(billingType)
        if billing.contains("stripe"), tier.contains("claude") {
            return .pro
        }
        return nil
    }

    public static func fromCompatibilityLoginMethod(_ loginMethod: String?) -> Self? {
        let words = Self.normalizedWords(loginMethod)
        if words.isEmpty {
            return nil
        }
        if words.contains("ultra") || Self.maxUsageMultiplier(rateLimitTier: loginMethod) == "20x" {
            return .ultra
        }
        if words.contains("max") {
            return .max
        }
        if words.contains("pro") {
            return .pro
        }
        if words.contains("team") {
            return .team
        }
        if words.contains("enterprise") {
            return .enterprise
        }
        return nil
    }

    public static func oauthLoginMethod(rateLimitTier: String?) -> String? {
        self.fromOAuthRateLimitTier(rateLimitTier)?.brandedLoginMethod
    }

    public static func oauthLoginMethod(subscriptionType: String?, rateLimitTier: String?) -> String? {
        self.fromOAuthCredentials(
            subscriptionType: subscriptionType,
            rateLimitTier: rateLimitTier)?.brandedLoginMethod
    }

    public static func webLoginMethod(rateLimitTier: String?, billingType: String?) -> String? {
        self.fromWebAccount(
            rateLimitTier: rateLimitTier,
            billingType: billingType)?.brandedLoginMethod
    }

    public static func webLoginMethod(rateLimitTier: String?, billingType: String?, seatTier: String?) -> String? {
        let plan = self.fromWebAccount(rateLimitTier: rateLimitTier, billingType: billingType)
        if let plan, plan != .team {
            return plan.brandedLoginMethod
        }

        return switch self.normalized(seatTier) {
        case "team_standard":
            "Claude Team Standard"
        case "team_tier_1":
            "Claude Team Premium"
        default:
            plan?.brandedLoginMethod
        }
    }

    public static func cliCompatibilityLoginMethod(_ loginMethod: String?) -> String? {
        guard let loginMethod = loginMethod?.trimmingCharacters(in: .whitespacesAndNewlines),
              !loginMethod.isEmpty
        else {
            return nil
        }

        if let plan = self.fromCompatibilityLoginMethod(loginMethod) {
            return plan.compactLoginMethod
        }

        return loginMethod
    }

    public static func isSubscriptionLoginMethod(_ loginMethod: String?) -> Bool {
        self.fromCompatibilityLoginMethod(loginMethod)?.countsAsSubscription ?? false
    }

    private static func fromRateLimitTier(_ rateLimitTier: String?) -> Self? {
        let tier = Self.normalized(rateLimitTier)
        if tier.contains("ultra") || Self.maxUsageMultiplier(rateLimitTier: rateLimitTier) == "20x" {
            return .ultra
        }
        if tier.contains("max") {
            return .max
        }
        if tier.contains("pro") {
            return .pro
        }
        if tier.contains("team") {
            return .team
        }
        if tier.contains("enterprise") {
            return .enterprise
        }
        return nil
    }

    private static func maxUsageMultiplier(rateLimitTier: String?) -> String? {
        let words = Self.normalizedWords(rateLimitTier)
        guard let maxIndex = words.firstIndex(of: Self.max.rawValue),
              words.indices.contains(maxIndex + 1)
        else {
            return nil
        }

        let multiplier = words[maxIndex + 1]
        guard multiplier.last == "x", Int(multiplier.dropLast()) != nil else {
            return nil
        }
        return multiplier
    }

    private static func normalized(_ text: String?) -> String {
        text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private static func normalizedWords(_ text: String?) -> [String] {
        self.normalized(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }
}
