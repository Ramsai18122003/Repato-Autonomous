using System.Security.Cryptography;
using System.Text.Json;

namespace Repato.QaLaunchAgent;

/// <summary>Independent native envelope for the RCP runner. CPV schema 2 is intentionally unchanged.</summary>
public sealed record RcpQaLaunchRequest(
    int SchemaVersion, string Operation, string RequestId, string RequestSha256,
    string TaskId, string WorkflowId, string QaWorkflowId, string TestId,
    string AttemptId, string RunId, string ClaimId, string RequestPath,
    string RequestSha256ForRunner, string ModelPath, string ModelSha256,
    string FixtureId, string FixtureSha256, string FixtureEvidencePath, string FixtureEvidenceSha256,
    string CandidatePath, string CandidateSha256, string SupportArtifactPath, string SupportArtifactSha256,
    string ManifestPath, string ManifestSha256, string IsolationPolicyPath, string IsolationPolicySha256,
    DateTimeOffset ExpiresUtc);

public sealed record RcpQaLaunchResponse(int SchemaVersion, string Operation, string RequestId,
    string TaskId, string WorkflowId, string QaWorkflowId, string TestId, string AttemptId,
    string RunId, string ClaimId, bool Accepted, int? Pid, string? User, string? Sid,
    int? SessionId, DateTimeOffset? LaunchUtc, string? FailureCode);

public sealed record RcpQaLaunchRoots(string RuntimeRoot, string CandidateRoot, string ManifestRoot,
    string IsolationRoot, string ExpectedUser, string ExpectedSid);

public static class RcpQaLaunchPolicy
{
    public const int SchemaVersion = 1;
    public const string Operation = "launch-revit-rcp-qa-v1";
    public const string ToolId = "create-rcp-views-v1";
    public const string RunnerRequestOperation = "create-rcp-views-qa";

    public static string CanonicalSha256(string json)
    {
        using var doc = JsonDocument.Parse(json);
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            foreach (var property in doc.RootElement.EnumerateObject().OrderBy(p => p.Name, StringComparer.Ordinal))
            {
                writer.WritePropertyName(property.Name);
                if (property.Name.Equals("requestSha256", StringComparison.OrdinalIgnoreCase)) writer.WriteStringValue(new string('0', 64));
                else property.Value.WriteTo(writer);
            }
            writer.WriteEndObject();
        }
        return Convert.ToHexString(SHA256.HashData(stream.ToArray()));
    }

    public static void Validate(RcpQaLaunchRequest request, string rawJson, RcpQaLaunchRoots roots,
        ToolQaDescriptorBinding descriptor, DateTimeOffset now, string currentUser, string currentSid, bool interactive)
    {
        if (request.SchemaVersion != SchemaVersion || request.Operation != Operation ||
            request.QaWorkflowId != ToolId || request.TestId != descriptor.TestId ||
            descriptor.RequestSchemaVersion != 1 || descriptor.RequestOperation != RunnerRequestOperation ||
            !Guid.TryParseExact(request.RequestId, "N", out _) || !Guid.TryParseExact(request.AttemptId, "N", out _) ||
            !Guid.TryParseExact(request.RunId, "N", out _) || !Guid.TryParseExact(request.ClaimId, "N", out _) ||
            !Guid.TryParseExact(request.WorkflowId, "N", out _) || string.IsNullOrWhiteSpace(request.TaskId) ||
            request.ExpiresUtc <= now || !Hash(request.RequestSha256) || !interactive ||
            !currentUser.Equals(roots.ExpectedUser, StringComparison.OrdinalIgnoreCase) ||
            !currentSid.Equals(roots.ExpectedSid, StringComparison.OrdinalIgnoreCase) ||
            !CanonicalSha256(rawJson).Equals(request.RequestSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("RCP native request identity, schema, or expiry is invalid.");

        Check(request.RequestPath, roots.RuntimeRoot, request.RequestSha256ForRunner);
        Check(request.ModelPath, roots.RuntimeRoot, request.ModelSha256, ".rvt");
        Check(request.FixtureEvidencePath, roots.RuntimeRoot, request.FixtureEvidenceSha256, ".json");
        Check(request.CandidatePath, roots.CandidateRoot, request.CandidateSha256);
        Check(request.SupportArtifactPath, roots.CandidateRoot, request.SupportArtifactSha256);
        Check(request.ManifestPath, roots.ManifestRoot, request.ManifestSha256);
        if (!Path.GetFileName(request.ManifestPath).Equals(descriptor.ManifestFile, StringComparison.Ordinal))
            throw new InvalidDataException("RCP manifest filename does not match the registered runner.");
        Check(request.IsolationPolicyPath, roots.IsolationRoot, request.IsolationPolicySha256);
        if (string.IsNullOrWhiteSpace(request.FixtureId) || !Hash(request.FixtureSha256))
            throw new InvalidDataException("RCP fixture identity or source hash is invalid.");
    }

    /// <summary>Minimal immutable projection supplied only by the embedded, validated tool registry.</summary>
    public sealed record ToolQaDescriptorBinding(string ToolId, string TestId, string ManifestFile,
        int RequestSchemaVersion, string RequestOperation);

    private static void Check(string path, string root, string expectedHash, string? extension = null)
    {
        if (!Path.IsPathFullyQualified(path) || !Path.IsPathFullyQualified(root) ||
            !Under(Path.GetFullPath(path), Path.GetFullPath(root)) || !File.Exists(path) || !Hash(expectedHash) ||
            (extension is not null && !Path.GetExtension(path).Equals(extension, StringComparison.OrdinalIgnoreCase)) ||
            !Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))).Equals(expectedHash, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("RCP request path, root, extension, or artifact hash is invalid.");
    }

    private static bool Under(string path, string root) => path.StartsWith(root.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    private static bool Hash(string? value) => value is { Length: 64 } && value.All(Uri.IsHexDigit);
}
