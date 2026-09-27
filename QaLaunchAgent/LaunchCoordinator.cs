namespace Repato.QaLaunchAgent;

public sealed class LaunchCoordinator(QaAgentOptions options, IIdentitySessionProvider identity, IReplayLedger ledger, IChildProcessLauncher launcher, IChildProcessVerifier verifier)
{
    public QaLaunchResponse Handle(QaLaunchRequest request, DateTimeOffset now)
    {
        if (!identity.User.Equals(options.ExpectedUser, StringComparison.OrdinalIgnoreCase) || identity.Sid != options.ExpectedUserSid) return Reject(request, "wrong-agent-identity");
        if (!identity.Interactive) return Reject(request, "non-interactive-session");
        if (!QaLaunchPolicy.IsValidRequest(request, now)) return Reject(request, "request-invalid");
        if (!ledger.TryReserve(request, now)) return Reject(request, "request-replayed");
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
            return new(1, request.RequestId, true, child.Pid, child.User, child.SessionId, child.LaunchUtc, child.ImagePath, request.RequestPath, request.RunId, null);
        }
        catch { return Reject(request, "launcher-failed"); }
    }
    private static bool IsUnder(string path, string root) => Path.GetFullPath(path).StartsWith(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    private static string Hash(string path) => Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(path)));
    private static QaLaunchResponse Reject(QaLaunchRequest r, string code) => new(1, r?.RequestId ?? "", false, null, null, null, null, null, r?.RequestPath, r?.RunId, code);
}
