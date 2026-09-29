using System.Text.Json;

namespace Repato.QaLaunchAgent;

public sealed class LaunchCoordinator(QaAgentOptions options, IIdentitySessionProvider identity, IReplayLedger ledger, IChildProcessLauncher launcher, IChildProcessVerifier verifier)
{
    public QaStageResponse HandleStage(QaStageRequest? request, DateTimeOffset now)
    {
        if (!identity.User.Equals(options.ExpectedUser, StringComparison.OrdinalIgnoreCase) || identity.Sid != options.ExpectedUserSid || !identity.Interactive) return StageReject(request, "wrong-agent-identity");
        if (request is null || request.SchemaVersion != 1 || request.Operation != QaLaunchPolicy.StageOperation || !Guid.TryParse(request.RequestId, out _) || request.CandidateCommit != QaLaunchPolicy.FrozenCandidateCommit || request.ExpectedCandidateSha256 != QaLaunchPolicy.FrozenCandidateSha256 || request.QaWorkflowId != "create-plan-views-v1" || request.TestId != request.QaWorkflowId) return StageReject(request, "staging-request-invalid");
        if (!ledger.TryReserve(request.RequestId, now)) return StageReject(request, "staging-request-replayed");
        try
        {
            var result = StagingAdapter.Run(request);
            return result;
        }
        catch (Exception ex) { return StageReject(request, "staging-adapter-failed", ex.Message); }
    }

    public QaLaunchResponseV2 Handle(QaLaunchRequest request, DateTimeOffset now, string? rawJson = null)
    {
        if (!identity.User.Equals(options.ExpectedUser, StringComparison.OrdinalIgnoreCase) || identity.Sid != options.ExpectedUserSid) return Reject(request, "wrong-agent-identity");
        if (!identity.Interactive) return Reject(request, "non-interactive-session");
        if (!QaLaunchPolicy.IsValidRequest(request, now)) return Reject(request, "request-invalid");
        if (!ledger.TryReserve(request, now)) return Reject(request, "request-replayed");
        if (!QaLaunchPolicy.CanonicalRequestSha256(rawJson ?? JsonSerializer.Serialize(request, QaLaunchPolicy.JsonOptions)).Equals(request.RequestSha256, StringComparison.OrdinalIgnoreCase)) return Reject(request, "request-hash-mismatch");
        if (!IsUnder(request.RequestPath, options.RuntimeRoot) || !IsUnder(request.ModelPath, options.RuntimeRoot)) return Reject(request, "request-root-invalid");
        if (!IsUnder(request.ManifestPath, options.QaProfileRoot)) return Reject(request, "manifest-boundary-invalid");
        if (!File.Exists(request.ModelPath) || !File.Exists(request.ManifestPath)) return Reject(request, "artifact-unavailable");
        if (!Hash(request.ModelPath).Equals(request.ModelSha256, StringComparison.OrdinalIgnoreCase)) return Reject(request, "model-hash-mismatch");
        if (!Hash(request.ManifestPath).Equals(request.ManifestSha256, StringComparison.OrdinalIgnoreCase)) return Reject(request, "manifest-hash-mismatch");
        if (!File.Exists(options.RevitExe)) return Reject(request, "executable-unavailable");
        try
        {
            var child = launcher.Launch(request, options);
            if (!verifier.Verify(child, request, options)) return Reject(request, "process-correlation-failed");
            return new(2, request.Operation, request.RequestId, request.RequestId, true, child.Pid, child.User, child.Sid, child.SessionId, child.LaunchUtc, child.ImagePath, request.RequestPath, request.TaskId, request.WorkflowId, request.QaWorkflowId, request.TestId, request.AttemptId, request.RunId, null);
        }
        catch { return Reject(request, "launcher-failed"); }
    }
    private static bool IsUnder(string path, string root) => Path.GetFullPath(path).StartsWith(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    private static string Hash(string path) => Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(path)));
    private static QaLaunchResponseV2 Reject(QaLaunchRequest r, string code) => new(2, QaLaunchPolicy.Operation, r?.RequestId ?? "", r?.RequestId ?? "", false, null, null, null, null, null, null, r?.RequestPath, r?.TaskId, r?.WorkflowId, r?.QaWorkflowId, r?.TestId, r?.AttemptId, r?.RunId, code);
    private static QaStageResponse StageReject(QaStageRequest? r, string code, string? message = null) => new(1, QaLaunchPolicy.StageOperation, r?.RequestId ?? "", false, r?.CandidateCommit, r?.ExpectedCandidateSha256, r?.QaWorkflowId, r?.TestId, null, null, false, null, code, message);
}
