using System.Security.Cryptography;
using System.Text.Json;
using Repato.QaLaunchAgent;
using Repato.ToolQaFramework;

static void Check(bool value, string message) { if (!value) throw new InvalidOperationException("FAILED: " + message); }
static void Reject(Action action, string message) { try { action(); } catch (InvalidDataException) { return; } throw new InvalidOperationException("FAILED: " + message); }
string root = Path.Combine(Path.GetTempPath(), "repato-rcp-native-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
try
{
    string runtime = Directory.CreateDirectory(Path.Combine(root, "runtime")).FullName;
    string candidate = Directory.CreateDirectory(Path.Combine(root, "candidate")).FullName;
    string manifests = Directory.CreateDirectory(Path.Combine(root, "manifests")).FullName;
    string isolation = Directory.CreateDirectory(Path.Combine(root, "isolation")).FullName;
    string Put(string dir, string name, string body) { var path = Path.Combine(dir, name); File.WriteAllText(path, body); return path; }
    string Hash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
    string model = Put(runtime, "model.rvt", "synthetic model");
    string evidence = Put(runtime, "fixture.evidence.json", "synthetic authenticated evidence");
    string requestPath = Put(runtime, "runner.request.json", "runner request");
    string artifact = Put(candidate, "Repato.Revit.dll", "candidate");
    string support = Put(candidate, "Repato.RcpQaRunner.dll", "runner support");
    string manifest = Put(manifests, "Repato.CreateRcpViews.TestRunner.addin", "manifest");
    string policy = Put(isolation, "isolation.json", "isolation policy");
    var req = new RcpQaLaunchRequest(1, RcpQaLaunchPolicy.Operation, Guid.NewGuid().ToString("N"), new string('0',64),
        "task-synthetic", Guid.NewGuid().ToString("N"), RcpQaLaunchPolicy.ToolId, RcpQaLaunchPolicy.ToolId,
        Guid.NewGuid().ToString("N"), Guid.NewGuid().ToString("N"), Guid.NewGuid().ToString("N"), requestPath, Hash(requestPath),
        model, Hash(model), "RcpEmptyThreeLevels", new string('A',64), evidence, Hash(evidence), artifact, Hash(artifact), support, Hash(support),
        manifest, Hash(manifest), policy, Hash(policy), DateTimeOffset.UtcNow.AddMinutes(15));
    string json = JsonSerializer.Serialize(req);
    req = req with { RequestSha256 = RcpQaLaunchPolicy.CanonicalSha256(json) };
    json = JsonSerializer.Serialize(req);
    var roots = new RcpQaLaunchRoots(runtime, candidate, manifests, isolation, "RepatoQA", "synthetic-sid");
    var descriptor = ToolQaRegistry.LoadBuiltIn().Get(RcpQaLaunchPolicy.ToolId);
    var binding = new RcpQaLaunchPolicy.ToolQaDescriptorBinding(descriptor.ToolId, descriptor.TestId, descriptor.ManifestFile, descriptor.RequestSchemaVersion, descriptor.RequestOperation);
    RcpQaLaunchPolicy.Validate(req, json, roots, binding, DateTimeOffset.UtcNow, "RepatoQA", "synthetic-sid", true);
    Check(true, "valid RCP schema 1 envelope and distinct evidence/model files accepted");
    Reject(() => RcpQaLaunchPolicy.Validate(req with { QaWorkflowId = "create-plan-views-v1" }, json, roots, binding, DateTimeOffset.UtcNow, "RepatoQA", "synthetic-sid", true), "cross-tool request rejected");
    Reject(() => RcpQaLaunchPolicy.Validate(req with { ExpiresUtc = DateTimeOffset.UtcNow.AddSeconds(-1) }, json, roots, binding, DateTimeOffset.UtcNow, "RepatoQA", "synthetic-sid", true), "expired request rejected");
    Reject(() => RcpQaLaunchPolicy.Validate(req with { CandidateSha256 = new string('B',64) }, json, roots, binding, DateTimeOffset.UtcNow, "RepatoQA", "synthetic-sid", true), "candidate hash mismatch rejected");
    Reject(() => RcpQaLaunchPolicy.Validate(req with { FixtureEvidencePath = model }, json, roots, binding, DateTimeOffset.UtcNow, "RepatoQA", "synthetic-sid", true), "fixture JSON path cannot be confused with model path");
    Reject(() => RcpQaLaunchPolicy.Validate(req, json, roots with { ManifestRoot = runtime }, binding, DateTimeOffset.UtcNow, "RepatoQA", "synthetic-sid", true), "manifest root mismatch rejected");
    Reject(() => RcpQaLaunchPolicy.Validate(req, json, roots, binding, DateTimeOffset.UtcNow, "wrong-user", "synthetic-sid", true), "wrong Windows identity rejected");
    Console.WriteLine("RCP native protocol contract passed: 7 assertions; temporary artifacts only; no process boundary invoked.");
}
finally { Directory.Delete(root, true); }
