using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Repato.QaLaunchAgent;

public sealed record CpvPreparationRequest(int SchemaVersion, string Operation, string RequestId, string TaskId,
    string WorkflowId, string AttemptId, string RunId, DateTimeOffset ExpiresUtc, int TimeoutSeconds,
    QaCandidateEvidence CandidateEvidence);
public sealed record CpvPreparationQuery(int SchemaVersion, string Operation, string RequestId);
public sealed record CpvPreparationReconciliation(int SchemaVersion, string Operation, string RequestId, string TaskId,
    string WorkflowId, string AttemptId, string RunId);
public sealed record CpvPreparationReceipt(int SchemaVersion, string Operation, string RequestId, string TaskId,
    string WorkflowId, string AttemptId, string RunId, string Status, string User, string Sid, int SessionId,
    string CandidateSha256, string ManifestSha256, string ModelPath, string ModelSha256, string RequestPath,
    string RequestSha256, string ResultPath, string ResultSha256, bool CleanupVerified, string RollbackStatus,
    string? FailureCode, DateTimeOffset ExpiresUtc);
public sealed record CpvPreparationOutcome(string ModelSha256, string ResultSha256, bool CleanupVerified, string RollbackStatus);
public interface ICpvPreparationBoundary : ICpvPreparationReconciliationBoundary
{
    void Validate(CpvPreparationRequest request);
    Task<CpvPreparationOutcome> Execute(CpvPreparationRequest request, string directory);
}
public interface ICpvPreparationReconciliationBoundary
{
    IDisposable ValidateReconciliation(CpvPreparationRequest request, CpvPreparationReceipt receipt);
}

/// <summary>One fixed operation; no caller-selected executable, model, environment, or command.</summary>
public sealed class CpvPreparationService(QaAgentOptions options, IIdentitySessionProvider identity,
    IReplayLedger ledger, ICpvPreparationBoundary boundary)
{
    public const string Operation = "prepare-cpv-fixture";
    public const string StatusOperation = "cpv-preparation-status";
    public const string ReconcileOperation = "cpv-preparation-reconcile-failed";
    public const string CapabilitiesOperation = "cpv-preparation-capabilities";
    public const string RunnerOperation = "prepare-disposable-create-plan-views-fixture";
    public const string FixtureSha256 = "92CC9E434E2C4DD6720A2AA564E19F4E1A30EB3DA63CEA73CF737F875B9EDD45";
    public static readonly JsonSerializerOptions StrictJson = new(QaLaunchPolicy.JsonOptions) {
        PropertyNameCaseInsensitive = true, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };
    private readonly object gate = new();
    private readonly HashSet<string> running = new(StringComparer.Ordinal);
    private string Store => Path.Combine(options.LogRoot, "CpvPreparation");
    public bool HasUnresolvedExecution => File.Exists(Path.Combine(Store, "active.json"));
    private bool IdentityValid => identity.User.Equals(options.ExpectedUser, StringComparison.OrdinalIgnoreCase) &&
        identity.Sid == options.ExpectedUserSid && identity.Interactive && identity.SessionId > 0;
    public static bool Id(string? id) => Guid.TryParseExact(id, "N", out var value) && value != Guid.Empty;
    public object Capabilities() => new { schemaVersion = 1, operation = CapabilitiesOperation, supported = IdentityValid,
        preparationOperation = Operation, reconciliationOperation = ReconcileOperation, user = identity.User, sid = identity.Sid, sessionId = identity.SessionId };
    public object Handle(string json, DateTimeOffset now)
    {
        if (!IdentityValid) throw new InvalidDataException("wrong-agent-identity");
        using var doc = JsonDocument.Parse(json);
        RejectDuplicateProperties(doc.RootElement);
        string operation = doc.RootElement.GetProperty("operation").GetString() ?? "";
        if (operation == StatusOperation)
        {
            var query = JsonSerializer.Deserialize<CpvPreparationQuery>(json, StrictJson)!;
            if (query.SchemaVersion != 1 || !Id(query.RequestId)) throw new InvalidDataException("query-invalid");
            lock (gate) return Read(query.RequestId);
        }
        if (operation == ReconcileOperation)
        {
            var q = JsonSerializer.Deserialize<CpvPreparationReconciliation>(json, StrictJson)!;
            if (q.SchemaVersion != 1 || q.Operation != ReconcileOperation || !Id(q.RequestId) || !Id(q.AttemptId) ||
                !Id(q.RunId) || !Id(q.WorkflowId) || !q.TaskId.StartsWith("task-", StringComparison.Ordinal) || !Id(q.TaskId[5..]))
                throw new InvalidDataException("reconciliation-request-invalid");
            lock (gate) return Reconcile(q);
        }
        var r = JsonSerializer.Deserialize<CpvPreparationRequest>(json, StrictJson)!;
        if (r.SchemaVersion != 1 || r.Operation != Operation || !Id(r.RequestId) || !Id(r.AttemptId) || !Id(r.RunId) ||
            !Id(r.WorkflowId) || !r.TaskId.StartsWith("task-", StringComparison.Ordinal) || !Id(r.TaskId[5..]) ||
            r.ExpiresUtc <= now || r.ExpiresUtc > now.AddHours(4) || r.TimeoutSeconds < 60 || r.TimeoutSeconds > 7200 ||
            r.ExpiresUtc < now.AddSeconds(r.TimeoutSeconds) || r.CandidateEvidence is null ||
            r.CandidateEvidence.TaskId != r.TaskId || r.CandidateEvidence.WorkflowId != r.WorkflowId ||
            r.CandidateEvidence.QaWorkflowId != "create-plan-views-v1" || r.CandidateEvidence.TestId != "create-plan-views-v1")
            throw new InvalidDataException("preparation-request-invalid-or-expired");
        lock (gate)
        {
            Directory.CreateDirectory(Store);
            if (File.Exists(Path.Combine(Store, r.RequestId + ".json"))) return Read(r.RequestId) is CpvPreparationReceipt old &&
                old.TaskId == r.TaskId && old.WorkflowId == r.WorkflowId && old.AttemptId == r.AttemptId && old.RunId == r.RunId &&
                File.ReadAllText(Path.Combine(Store, r.RequestId + ".request.json")) == json ? old : throw new InvalidDataException("request-id-collision");
            // Durable marker intentionally survives agent termination. Never guess whether a child launched.
            string active = Path.Combine(Store, "active.json");
            if (File.Exists(active)) throw new InvalidOperationException("preparation-busy-or-interrupted-reconcile-required");
            boundary.Validate(r);
            if (!ledger.TryReserve("cpv-preparation-attempt-" + r.AttemptId, now) ||
                !ledger.TryReserve("cpv-preparation-run-" + r.RunId, now) || !ledger.TryReserve(r.RequestId, now))
                throw new InvalidOperationException("preparation-replayed");
            foreach (string key in new[] { "attempt-" + r.AttemptId, "run-" + r.RunId })
                using (var reserved = File.Open(Path.Combine(Store, key + ".reserved"), FileMode.CreateNew, FileAccess.Write, FileShare.None)) { reserved.Flush(true); }
            using (var file = new FileStream(active, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { JsonSerializer.Serialize(file, r, StrictJson); file.Flush(true); }
            WriteDurable(Path.Combine(Store, r.RequestId + ".request.json"), json);
            string directory = Path.Combine(options.RuntimeRoot, "cpv-preparation-" + r.RunId);
            if (Directory.Exists(directory)) throw new InvalidDataException("preparation-runtime-already-exists");
            var pending = new CpvPreparationReceipt(1, Operation, r.RequestId, r.TaskId, r.WorkflowId, r.AttemptId, r.RunId,
                "Executing", identity.User, identity.Sid, identity.SessionId, r.CandidateEvidence.CandidateDllSha256,
                r.CandidateEvidence.RunnerManifestSha256, Path.Combine(directory, "model.rvt"), "",
                Path.Combine(directory, "tara-" + r.AttemptId + ".request.json"), "", "", "", false, "Unknown", null, r.ExpiresUtc);
            Write(pending);
            running.Add(r.RequestId);
            _ = Task.Run(async () => {
                CpvPreparationReceipt terminal;
                try {
                    var outcome = await boundary.Execute(r, directory);
                    terminal = pending with { Status = outcome.CleanupVerified ? "Passed" : "Failed", ModelSha256 = outcome.ModelSha256,
                        RequestSha256 = Hash(pending.RequestPath), ResultPath = pending.RequestPath + ".preparation.json",
                        ResultSha256 = outcome.ResultSha256, CleanupVerified = outcome.CleanupVerified,
                        RollbackStatus = outcome.RollbackStatus, FailureCode = outcome.CleanupVerified ? null : "cleanup-failed" };
                } catch (Exception ex) {
                    File.WriteAllText(Path.Combine(Store, r.RequestId + ".failure.txt"), ex.ToString());
                    // A failed/ambiguous preparation never authorizes final QA. Preserve its marker and model.
                    terminal = pending with { Status = "OutcomeUnknown", FailureCode = ex is TimeoutException ? "preparation-timeout" : "preparation-failed-reconcile-required" };
                }
                lock (gate) { Write(terminal); running.Remove(r.RequestId); if (terminal.Status == "Passed") File.Delete(active); }
            });
            return pending;
        }
    }
    private object Reconcile(CpvPreparationReconciliation q)
    {
        Directory.CreateDirectory(Store);
        string activePath = Path.Combine(Store, "active.json"), receiptPath = Path.Combine(Store, q.RequestId + ".json");
        if (!File.Exists(receiptPath)) throw new InvalidDataException("reconciliation-receipt-missing");
        var receipt = JsonSerializer.Deserialize<CpvPreparationReceipt>(File.ReadAllText(receiptPath), StrictJson)
            ?? throw new InvalidDataException("reconciliation-receipt-invalid");
        Match(q, receipt);
        if (receipt.Status == "FailedReconciled")
        {
            if (receipt.FailureCode != "preparation-exited-without-result") throw new InvalidDataException("reconciliation-terminal-evidence-mismatch");
            if (File.Exists(activePath))
            {
                var active = ReadActive(activePath); Match(q, active);
                string terminalRequestPath = Path.Combine(Store, q.RequestId + ".request.json");
                if (!File.Exists(terminalRequestPath) || JsonSerializer.Serialize(active, StrictJson) !=
                    JsonSerializer.Serialize(JsonSerializer.Deserialize<CpvPreparationRequest>(File.ReadAllText(terminalRequestPath), StrictJson), StrictJson))
                    throw new InvalidDataException("reconciliation-active-request-mismatch");
            }
            File.Delete(activePath);
            return receipt;
        }
        if (receipt.Status != "OutcomeUnknown" || receipt.FailureCode != "preparation-failed-reconcile-required" ||
            receipt.CleanupVerified || receipt.ModelSha256 != "" || receipt.ResultPath != "" || receipt.ResultSha256 != "" ||
            receipt.RollbackStatus != "Unknown" || !File.Exists(activePath))
            throw new InvalidDataException("reconciliation-state-invalid");
        var request = ReadActive(activePath);
        Match(q, request);
        string requestPath = Path.Combine(Store, q.RequestId + ".request.json");
        string failurePath = Path.Combine(Store, q.RequestId + ".failure.txt");
        if (!File.Exists(requestPath) || !File.Exists(failurePath) ||
            !File.ReadAllText(failurePath).Contains("InvalidDataException: preparation-exited-without-result", StringComparison.Ordinal))
            throw new InvalidDataException("reconciliation-failure-evidence-invalid");
        var persisted = JsonSerializer.Deserialize<CpvPreparationRequest>(File.ReadAllText(requestPath), StrictJson)
            ?? throw new InvalidDataException("reconciliation-request-evidence-invalid");
        Match(q, persisted);
        if (JsonSerializer.Serialize(request, StrictJson) != JsonSerializer.Serialize(persisted, StrictJson))
            throw new InvalidDataException("reconciliation-active-request-mismatch");
        if (persisted.CandidateEvidence is null || receipt.CandidateSha256 != persisted.CandidateEvidence.CandidateDllSha256 ||
            receipt.ManifestSha256 != persisted.CandidateEvidence.RunnerManifestSha256 || receipt.ExpiresUtc != persisted.ExpiresUtc ||
            !Path.GetFullPath(receipt.ModelPath).Equals(Path.GetFullPath(Path.Combine(options.RuntimeRoot, "cpv-preparation-" + q.RunId, "model.rvt")), StringComparison.OrdinalIgnoreCase) ||
            !Path.GetFullPath(receipt.RequestPath).Equals(Path.GetFullPath(Path.Combine(options.RuntimeRoot, "cpv-preparation-" + q.RunId, "tara-" + q.AttemptId + ".request.json")), StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("reconciliation-path-binding-invalid");
        string runnerPath = receipt.RequestPath, resultPath = runnerPath + ".preparation.json", modelPath = receipt.ModelPath;
        if (!File.Exists(runnerPath) || File.Exists(resultPath) || File.Exists(modelPath + ".slog") || File.Exists(modelPath + ".lck"))
            throw new InvalidDataException("reconciliation-result-or-lock-evidence-present");
        var runner = JsonDocument.Parse(File.ReadAllText(runnerPath));
        using (runner)
        {
            var root = runner.RootElement;
            RejectDuplicateProperties(root);
            string[] expectedProperties = ["schemaVersion", "operation", "requestId", "taskId", "workflowId", "attemptId", "runId", "requestPath", "modelPath", "modelSha256", "selectedManifestPath", "selectedManifestSha256", "outputPath", "expiresUtc"];
            if (root.ValueKind != JsonValueKind.Object || root.EnumerateObject().Count() != expectedProperties.Length ||
                expectedProperties.Any(name => !root.TryGetProperty(name, out _)))
                throw new InvalidDataException("reconciliation-runner-request-schema-mismatch");
            if (root.GetProperty("operation").GetString() != RunnerOperation || root.GetProperty("requestId").GetString() != q.AttemptId ||
                root.GetProperty("taskId").GetString() != q.TaskId || root.GetProperty("workflowId").GetString() != q.WorkflowId ||
                root.GetProperty("attemptId").GetString() != q.AttemptId || root.GetProperty("runId").GetString() != q.RunId ||
                root.GetProperty("schemaVersion").GetInt32() != 1 ||
                !Path.GetFullPath(root.GetProperty("requestPath").GetString()!).Equals(Path.GetFullPath(runnerPath), StringComparison.OrdinalIgnoreCase) ||
                !Path.GetFullPath(root.GetProperty("modelPath").GetString()!).Equals(Path.GetFullPath(modelPath), StringComparison.OrdinalIgnoreCase) ||
                root.GetProperty("modelSha256").GetString() != FixtureSha256 ||
                root.GetProperty("selectedManifestPath").GetString() != QaLaunchPolicy.ExpectedRunnerManifestPath ||
                root.GetProperty("selectedManifestSha256").GetString() != persisted.CandidateEvidence.RunnerManifestSha256 ||
                !Path.GetFullPath(root.GetProperty("outputPath").GetString()!).Equals(Path.GetFullPath(resultPath), StringComparison.OrdinalIgnoreCase) ||
                DateTimeOffset.Parse(root.GetProperty("expiresUtc").GetString()!) != persisted.ExpiresUtc)
                throw new InvalidDataException("reconciliation-runner-request-mismatch");
        }
        if (!Hash(modelPath).Equals(FixtureSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("reconciliation-model-hash-mismatch");
        using var evidenceLease = boundary.ValidateReconciliation(persisted, receipt);
        var terminal = receipt with { Status = "FailedReconciled", RequestSha256 = Hash(runnerPath), FailureCode = "preparation-exited-without-result", CleanupVerified = false, RollbackStatus = "NotRequired-NoPreparationResult" };
        WriteReconciled(terminal); // Receipt is durable before the sole matching marker is removed.
        File.Delete(activePath);
        return terminal;
    }
    private static CpvPreparationRequest ReadActive(string path) => JsonSerializer.Deserialize<CpvPreparationRequest>(File.ReadAllText(path), StrictJson)
        ?? throw new InvalidDataException("reconciliation-active-marker-invalid");
    private static void Match(CpvPreparationReconciliation q, CpvPreparationRequest r)
    {
        if (q.RequestId != r.RequestId || q.TaskId != r.TaskId || q.WorkflowId != r.WorkflowId || q.AttemptId != r.AttemptId || q.RunId != r.RunId)
            throw new InvalidDataException("reconciliation-identity-mismatch");
    }
    private static void Match(CpvPreparationReconciliation q, CpvPreparationReceipt r)
    {
        if (q.RequestId != r.RequestId || q.TaskId != r.TaskId || q.WorkflowId != r.WorkflowId || q.AttemptId != r.AttemptId || q.RunId != r.RunId)
            throw new InvalidDataException("reconciliation-identity-mismatch");
    }
    private object Read(string id) {
        if (!File.Exists(Path.Combine(Store, id + ".json"))) return new { schemaVersion = 1, operation = StatusOperation, requestId = id, status = "NotFound" };
        var receipt = JsonSerializer.Deserialize<CpvPreparationReceipt>(File.ReadAllText(Path.Combine(Store, id + ".json")), StrictJson)!;
        return receipt.Status == "Executing" && !running.Contains(id) ? receipt with { Status = "OutcomeUnknown", FailureCode = "agent-interrupted-reconcile-required" } : receipt;
    }
    private void Write(CpvPreparationReceipt receipt) {
        string path = Path.Combine(Store, receipt.RequestId + ".json"), temporary = path + ".partial";
        WriteDurable(temporary, JsonSerializer.Serialize(receipt, StrictJson)); File.Move(temporary, path, true);
    }
    private void WriteReconciled(CpvPreparationReceipt receipt)
    {
        string path = Path.Combine(Store, receipt.RequestId + ".json"), temporary = path + "." + Guid.NewGuid().ToString("N") + ".reconcile.partial";
        string json = JsonSerializer.Serialize(receipt, StrictJson);
        WriteDurable(temporary, json);
        File.Move(temporary, path, true);
    }
    private static void WriteDurable(string path, string text) { using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None); using var writer = new StreamWriter(stream, leaveOpen: true); writer.Write(text); writer.Flush(); stream.Flush(true); }
    public static string Hash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
    private static void RejectDuplicateProperties(JsonElement element) {
        if (element.ValueKind != JsonValueKind.Object) return;
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in element.EnumerateObject()) { if (!names.Add(p.Name)) throw new InvalidDataException("duplicate-json-property"); RejectDuplicateProperties(p.Value); }
    }
}

public sealed class RevitCpvPreparationBoundary(QaAgentOptions options) : ICpvPreparationBoundary
{
    private const string Source = @"C:\Repato-Autonomous\Source\QA\Fixtures\CreatePlanViewsEmpty.rvt";
    public void Validate(CpvPreparationRequest r)
    {
        var e = r.CandidateEvidence;
        if (!QaLaunchPolicy.IsValidCandidateEvidence(e, r.TaskId, r.WorkflowId, "create-plan-views-v1", "create-plan-views-v1"))
            throw new InvalidDataException("candidate-invalid");
        NoLinks(e.CandidateDllPath); NoLinks(e.RunnerManifestPath); NoLinks(e.CandidateProvenancePath);
        NoLinks(options.RuntimeRoot); NoLinks(Source); NoLinks(Source.Replace(".rvt", ".provenance.json"));
        if (Process.GetProcessesByName("Revit").Length != 0) throw new InvalidDataException("revit-already-running");
        if (CpvPreparationService.Hash(Source) != CpvPreparationService.FixtureSha256) throw new InvalidDataException("source-fixture-integrity");
        using var provenance = JsonDocument.Parse(File.ReadAllText(Source.Replace(".rvt", ".provenance.json")));
        if (provenance.RootElement.GetProperty("fixtureId").GetString() != "CreatePlanViewsEmpty" ||
            provenance.RootElement.GetProperty("sourceSha256").GetString() != CpvPreparationService.FixtureSha256)
            throw new InvalidDataException("source-fixture-provenance");
        using var sourceLock = File.Open(Source, FileMode.Open, FileAccess.Read, FileShare.Read);
        var validated = StagingAdapter.ValidateDeployment(new(1, QaLaunchPolicy.ValidateDeploymentOperation, r.RequestId,
            e.CandidateSourceCommit, e.CandidateDllSha256, e.QaWorkflowId, e.TestId, r.TaskId, r.WorkflowId, e));
        if (!QaLaunchPolicy.CanPassDeploymentValidation(validated) || !validated.IsolationPassed ||
            !string.Equals(validated.ValidationIdentity, options.ExpectedUser, StringComparison.OrdinalIgnoreCase) ||
            validated.CandidateSha256 != e.CandidateDllSha256) throw new InvalidDataException("deployment-validation-failed");
    }
    public async Task<CpvPreparationOutcome> Execute(CpvPreparationRequest r, string directory)
    {
        Validate(r); // Recheck immediately before creating the sole disposable target.
        if (r.ExpiresUtc <= DateTimeOffset.UtcNow) throw new InvalidDataException("preparation-expired");
        Directory.CreateDirectory(directory); NoLinks(directory);
        string model = Path.Combine(directory, "model.rvt"), request = Path.Combine(directory, "tara-" + r.AttemptId + ".request.json"), result = request + ".preparation.json";
        File.Copy(Source, model, false);
        if (CpvPreparationService.Hash(model) != CpvPreparationService.FixtureSha256) throw new InvalidDataException("disposable-copy-integrity-failed");
        File.WriteAllText(model + ".fixture.json", JsonSerializer.Serialize(new { fixtureId = "CreatePlanViewsEmpty", sourceSha256 = CpvPreparationService.FixtureSha256 }));
        using (File.Open(model, FileMode.Open, FileAccess.Read, FileShare.None)) { }
        var runnerRequest = new { schemaVersion = 1, operation = CpvPreparationService.RunnerOperation, requestId = r.AttemptId,
            taskId = r.TaskId, workflowId = r.WorkflowId, attemptId = r.AttemptId, runId = r.RunId, requestPath = request,
            modelPath = model, modelSha256 = CpvPreparationService.FixtureSha256, selectedManifestPath = QaLaunchPolicy.ExpectedRunnerManifestPath,
            selectedManifestSha256 = r.CandidateEvidence.RunnerManifestSha256, outputPath = result, expiresUtc = r.ExpiresUtc };
        File.WriteAllText(request, JsonSerializer.Serialize(runnerRequest));
        var psi = new ProcessStartInfo(options.RevitExe) { UseShellExecute = false, WindowStyle = ProcessWindowStyle.Hidden };
        psi.ArgumentList.Add(model);
        foreach (var key in psi.Environment.Keys.ToArray()) if (key.StartsWith("REPATO_QA_", StringComparison.OrdinalIgnoreCase)) psi.Environment.Remove(key);
        psi.Environment["REPATO_QA_CREATE_PLAN_VIEWS_FIXTURE_PREPARATION"] = request;
        using var process = Process.Start(psi) ?? throw new InvalidOperationException("preparation-process-start-failed");
        try {
            if (process.SessionId != Process.GetCurrentProcess().SessionId || !Path.GetFullPath(process.MainModule!.FileName).Equals(Path.GetFullPath(options.RevitExe), StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("preparation-child-correlation-failed");
            var deadline = DateTimeOffset.UtcNow.AddSeconds(r.TimeoutSeconds);
            while (!File.Exists(result)) {
                if (process.HasExited) throw new InvalidDataException("preparation-exited-without-result");
                string? dialog = PreparationDialogs.FindOwnedDialog(process.Id);
                if (dialog is not null) throw new InvalidOperationException("Unattended preparation stopped at dialog: " + dialog);
                if (DateTimeOffset.UtcNow >= deadline || DateTimeOffset.UtcNow >= r.ExpiresUtc) throw new TimeoutException();
                await Task.Delay(250);
            }
            // The runner writes after Save, with exclusive file access. Wait for the writer to close.
            string json = "";
            while (true) {
                try { using var file = File.Open(result, FileMode.Open, FileAccess.Read, FileShare.Read); using var reader = new StreamReader(file); json = reader.ReadToEnd(); break; }
                catch (IOException) { if (DateTimeOffset.UtcNow >= deadline) throw new TimeoutException(); await Task.Delay(100); }
            }
            VerifyResult(json, r, model);
        } finally {
            // Only this owned child is terminated; no global Revit close/kill and no dialog dismissal.
            if (!process.HasExited) process.Kill(true);
            if (!process.WaitForExit(15000)) throw new IOException("preparation-cleanup-failed");
        }
        using (File.Open(model, FileMode.Open, FileAccess.Read, FileShare.None)) { }
        if (Directory.EnumerateFiles(directory, "*.slog").Any() || Directory.EnumerateFiles(directory, "*.lck").Any()) throw new IOException("preparation-model-lock-remains");
        if (CpvPreparationService.Hash(Source) != CpvPreparationService.FixtureSha256) throw new InvalidDataException("source-mutated");
        File.WriteAllText(model + ".fixture.json", JsonSerializer.Serialize(new {
            fixtureId = "CreatePlanViewsEmpty", sourceSha256 = CpvPreparationService.FixtureSha256,
            preparedModelSha256 = CpvPreparationService.Hash(model), fixturePreparationRequestPath = request,
            fixturePreparationRequestSha256 = CpvPreparationService.Hash(request), fixturePreparationResultPath = result,
            fixturePreparationResultSha256 = CpvPreparationService.Hash(result), fixturePreparationAttemptId = r.AttemptId,
            fixturePreparationRunId = r.RunId }));
        return new(CpvPreparationService.Hash(model), CpvPreparationService.Hash(result), true, "CommittedDisposableFixtureOnly");
    }
    public IDisposable ValidateReconciliation(CpvPreparationRequest request, CpvPreparationReceipt receipt)
    {
        static void RequireNoRevitProcess()
        {
            // Any unreadable process snapshot makes absence unprovable; never treat errors as no process.
            foreach (var process in Process.GetProcessesByName("Revit"))
            {
                using (process) throw new InvalidDataException("reconciliation-revit-process-present");
            }
        }
        RequireNoRevitProcess();
        var model = File.Open(receipt.ModelPath, FileMode.Open, FileAccess.Read, FileShare.None);
        try
        {
            if (!Convert.ToHexString(SHA256.HashData(model)).Equals(CpvPreparationService.FixtureSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("reconciliation-model-hash-mismatch");
            RequireNoRevitProcess();
            return model;
        }
        catch { model.Dispose(); throw; }
    }
    public static void VerifyResult(string json, CpvPreparationRequest r, string model) {
        using var d = JsonDocument.Parse(json); var e = d.RootElement;
        string Text(string n) => e.GetProperty(n).GetString() ?? "";
        if (Text("Status") != "Passed" || Text("Operation") != CpvPreparationService.RunnerOperation || Text("TaskId") != r.TaskId ||
            Text("WorkflowId") != r.WorkflowId || Text("AttemptId") != r.AttemptId || Text("RunId") != r.RunId ||
            Text("ModelPath") != model || Text("SourceModelSha256") != CpvPreparationService.FixtureSha256 || Text("PreparedModelSha256") != CpvPreparationService.Hash(model))
            throw new InvalidDataException("preparation-result-correlation-failed");
        var levels = e.GetProperty("Levels").EnumerateArray().ToArray();
        var expected = new[] { ("0", 0d), ("1", 4d), ("2", 7.8d) };
        if (levels.Length != 3 || levels.Select(l => l.GetProperty("ElementId").GetInt64()).Distinct().Count() != 3 || expected.Any(x => levels.Count(l => l.GetProperty("Name").GetString() == x.Item1 &&
            Math.Abs(l.GetProperty("ElevationMeters").GetDouble() - x.Item2) < 1e-7 && l.GetProperty("ElementId").GetInt64() > 0) != 1))
            throw new InvalidDataException("prepared-level-verification-failed");
    }
    public static void NoLinks(string path) {
        for (var current = new FileInfo(Path.GetFullPath(path)) as FileSystemInfo; current is not null; current = Directory.GetParent(current.FullName))
            if ((current.Attributes & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("reparse-path-rejected");
    }
}

internal static class PreparationDialogs
{
    private delegate bool WindowCallback(IntPtr window, IntPtr parameter);
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern bool EnumWindows(WindowCallback callback, IntPtr parameter);
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)] private static extern int GetClassName(IntPtr window, System.Text.StringBuilder text, int count);
    [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, System.Text.StringBuilder text, int count);
    public static string? FindOwnedDialog(int processId) {
        string? found = null;
        EnumWindows((window, _) => {
            GetWindowThreadProcessId(window, out uint owner); if (owner != processId) return true;
            var name = new System.Text.StringBuilder(256); GetClassName(window, name, name.Capacity);
            if (name.ToString() != "#32770") return true;
            var title = new System.Text.StringBuilder(1024); GetWindowText(window, title, title.Capacity);
            found = title.ToString(); return false;
        }, IntPtr.Zero);
        return found;
    }
}
