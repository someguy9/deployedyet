#!/usr/bin/env python3
"""Compile real row-selection and filtering code with synthetic, in-memory fixtures.

This does not construct Store, contact providers, or access app preferences/Keychain.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'app/Sources/Store.swift').read_text()

def extract(start, text=source):
    pos = text.index(start)
    brace = text.index('{', pos)
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[pos:end]

methods = '\n'.join(extract(name) for name in [
    'var rows: [Deploy]', 'var recentFetchedRows: [Deploy]',
    'func needsFailureAttention(', 'private func tracked(',
    'var overall: DeployState?', 'var headline: String',
])
fixture = r'''
import SwiftUI

final class FixtureStore {
    var projects: [Project] = []
    var selected: Set<String> = []
    var productionOnly: Set<String> = []
    var trackPreviews = true
    var monitoringDegraded = false
    func isAcknowledged(_ deploy: Deploy) -> Bool { false }
    METHODS
}

@main struct Proof {
    static func main() {
        let now = Date()
        let account = UUID()
        func deploy(_ id: String, _ state: DeployState, _ minutes: Double, production: Bool = true, provider: Provider = .vercel, project: String = "picked") -> Deploy {
            Deploy(id: id, provider: provider, projectID: project, projectName: project, accountLabel: "fixture", team: "team", state: state, isProduction: production, branch: "main", message: "message \(id)", createdAt: now.addingTimeInterval(-minutes * 60), startedAt: now, duration: nil, url: nil, siteURL: nil, projectURL: nil, commit: "sha-\(id)")
        }
        let current = deploy("current", .ready, 1)
        let active = deploy("active", .building, 2)
        let ready = deploy("old-ready", .ready, 3)
        let failed = deploy("old-failed", .failed, 4)
        let canceled = deploy("old-canceled", .canceled, 5)
        let preview = deploy("preview", .failed, 6, production: false)
        let other = deploy("other", .failed, 7, provider: .github, project: "other")
        let store = FixtureStore()
        store.projects = [Project(id: "picked", name: "picked", accountID: account, teamID: "team", team: "team", latest: [current, active, active, ready, failed, canceled, preview]), Project(id: "other", name: "other", accountID: account, teamID: "team", team: "team", latest: [other])]
        store.selected = ["picked"]
        func check(_ ok: @autoclosure () -> Bool, _ message: String) { if !ok() { fatalError(message) }; print("PASS \(message)") }
        let currentIDs = Set(store.rows.map(\.id))
        check(currentIDs == ["current", "active"], "default contains only newest and active rows")
        let beforeOverall = store.overall
        let beforeHeadline = store.headline
        let history = store.recentFetchedRows
        check(Set(history.map(\.id)) == ["current", "active", "old-ready", "old-failed", "old-canceled", "preview"], "history includes older ready, failed, canceled and selected previews")
        check(history.filter { $0.id == "active" }.count == 1, "duplicate active row removed")
        check(store.overall == beforeOverall && store.headline == beforeHeadline && beforeOverall == .building, "history does not change global status or headline")
        var filter = DeployFilter()
        filter.query = "old-failed"
        filter.provider = .vercel
        filter.state = .failed
        check(history.filter(filter.matches).map(\.id) == ["old-failed"], "combined search, provider and state filters apply")
        filter.provider = .github
        check(history.filter(filter.matches).isEmpty, "provider filter excludes nonmatching history")
        store.productionOnly = ["picked"]
        check(!store.recentFetchedRows.contains { $0.id == "preview" }, "per-project production-only excludes previews")
        store.productionOnly = []
        store.trackPreviews = false
        check(!store.recentFetchedRows.contains { $0.id == "preview" }, "global preview setting excludes previews")
        store.selected = ["other"]
        check(store.recentFetchedRows.map(\.id) == ["other"], "history respects project selection")
    }
}
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory(prefix='deployedyet-history-proof-') as tmp:
    path = Path(tmp)
    (path / 'Proof.swift').write_text(fixture)
    models = (root / 'app/Sources/Models.swift').read_text()
    models = models.replace(extract('func client(token:', models), '')
    (path / 'Models.swift').write_text(models)
    subprocess.run(['swiftc', str(path / 'Models.swift'), str(path / 'Proof.swift'), '-o', str(path / 'proof')], check=True)
    subprocess.run([str(path / 'proof')], check=True)
