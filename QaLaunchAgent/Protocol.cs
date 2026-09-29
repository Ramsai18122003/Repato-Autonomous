using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Repato.QaLaunchAgent;

public sealed record QaLaunchRequest(
    int SchemaVersion, string Operation, string RequestId, string TaskId,
    string WorkflowId, string QaWorkflowId, string TestId, string AttemptId,
    string RunId, string ClaimId, string RequestPath, string RequestSha256,
    string ModelPath, string ModelSha256, string ManifestPath,
    string ManifestSha256, DateTimeOffset ExpiresUtc);

public sealed record QaLaunchResponse(
    int SchemaVersion, string RequestId, bool Accepted, int? Pid, string? User,
    int? SessionId, DateTimeOffset? LaunchUtc, string? ImagePath,
    string? RequestPath, string? RunId, string? FailureCode);

public sealed record QaLaunchResponseV2(
    int SchemaVersion, string Operation, string RequestId, string CorrelationId,
    bool Accepted, int? Pid, string? User, string? Sid, int? SessionId,
    DateTimeOffset? LaunchUtc, string? ImagePath, string? RequestPath,
    string? TaskId, string? WorkflowId, string? QaWorkflowId, string? TestId,
    string? AttemptId, string? RunId, string? FailureCode);

public sealed record QaHealthRequest(int SchemaVersion, string Operation);
public sealed record QaHealthResponse(int SchemaVersion, string Operation, bool Ready, string User, string Sid, int SessionId, bool Interactive, string? FailureCode);
public sealed record QaStageRequest(int SchemaVersion, string Operation, string RequestId, string CandidateCommit, string ExpectedCandidateSha256, string QaWorkflowId, string TestId);
public sealed record QaStageResponse(int SchemaVersion, string Operation, string RequestId, bool Succeeded, string? CandidateCommit, string? CandidateSha256, string? QaWorkflowId, string? TestId, string? StagingIdentity, string? QaAddinRoot, bool IsolationPassed, string? ReceiptPath, string? ErrorCode, string? ErrorMessage);
public sealed record QaDeploymentValidationRequest(int SchemaVersion, string Operation, string RequestId, string CandidateCommit, string ExpectedCandidateSha256, string QaWorkflowId, string TestId);
public sealed record QaDeploymentValidationResponse(int SchemaVersion, string Operation, string RequestId, bool Succeeded, string? CandidateCommit, string? CandidateSha256, string? QaWorkflowId, string? TestId, string? ValidationIdentity, string? QaAddinRoot, bool IsolationPassed, string? ErrorCode, string? ErrorMessage);

public static class QaLaunchPolicy
{
    public const int SchemaVersion = 1;
    public const int LaunchSchemaVersion = 2;
    public const string Operation = "launch-revit-qa";
    public const string HealthOperation = "health";
    public const string StageOperation = "stage-frozen-candidate-for-qa";
    public const string ValidateDeploymentOperation = "validate-qa-deployment";
    public const string ExpectedUser = "RAMSAI\\RepatoQA";
    public const string ExpectedUserSid = "S-1-5-21-1031246752-3872016183-2454652381-1015";
    public const string ClientAccount = "RAMSAI\\rsgud";
    public const string ClientSid = "S-1-5-21-1031246752-3872016183-2454652381-1001";
    public const string FrozenCandidateCommit = "fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3";
    public const string FrozenCandidateSha256 = "7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2";
    public const string StagingAdapterPath = @"C:\Repato-Autonomous\Source\AgentOrchestration\Invoke-RepatoQaFrozenCandidateStaging.ps1";
    public const string StagingCandidateDirectory = @"C:\Repato-Autonomous\Source\DeploymentCandidates\AgentBuilds\ReleaseCandidate-fcf624ee3ed1";
    public const string LogRoot = @"C:\Users\RepatoQA\AppData\Local\Repato\QaLaunchAgent\Logs";
    public const string RequestEnvironmentVariable = "REPATO_QA_CREATE_PLAN_VIEWS_REQUEST";
    public static readonly string[] AllowedQaWorkflows = ["create-plan-views-v1"];
    public const string RequestSha256Placeholder = "0000000000000000000000000000000000000000000000000000000000000000";
    public static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.General) { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true };
    public static string CanonicalRequestSha256(string json)
    {
        using var document = JsonDocument.Parse(json);
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = false }))
        {
            writer.WriteStartObject();
            foreach (var property in document.RootElement.EnumerateObject().OrderBy(p => p.Name, StringComparer.Ordinal))
            {
                writer.WritePropertyName(property.Name);
                if (property.Name.Equals("requestSha256", StringComparison.OrdinalIgnoreCase)) writer.WriteStringValue(RequestSha256Placeholder);
                else property.Value.WriteTo(writer);
            }
            writer.WriteEndObject();
        }
        return Convert.ToHexString(SHA256.HashData(stream.ToArray()));
    }
    public static bool IsValidRequest(QaLaunchRequest r, DateTimeOffset now) =>
        r is not null && r.SchemaVersion == LaunchSchemaVersion && r.Operation == Operation &&
        Guid.TryParse(r.RequestId, out _) &&
        !string.IsNullOrWhiteSpace(r.TaskId) && !string.IsNullOrWhiteSpace(r.WorkflowId) &&
        !string.IsNullOrWhiteSpace(r.QaWorkflowId) && !string.IsNullOrWhiteSpace(r.TestId) &&
        !string.IsNullOrWhiteSpace(r.AttemptId) && !string.IsNullOrWhiteSpace(r.RunId) &&
        !string.IsNullOrWhiteSpace(r.ClaimId) && !string.IsNullOrWhiteSpace(r.RequestPath) &&
        !string.IsNullOrWhiteSpace(r.ModelPath) && !string.IsNullOrWhiteSpace(r.ManifestPath) &&
        IsSha256(r.RequestSha256) && IsSha256(r.ModelSha256) && IsSha256(r.ManifestSha256) &&
        AllowedQaWorkflows.Contains(r.QaWorkflowId) && r.TestId == r.QaWorkflowId && r.ExpiresUtc > now;

    private static bool IsSha256(string value) => value is not null && value.Length == 64 && value.All(Uri.IsHexDigit);
}
