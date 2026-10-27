import SwiftUI

enum Provider: String, Codable, CaseIterable {
    case vercel, cloudflare, github

    var name: String {
        switch self {
        case .vercel: "Vercel"
        case .cloudflare: "Cloudflare"
        case .github: "GitHub Actions"
        }
    }

    /// Simple Icons (CC0) logo in the asset catalog.
    var logo: String { self == .github ? "logo-githubactions" : "logo-\(rawValue)" }

    var tint: Color {
        switch self {
        case .vercel: .primary
        case .cloudflare: Color(red: 0.953, green: 0.502, blue: 0.125) // #F38020
        case .github: Color(red: 0.165, green: 0.518, blue: 0.996) // #2088FF, Actions blue
        }
    }

    var pitch: String {
        switch self {
        case .vercel: "Deployments and previews for every team"
        case .cloudflare: "Workers and Pages across all accounts"
        case .github: "Workflow runs for anything that deploys from CI"
        }
    }

    var tokenURL: URL {
        switch self {
        case .vercel: URL(string: "https://vercel.com/account/tokens")!
        case .cloudflare: URL(string: "https://dash.cloudflare.com/profile/api-tokens")!
        case .github: URL(string: "https://github.com/settings/personal-access-tokens/new")!
        }
    }

    var tokenHelp: String {
        switch self {
        // Vercel tokens can't be read-only (only scoped to a team or project), so say so and recommend the safest shape.
        case .vercel: "Vercel tokens can't be read-only yet, so scope each one to a single team and give it an expiration. Add one token per team; Deployed Yet? only ever reads."
        case .cloudflare: "Create a custom token with Account Settings: Read, Workers Scripts: Read and Cloudflare Pages: Read, for all accounts you want to watch."
        case .github: "Create a fine-grained token with Actions: Read and Metadata: Read on the repos you deploy from."
        }
    }

    var apiHost: String {
        switch self {
        case .vercel: "api.vercel.com"
        case .cloudflare: "api.cloudflare.com"
        case .github: "api.github.com"
        }
    }

    func client(token: String) -> any ProviderClient {
        switch self {
        case .vercel: VercelClient(token: token)
        case .cloudflare: CloudflareClient(token: token)
        case .github: GitHubClient(token: token)
        }
    }
}

/// One per provider. A "team" is a Vercel team or a Cloudflare account.
protocol ProviderClient: Sendable {
    /// `discover`: list every project the token can see (Settings, auto-pick). `teams`: the teams to read
    /// deploys for; Vercel and Cloudflare read all teams when discovering, GitHub only ever reads picked repos.
    /// Teams that refuse are listed in `unreachable`; it throws only when nothing could be read.
    func projects(account: Account, teams: Set<String>, discover: Bool) async throws -> (projects: [Project], unreachable: [TeamRef])
    func suggestedLabel() async throws -> String
}

/// A Vercel team or Cloudflare account that couldn't be (fully) read this time.
struct TeamRef: Hashable, Sendable {
    let id: String
    let name: String
}

/// Shared GET + decode for provider APIs.
func getJSON<T: Decodable>(_ base: String, _ path: String, _ query: [String: String], token: String, provider: Provider) async throws -> T {
    var url = URLComponents(string: base + path)!
    if !query.isEmpty { url.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
    var request = URLRequest(url: url.url!)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        // GitHub answers an exhausted rate limit with 403, not 429; don't call that a bad token.
        if http.statusCode == 403, http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
            throw AppError.http(429, provider)
        }
        throw AppError.http(http.statusCode, provider)
    }
    return try JSONDecoder().decode(T.self, from: data)
}

/// How the menu bar glyph is colored, in the menu's colors. Automatic only colors what's worth a look:
/// amber while building, green for a few minutes after a deploy lands, red while something's failed.
enum IconColor: String, CaseIterable, Identifiable {
    case never, automatic, always
    var id: Self { self }
    var label: String {
        switch self {
        case .never: "Never"
        case .automatic: "Automatic"
        case .always: "Always"
        }
    }
}

/// The menu bar glyph's look: one SF Symbol per answer (building, live, failed). Every set reads the same way,
/// an open or questioning shape while building that becomes a settled one when it ships.
enum IconStyle: String, CaseIterable, Identifiable {
    case plain, circled, filled, triangle, cloud, dot
    var id: Self { self }
    var label: String {
        switch self {
        case .plain: "Plain"
        case .circled: "Circled"
        case .filled: "Filled"
        case .triangle: "Triangle"
        case .cloud: "Cloud"
        case .dot: "Dot"
        }
    }

    /// nil (no deploys yet) draws the building symbol, dimmed.
    func symbol(_ state: DeployState?) -> String {
        let (building, ready, failed): (String, String, String) = switch self {
        case .plain: ("questionmark", "checkmark", "exclamationmark")
        case .circled: ("questionmark.circle", "checkmark.circle", "exclamationmark.circle")
        case .filled: ("questionmark.circle.fill", "checkmark.circle.fill", "exclamationmark.circle.fill")
        case .triangle: ("triangle", "triangle.fill", "exclamationmark.triangle.fill") // hollow until it ships, like Vercel's mark
        case .cloud: ("icloud.and.arrow.up", "checkmark.icloud", "exclamationmark.icloud")
        case .dot: ("circle.dashed", "circle.fill", "exclamationmark.circle.fill")
        }
        switch state {
        case .failed: return failed
        case .ready, .canceled: return ready
        case .building, nil: return building
        }
    }
}

struct Account: Codable, Identifiable, Hashable {
    var id = UUID()
    var label: String
    var provider: Provider
}

/// Ordered by severity so `max()` gives the menu bar state.
enum DeployState: Int, Comparable, Codable {
    case canceled, ready, building, failed

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .canceled: "Canceled"
        case .ready: "Ready"
        case .building: "Building"
        case .failed: "Failed"
        }
    }

    var color: Color {
        switch self {
        case .canceled: .gray
        case .ready: .green
        case .building: .orange
        case .failed: .red
        }
    }
}

struct Deploy: Identifiable, Hashable, Codable {
    let id: String
    let provider: Provider
    let projectID: String
    let projectName: String
    let accountLabel: String
    /// Team or account the project lives in on the provider.
    let team: String
    let state: DeployState
    let isProduction: Bool
    let branch: String?
    let message: String?
    let createdAt: Date
    /// When the build started, for the live "building 1:23" timer.
    let startedAt: Date
    /// Build duration once finished.
    let duration: TimeInterval?
    /// Deploy page on the provider dashboard.
    let url: URL?
    /// The deployed site itself.
    let siteURL: URL?
    let projectURL: URL?
    /// No build phase reported (a `wrangler deploy`): it just appears, already live.
    var isManual = false
    /// Full commit SHA when the provider knows it.
    var commit: String?

    var shortCommit: String? { commit.map { String($0.prefix(7)) } }
}

struct Project: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let accountID: UUID
    let teamID: String
    let team: String
    /// What Settings groups by. Defaults to the team; GitHub groups repos by owner.
    var groupID = ""
    /// Last push or similar, for "recently active" when there are no deploys yet.
    var activity: Date?
    /// Newest first. Always includes the current production deploy when there is one.
    let latest: [Deploy]

    var group: String { groupID.isEmpty ? teamID : groupID }
    var lastActive: Date? { latest.first?.createdAt ?? activity }
}

enum AppError: LocalizedError {
    case http(Int, Provider)
    case keychain

    /// The token lacks access, as opposed to a network blip or a 429/5xx worth retrying.
    var isAuth: Bool {
        if case .http(let code, _) = self { return [400, 401, 403].contains(code) }
        return false
    }

    var isRateLimit: Bool {
        if case .http(429, _) = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .http(401, let p), .http(403, let p), .http(400, let p): "\(p.name) rejected the token. Check its permissions or make a new one."
        case .http(429, let p): "\(p.name) is rate limiting. Trying again in a minute."
        case .http(let code, let p) where (500...599).contains(code): "\(p.name) is having trouble (\(code)). Checking again on the next poll."
        case .http(let code, let p): "\(p.name) returned an unexpected \(code)."
        case .keychain: "Couldn't save the token to Keychain."
        }
    }
}
