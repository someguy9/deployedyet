#!/usr/bin/env python3
"""Exercise the real refresh implementation with in-memory providers, never user data."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'app/Sources/Store.swift').read_text()
def extract(start):
    pos = source.index(start)
    brace = source.index('{', pos)
    depth, end = 1, brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[pos:end]

fixture = r'''
import Foundation
struct TeamRef: Hashable { let id: String; let name: String }
struct Deploy { let id: String; let state: State }
enum State { case failed, ready, building }
struct Project { let id: String; let accountID: UUID; let teamID: String; let latest: [Deploy] }
struct Result { var projects: [Project]; var unreachable: [TeamRef]; var rateLimited: Bool }
struct Provider { func client(token: String) -> Client { Client() } }
struct Account { let id: UUID; let provider = Provider() }
struct Client { func projects(account: Account, teams: Set<String>, discover: Bool) async throws -> Result { if fixtureThrows { throw AppError.network }; return fixtureResult } }
enum AppError: Error { case network; var isAuth: Bool { false }; var isRateLimit: Bool { false } }
enum Keychain { static func get(_ id: UUID) -> String? { "synthetic" } }
struct Ack: Hashable { let accountID: UUID; let projectID: String; let deploymentID: String }
var fixtureThrows = false
var fixtureResult = Result(projects: [], unreachable: [], rateLimited: false)
@MainActor final class FixtureStore {
    var refreshing = false; var lastFull: Date?; var lastPicked: Date?; var lastAttempt: Date?
    var accounts: [Account] = []; var projects: [Project] = []; var selected: Set<String> = []
    var credentialVersions: [UUID: Int] = [:]; var backoff: [UUID: Date] = [:]
    var errors: [UUID: String] = [:]; var accountErrors: [UUID: String] = [:]
    var fullUnreachable: [UUID: [TeamRef]] = [:]; var lastSuccessfulChecks: [UUID: Date] = [:]
    var acknowledgedFailures: Set<Ack> = []; var known: Set<String>?
    func tracked(_ project: Project) -> [Deploy] { project.latest }
    func autoPick(_ projects: [Project], account: Account, client: Client, version: Int) async -> (projects: [Project], unreachable: [TeamRef], rateLimited: Bool) { (projects, [], false) }
    static func unreachableMessage(_ teams: [TeamRef]) -> String? { teams.isEmpty ? nil : "Unreachable" }
    static func writeCache(_ projects: [Project], successfulChecks: [UUID: Date]) {}
    func notifyFinished() {}; func updateWobble() {}
    REFRESH
}
@main struct Proof {
 @MainActor static func main() async {
    let store = FixtureStore(), id = UUID(), old = Date(timeIntervalSince1970: 100)
    let account = Account(id: id)
    let cached = Project(id: "p", accountID: id, teamID: "t", latest: [Deploy(id: "cached", state: .ready)])
    store.accounts = [account]; store.projects = [cached]; store.lastSuccessfulChecks[id] = old
    func check(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError(message) }; print("PASS \(message)") }
    fixtureThrows = true
    await store.refresh(full: true)
    check(store.lastSuccessfulChecks[id] == old && store.projects.first?.latest.first?.id == "cached", "thrown error preserves freshness and cached rows")
    fixtureThrows = false
    fixtureResult = Result(projects: [], unreachable: [TeamRef(id: "t", name: "Team")], rateLimited: false)
    await store.refresh(full: true)
    check(store.lastSuccessfulChecks[id] == old && store.projects.first?.latest.first?.id == "cached", "partial team failure preserves freshness and cached rows")
    let fresh = Project(id: "p", accountID: id, teamID: "t", latest: [Deploy(id: "fresh", state: .ready)])
    let retained = Project(id: "retained", accountID: id, teamID: "other", latest: [Deploy(id: "retained", state: .building)])
    store.projects.append(retained)
    fixtureResult = Result(projects: [fresh], unreachable: [], rateLimited: true)
    await store.refresh(full: true)
    let retry = store.backoff[id]!
    check(store.lastSuccessfulChecks[id] == old && store.projects.first?.latest.first?.id == "fresh" && store.projects.count == 2 && store.errors[id] != nil, "partial rate limit keeps fresh results ahead of cache, retains missing projects and remains degraded")
    fixtureResult = Result(projects: [], unreachable: [], rateLimited: false)
    await store.refresh(full: true)
    check(store.backoff[id] == retry && store.lastSuccessfulChecks[id] == old && store.projects.count == 2, "manual full refresh honors cooldown")
    store.backoff[id] = Date().addingTimeInterval(-1)
    await store.refresh(full: true)
    check(store.lastSuccessfulChecks[id]! > old && store.errors[id] == nil && store.projects.isEmpty, "complete successful check advances freshness and clears error")
 }
}
'''.replace('REFRESH', extract('func refresh(full: Bool = false) async'))
with tempfile.TemporaryDirectory(prefix='deployedyet-monitoring-proof-') as tmp:
    path = Path(tmp)
    (path / 'Proof.swift').write_text(fixture)
    subprocess.run(['swiftc', '-parse-as-library', str(path / 'Proof.swift'), '-o', str(path / 'proof')], check=True)
    subprocess.run([str(path / 'proof')], check=True)
