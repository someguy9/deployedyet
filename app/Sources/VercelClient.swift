import Foundation

/// One `/v10/projects` call per team returns every project with its latest deploys,
/// so a refresh costs 1 + teams requests no matter how many projects are picked.
struct VercelClient: ProviderClient {
    let token: String

    /// Projects from every team the token can see. A team that refuses (SSO-enforced, removed)
    /// is reported in `unreachable` instead of failing the whole account.
    func projects(account: Account, teams: Set<String>, discover: Bool) async throws -> (projects: [Project], unreachable: [TeamRef]) {
        let response: TeamsResponse = try await get("/v2/teams", ["limit": "100"])
        let teams = response.teams.filter { discover || teams.contains($0.id) }
        let results = await withTaskGroup(of: (team: TeamRef, projects: [Project], error: Error?).self) { group in
            for team in teams { group.addTask { await fetch(team, account: account) } }
            return await group.reduce(into: []) { $0.append($1) }
        }
        let failed = results.filter { $0.error != nil }
        if failed.count == teams.count, let error = failed.first?.error { throw error }
        return (results.flatMap(\.projects), failed.map(\.team))
    }

    private func fetch(_ team: Team, account: Account) async -> (team: TeamRef, projects: [Project], error: Error?) {
        let ref = TeamRef(id: team.id, name: team.name ?? team.slug)
        var out: [Project] = []
        do {
            var until: Int?
            repeat {
                var query = ["teamId": team.id, "limit": "100"]
                if let until { query["until"] = String(until) }
                let page: ProjectsResponse = try await get("/v10/projects", query)
                out += page.projects.map { $0.project(team: team, account: account) }
                let next = page.pagination?.next
                until = next == until ? nil : next // a repeating cursor would loop forever
            } while until != nil
            return (ref, out, nil)
        } catch {
            return (ref, [], error)
        }
    }

    /// Team name for a single-team token, else the Vercel username.
    func suggestedLabel() async throws -> String {
        let teams: TeamsResponse = try await get("/v2/teams", ["limit": "2"])
        if teams.teams.count == 1, let team = teams.teams.first { return team.name ?? team.slug }
        let me: UserResponse = try await get("/v2/user", [:])
        return me.user.name ?? me.user.username
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        try await getJSON("https://api.vercel.com", path, query, token: token, provider: .vercel)
    }
}

// MARK: - Wire format (only the fields we use, everything else ignored)

private struct TeamsResponse: Decodable {
    let teams: [Team]
}

private struct Team: Decodable {
    let id: String
    let slug: String
    let name: String?
}

private struct UserResponse: Decodable {
    let user: User
    struct User: Decodable { let username: String; let name: String? }
}

private struct ProjectsResponse: Decodable {
    let projects: [VProject]
    let pagination: Pagination?
    struct Pagination: Decodable { let next: Int? }
}

private struct VProject: Decodable {
    let id: String
    let name: String
    let latestDeployments: [VDeployment]
    let production: VDeployment?

    enum CodingKeys: String, CodingKey { case id, name, latestDeployments, targets }
    struct Targets: Decodable { let production: VDeployment? }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        // Lenient: a weird deploy payload shouldn't drop the whole project list.
        latestDeployments = ((try? c.decode([Lossy<VDeployment>].self, forKey: .latestDeployments)) ?? []).compactMap(\.value)
        production = (try? c.decode(Targets.self, forKey: .targets))?.production
    }

    func project(team: Team, account: Account) -> Project {
        var seen = Set<String>()
        let deploys = (latestDeployments + [production].compactMap { $0 })
            .filter { seen.insert($0.id).inserted }
            .map { $0.deploy(project: self, team: team, account: account) }
            .sorted { $0.createdAt > $1.createdAt }
        return Project(id: id, name: name, accountID: account.id, teamID: team.id, team: team.name ?? team.slug, latest: deploys)
    }
}

/// Decodes to nil instead of failing the surrounding array.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

private struct VDeployment: Decodable {
    let id: String
    let readyState: String?
    let target: String?
    let url: String?
    let createdAt: Double
    let buildingAt: Double?
    let readyAt: Double?
    let meta: Meta?

    struct Meta: Decodable {
        let githubCommitMessage, githubCommitRef, githubCommitSha: String?
        let gitlabCommitMessage, gitlabCommitRef, gitlabCommitSha: String?
        let bitbucketCommitMessage, bitbucketCommitRef, bitbucketCommitSha: String?
    }

    func deploy(project: VProject, team: Team, account: Account) -> Deploy {
        let state: DeployState = switch readyState {
        case "READY": .ready
        case "ERROR": .failed
        case "CANCELED": .canceled
        default: .building // QUEUED, INITIALIZING, BUILDING
        }
        let slug = id.hasPrefix("dpl_") ? String(id.dropFirst(4)) : id
        return Deploy(
            id: id,
            provider: .vercel,
            projectID: project.id,
            projectName: project.name,
            accountLabel: account.label,
            team: team.name ?? team.slug,
            state: state,
            isProduction: target == "production",
            branch: meta?.githubCommitRef ?? meta?.gitlabCommitRef ?? meta?.bitbucketCommitRef,
            message: meta?.githubCommitMessage ?? meta?.gitlabCommitMessage ?? meta?.bitbucketCommitMessage,
            createdAt: Date(timeIntervalSince1970: createdAt / 1000),
            startedAt: Date(timeIntervalSince1970: (buildingAt ?? createdAt) / 1000),
            duration: state != .ready ? nil : readyAt.map { ($0 - (buildingAt ?? createdAt)) / 1000 }.flatMap { $0 > 0 ? $0 : nil },
            url: URL(string: "https://vercel.com/\(team.slug)/\(project.name)/\(slug)"),
            siteURL: url.flatMap { URL(string: "https://\($0)") },
            projectURL: URL(string: "https://vercel.com/\(team.slug)/\(project.name)"),
            commit: meta?.githubCommitSha ?? meta?.gitlabCommitSha ?? meta?.bitbucketCommitSha
        )
    }
}
