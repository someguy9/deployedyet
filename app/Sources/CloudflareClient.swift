import Foundation

/// Workers + Pages across every Cloudflare account the token can see.
/// Per account: one `/workers/scripts` call (all Workers, last deploy time) plus paged `/pages/projects`
/// (each project's latest and production deploy with build stage).
// ponytail: Workers Builds (git CI for Workers) not read yet. It needs a user token with Builds scope, add when someone uses it.
struct CloudflareClient: ProviderClient {
    let token: String

    func projects(account: Account, teams: Set<String>, discover: Bool) async throws -> (projects: [Project], unreachable: [TeamRef]) {
        let accounts = try await allAccounts().filter { discover || teams.contains($0.id) }
        // All accounts at once: 18 accounts one by one took ~15s.
        let results = await withTaskGroup(of: (team: TeamRef, projects: [Project], error: Error?).self) { group in
            for cf in accounts { group.addTask { await fetch(cf, account: account) } }
            return await group.reduce(into: []) { $0.append($1) }
        }
        let failed = results.filter { $0.error != nil }
        if failed.count == accounts.count, failed.allSatisfy({ $0.projects.isEmpty }), let error = failed.first?.error { throw error }
        return (results.flatMap(\.projects), failed.map(\.team))
    }

    /// Workers and Pages for one Cloudflare account. An account can allow Workers but refuse Pages (403),
    /// and that's fine. A blip (429, 5xx, offline) on either one marks the account unreachable so the
    /// Store keeps its last-known projects instead of dropping half of them.
    private func fetch(_ cf: CFAccount, account: Account) async -> (team: TeamRef, projects: [Project], error: Error?) {
        var out: [Project] = []
        var errors: [Error] = []
        do {
            let scripts: Envelope<[Script]> = try await get("/accounts/\(cf.id)/workers/scripts", [:])
            out += scripts.result.map { $0.project(cf: cf, account: account) }
        } catch { errors.append(error) }
        do {
            var page = 1
            while true {
                // per_page caps at 10 for this endpoint (25 and 50 return error 8000024).
                let pages: Envelope<[PagesProject]> = try await get("/accounts/\(cf.id)/pages/projects", ["per_page": "10", "page": String(page)])
                out += pages.result.map { $0.project(cf: cf, account: account) }
                guard let info = pages.result_info, let total = info.total_pages, page < total else { break }
                page += 1
            }
        } catch { errors.append(error) }
        let transient = errors.first { !(($0 as? AppError)?.isAuth ?? false) }
        let error = transient ?? (errors.count == 2 ? errors[0] : nil)
        return (TeamRef(id: cf.id, name: cf.name), out, error)
    }

    /// The account name for a single-account token, else the user's email.
    func suggestedLabel() async throws -> String {
        let accounts = try await allAccounts()
        if accounts.count == 1, let only = accounts.first { return only.name }
        let me: Envelope<User> = try await get("/user", [:])
        return me.result.email ?? "Cloudflare"
    }

    private func allAccounts() async throws -> [CFAccount] {
        var out: [CFAccount] = []
        var page = 1
        while true {
            let response: Envelope<[CFAccount]> = try await get("/accounts", ["per_page": "50", "page": String(page)])
            out += response.result
            guard let info = response.result_info, let total = info.total_pages, page < total else { return out }
            page += 1
        }
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        try await getJSON("https://api.cloudflare.com/client/v4", path, query, token: token, provider: .cloudflare)
    }
}

// MARK: - Wire format

private struct Envelope<T: Decodable>: Decodable {
    let result: T
    let result_info: Info?
    struct Info: Decodable { let total_pages: Int? }
}

private struct User: Decodable {
    let email: String?
}

private struct CFAccount: Decodable {
    let id: String
    let name: String
}

private func date(_ string: String?) -> Date? {
    string.flatMap { try? Date($0, strategy: .iso8601) }
}

private struct Script: Decodable {
    let id: String // the Worker name
    let modified_on: String?
    let etag: String?
    let last_deployed_from: String?
    let routes: [Route]?
    struct Route: Decodable { let pattern: String }

    func project(cf: CFAccount, account: Account) -> Project {
        let projectID = "cf-worker:\(cf.id):\(id)"
        let deployed = date(modified_on) ?? .distantPast
        // Route patterns look like "example.com/path*"; good enough for an "Open site" link.
        let site = routes?.first.map {
            $0.pattern.replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        }
            .flatMap { $0.hasPrefix(".") ? nil : URL(string: "https://\($0)") }
        let dashboard = URL(string: "https://dash.cloudflare.com/\(cf.id)/workers/services/view/\(id)/production")
        let source = last_deployed_from.flatMap { $0.isEmpty ? nil : $0 }
        let deploy = Deploy(
            // etag is the script content hash: it moves on a code deploy but not on a secret or setting edit,
            // which would otherwise post a false "Deployed". (deployment_id comes back empty in the list.)
            // ponytail: a config-only redeploy with identical code won't notify; fetch /deployments if that matters.
            id: "\(projectID):\(etag.flatMap { $0.isEmpty ? nil : $0 } ?? modified_on ?? "")",
            provider: .cloudflare,
            projectID: projectID,
            projectName: id,
            accountLabel: account.label,
            team: cf.name,
            state: .ready, // a Worker version is live the moment it exists
            isProduction: true,
            branch: nil,
            message: source.map { "Deployed with \($0 == "cf_cli" ? "cf" : $0)" },
            createdAt: deployed,
            startedAt: deployed,
            duration: nil,
            url: dashboard,
            siteURL: site,
            projectURL: dashboard,
            isManual: true
        )
        return Project(id: projectID, name: id, accountID: account.id, teamID: cf.id, team: cf.name, latest: [deploy])
    }
}

private struct PagesProject: Decodable {
    let id: String
    let name: String
    let latest_deployment: PagesDeploy?
    let canonical_deployment: PagesDeploy?

    func project(cf: CFAccount, account: Account) -> Project {
        let projectID = "cf-pages:\(id)"
        var seen = Set<String>()
        let deploys = [latest_deployment, canonical_deployment].compactMap { $0 }
            .filter { seen.insert($0.id).inserted }
            .map { $0.deploy(projectID: projectID, project: self, cf: cf, account: account) }
            .sorted { $0.createdAt > $1.createdAt }
        return Project(id: projectID, name: name, accountID: account.id, teamID: cf.id, team: cf.name, latest: deploys)
    }
}

private struct PagesDeploy: Decodable {
    let id: String
    let environment: String?
    let url: String?
    let created_on: String?
    let latest_stage: Stage?
    let stages: [Stage]?
    let is_skipped: Bool?
    let deployment_trigger: Trigger?

    struct Stage: Decodable {
        let name: String?
        let status: String?
        let started_on: String?
        let ended_on: String?
    }

    struct Trigger: Decodable {
        let metadata: Metadata?
        struct Metadata: Decodable { let branch: String?; let commit_message: String?; let commit_hash: String? }
    }

    func deploy(projectID: String, project: PagesProject, cf: CFAccount, account: Account) -> Deploy {
        // Stages run queued → initialize → clone_repo → build → deploy. Only a successful "deploy" stage is live.
        let state: DeployState = switch (latest_stage?.status, latest_stage?.name) {
        case _ where is_skipped == true: .canceled // branch rules or watch paths skipped it; never "building"
        case ("skipped", _): .canceled
        case ("failure", _): .failed
        case ("canceled", _): .canceled
        case ("success", "deploy"): .ready
        default: .building
        }
        let created = date(created_on) ?? .distantPast
        let started = stages?.first { $0.name == "build" }.flatMap { date($0.started_on) } ?? created
        let ended = state == .ready ? date(latest_stage?.ended_on) : nil
        return Deploy(
            id: id,
            provider: .cloudflare,
            projectID: projectID,
            projectName: project.name,
            accountLabel: account.label,
            team: cf.name,
            state: state,
            isProduction: environment == "production",
            branch: deployment_trigger?.metadata?.branch,
            message: deployment_trigger?.metadata?.commit_message,
            createdAt: created,
            startedAt: started,
            duration: ended.map { $0.timeIntervalSince(started) }.flatMap { $0 > 0 ? $0 : nil },
            url: URL(string: "https://dash.cloudflare.com/\(cf.id)/pages/view/\(project.name)/\(id)"),
            siteURL: url.flatMap(URL.init(string:)),
            projectURL: URL(string: "https://dash.cloudflare.com/\(cf.id)/pages/view/\(project.name)"),
            commit: deployment_trigger?.metadata?.commit_hash
        )
    }
}
