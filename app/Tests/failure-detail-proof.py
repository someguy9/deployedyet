#!/usr/bin/env python3
"""Compile actual provider decoders/mappers with synthetic data; no network or app state."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
sources = root / 'app/Sources'
# One translation unit makes the providers' private wire types visible to the fixture.
models = (sources / 'Models.swift').read_text()
vercel = (sources / 'VercelClient.swift').read_text()
cloudflare = (sources / 'CloudflareClient.swift').read_text().replace('Envelope<User>', 'Envelope<CFUser>').replace('struct User: Decodable', 'struct CFUser: Decodable')
stub = '''
struct GitHubClient: ProviderClient {
    let token: String
    func projects(account: Account, teams: Set<String>, discover: Bool) async throws -> (projects: [Project], unreachable: [TeamRef], rateLimited: Bool) { fatalError() }
    func suggestedLabel() async throws -> String { fatalError() }
}
'''
fixture = r'''
@main struct Proof {
 static func main() throws {
    let decoder = JSONDecoder()
    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try decoder.decode(type, from: Data(json.utf8)) }
    func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label); print("PASS \(label)") }
    let account = Account(label: "fixture", provider: .vercel)
    let team = try decode(Team.self, #"{"id":"team","slug":"team"}"#)
    func vercel(_ deployment: String) throws -> Deploy {
        let project = try decode(VProject.self, "{\"id\":\"p\",\"name\":\"example\",\"latestDeployments\":[\(deployment)]}")
        return project.project(team: team, account: account).latest[0]
    }
    let v = try vercel(#"{"id":"dpl_a","createdAt":1000,"readyState":"ERROR","aliasError":{"message":"Domain could not be assigned","code":"ALIAS_FAILED"}}"#)
    check(v.failureDetail == "Domain could not be assigned (ALIAS_FAILED)", "Vercel alias error message and code")
    let code = try vercel(#"{"id":"dpl_b","createdAt":1000,"readyState":"ERROR","aliasError":{"code":"ALIAS_FAILED"}}"#)
    check(code.failureDetail == "ALIAS_FAILED", "Vercel alias error code only")
    let missing = try vercel(#"{"id":"dpl_c","createdAt":1000,"readyState":"ERROR"}"#)
    check(missing.failureDetail == nil, "missing Vercel diagnosis")
    let ready = try vercel(#"{"id":"dpl_d","createdAt":1000,"readyState":"READY","aliasError":{"message":"old"}}"#)
    check(ready.failureDetail == nil, "nonfailed Vercel ignores error")
    let cf = try decode(CFAccount.self, #"{"id":"cf","name":"fixture"}"#)
    func pages(_ stage: String) throws -> Deploy {
        let project = try decode(PagesProject.self, "{\"id\":\"p\",\"name\":\"example\",\"latest_deployment\":{\"id\":\"d\",\"latest_stage\":\(stage)}}")
        return project.project(cf: cf, account: account).latest[0]
    }
    let page = try pages(#"{"name":"clone_repo","status":"failure"}"#)
    check(page.failureDetail == "Clone repo failed", "Pages failed stage")
    let noStage = try pages(#"{"status":"failure"}"#)
    check(noStage.failureDetail == nil, "Pages missing stage name")
    let skipped = try pages(#"{"name":"build","status":"skipped"}"#)
    check(skipped.failureDetail == nil, "Pages skipped stage")
    let script = try decode(Script.self, #"{"id":"example"}"#)
    func worker(_ outcome: String) throws -> Deploy {
        let build = try decode(Build.self, "{\"build_uuid\":\"b\",\"created_on\":\"2025-01-01T00:00:00Z\",\"status\":\"stopped\",\"build_outcome\":\"\(outcome)\"}")
        return script.project(cf: cf, account: account, build: build).latest.first { $0.id == "b" }!
    }
    let terminated = try worker("terminated")
    let failed = try worker("fail")
    check(terminated.failureDetail == "Build terminated", "Workers terminated outcome")
    check(failed.failureDetail == nil, "Workers generic failure has no invented reason")
    let encoded = try JSONEncoder().encode(v)
    var old = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    old.removeValue(forKey: "failureDetail")
    let oldDeploy = try decoder.decode(Deploy.self, from: JSONSerialization.data(withJSONObject: old))
    check(oldDeploy.failureDetail == nil && oldDeploy.id == v.id, "old cached deployment decodes")
    check(try decoder.decode(Deploy.self, from: encoded).failureDetail == v.failureDetail, "cached detail round trip")
 }
}
'''
# Throwing operations must happen outside the nonthrowing check autoclosure.
fixture = fixture.replace('    check(try decoder.decode(Deploy.self, from: encoded).failureDetail == v.failureDetail, "cached detail round trip")', '    let roundTrip = try decoder.decode(Deploy.self, from: encoded)\n    check(roundTrip.failureDetail == v.failureDetail, "cached detail round trip")')
with tempfile.TemporaryDirectory() as tmp:
    source = Path(tmp) / 'proof.swift'
    source.write_text(models + '\n' + vercel + '\n' + cloudflare + '\n' + stub + '\n' + fixture)
    binary = Path(tmp) / 'proof'
    subprocess.run(['swiftc', '-parse-as-library', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
