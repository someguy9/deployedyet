import Foundation
import os

/// GitHub Actions: anything that deploys from CI (Convex, Fly, a `wrangler deploy` step) shows up as a workflow run.
/// Each repo is its own "team" so a building repo can be polled every 5s without re-asking for the rest.
/// Discovery lists repos only; runs are fetched just for picked repos (one call each), since a token can see hundreds.
/// A row is a commit, not a run: CI + Lint + Deploy on one push is one deploy, building until all finish.
// ponytail: no ETag/If-None-Match caching. 5,000 requests/hour covers ~80 picked repos at 60s; add it past that.
struct GitHubClient: ProviderClient {
    let token: String

    /// Default branches learned on discovery. Runs don't carry it, and the first refresh of every launch is a full one.
    private static let defaultBranches = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    func projects(account: Account, teams: Set<String>, discover: Bool) async throws -> (projects: [Project], unreachable: [TeamRef]) {
        var repos: [Repo]
        if discover {
            repos = []
            for page in 1...3 { // 300 most recently pushed is plenty for a picker
                let batch: [Repo] = try await get("/user/repos", ["per_page": "100", "sort": "pushed", "page": String(page)])
                repos += batch.filter { !$0.archived }
                if batch.count < 100 { break }
            }
            let listed = repos
            Self.defaultBranches.withLock { known in
                for repo in listed { known[repo.full_name] = repo.default_branch }
            }
            // A picked repo past the 300 most recent stays picked and polled.
            repos += teams.subtracting(repos.map(\.full_name)).map { Repo(stub: $0) }
        } else {
            // Polling: only picked repos, rebuilt from ids ("owner/name") without a listing call.
            repos = teams.map { Repo(stub: $0) }
        }

        let wanted = repos.filter { teams.contains($0.full_name) }
        let results = await withTaskGroup(of: (repo: String, runs: [Run]?, error: Error?).self) { group in
            for repo in wanted {
                group.addTask {
                    do {
                        let r: RunsResponse = try await get("/repos/\(repo.full_name)/actions/runs", ["per_page": "20"])
                        return (repo.full_name, r.workflow_runs, nil)
                    } catch {
                        return (repo.full_name, nil, error)
                    }
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        let runs = Dictionary(results.compactMap { r in r.runs.map { (r.repo, $0) } }, uniquingKeysWith: { a, _ in a })
        let failed = results.filter { $0.error != nil }
        if !wanted.isEmpty, failed.count == wanted.count, !discover, let error = failed.first?.error { throw error }

        // Repos that failed to load runs keep their last-known runs in the Store; leave them out here.
        let projects = repos
            .filter { !failed.map(\.repo).contains($0.full_name) }
            .map { $0.project(runs: runs[$0.full_name] ?? [], account: account) }
        return (projects, failed.map { TeamRef(id: $0.repo, name: $0.repo) })
    }

    func suggestedLabel() async throws -> String {
        let me: User = try await get("/user", [:])
        return me.login
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        try await getJSON("https://api.github.com", path, query, token: token, provider: .github)
    }

    fileprivate static func defaultBranch(_ repo: String) -> String? {
        defaultBranches.withLock { $0[repo] }
    }
}

// MARK: - Wire format

private struct User: Decodable {
    let login: String
}

private struct Repo: Decodable {
    let full_name: String
    let default_branch: String?
    let pushed_at: String?
    let archived: Bool

    init(stub fullName: String) {
        full_name = fullName
        default_branch = GitHubClient.defaultBranch(fullName)
        pushed_at = nil
        archived = false
    }

    var owner: String { String(full_name.split(separator: "/").first ?? "") }
    var name: String { String(full_name.split(separator: "/").last ?? "") }

    func project(runs: [Run], account: Account) -> Project {
        let projectID = "gh:\(full_name)"
        // Cron jobs, Dependabot and CodeQL aren't deploys; a failing nightly shouldn't turn the menu red.
        let relevant = runs.filter { !["schedule", "dynamic"].contains($0.event ?? "") }
        let deploys = Dictionary(grouping: relevant, by: { $0.head_sha ?? String($0.id) })
            .map { sha, runs in Run.deploy(sha: sha, runs: runs, projectID: projectID, repo: self, account: account) }
            .sorted { $0.createdAt > $1.createdAt }
        return Project(
            id: projectID, name: name, accountID: account.id,
            teamID: full_name, team: owner, groupID: owner,
            activity: pushed_at.flatMap { try? Date($0, strategy: .iso8601) },
            latest: deploys
        )
    }
}

private struct RunsResponse: Decodable {
    let workflow_runs: [Run]
}

private struct Run: Decodable {
    let id: Int
    let name: String?
    let head_branch: String?
    let head_sha: String?
    let event: String?
    let status: String?
    let conclusion: String?
    let run_attempt: Int?
    let created_at: String?
    let run_started_at: String?
    let updated_at: String?
    let html_url: String?
    let head_commit: Commit?
    struct Commit: Decodable { let message: String? }

    var state: DeployState {
        switch (status, conclusion) {
        case ("completed", "success"): .ready
        case ("completed", "failure"), ("completed", "timed_out"), ("completed", "startup_failure"): .failed
        case ("completed", _): .canceled // cancelled, skipped, neutral, stale, action_required
        default: .building // queued, in_progress, waiting, requested, pending
        }
    }

    var started: Date? { run_started_at.flatMap { try? Date($0, strategy: .iso8601) } }

    /// A re-run keeps its original created_at; count it from when the new attempt started.
    var created: Date {
        let original = created_at.flatMap { try? Date($0, strategy: .iso8601) } ?? .distantPast
        return (run_attempt ?? 1) > 1 ? (started ?? original) : original
    }

    /// All runs for one commit become one deploy: building if any run is, else failed if any failed.
    static func deploy(sha: String, runs: [Run], projectID: String, repo: Repo, account: Account) -> Deploy {
        let states = runs.map(\.state)
        let state: DeployState = states.contains(.building) ? .building
            : states.contains(.failed) ? .failed
            : states.contains(.ready) ? .ready : .canceled
        let first = runs.min { $0.created < $1.created }!
        let createdAt = first.created
        let startedAt = runs.compactMap(\.started).min() ?? createdAt
        let ended = state == .ready ? runs.compactMap { $0.updated_at.flatMap { try? Date($0, strategy: .iso8601) } }.max() : nil
        let defaultBranch = repo.default_branch ?? "main"
        // PR runs build the PR's code even when its branch is called main (forks), so they're previews.
        let production = runs.contains { $0.head_branch == defaultBranch && !["pull_request", "pull_request_target"].contains($0.event ?? "") }
        let workflows = runs.compactMap(\.name)
        let commit = first.head_commit?.message?.components(separatedBy: .newlines).first
        let label = workflows.count == 1 ? workflows[0] : "\(workflows.count) workflows"
        return Deploy(
            id: "gh:\(repo.full_name):\(sha)",
            provider: .github,
            projectID: projectID,
            projectName: repo.name,
            accountLabel: account.label,
            team: repo.owner,
            state: state,
            isProduction: production,
            branch: first.head_branch,
            message: [label, commit].compactMap { $0 }.joined(separator: ": "),
            createdAt: createdAt,
            startedAt: startedAt,
            duration: ended.map { $0.timeIntervalSince(startedAt) }.flatMap { $0 > 0 ? $0 : nil },
            url: runs.count == 1 ? first.html_url.flatMap(URL.init(string:))
                : URL(string: "https://github.com/\(repo.full_name)/commit/\(sha)/checks"),
            siteURL: nil,
            projectURL: URL(string: "https://github.com/\(repo.full_name)/actions"),
            commit: first.head_sha
        )
    }
}
