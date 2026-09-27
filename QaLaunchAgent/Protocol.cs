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

public sealed record QaHealthRequest(int SchemaVersion, string Operation);
public sealed record QaHealthResponse(int SchemaVersion, string Operation, bool Ready, string User, string Sid, int SessionId, bool Interactive, string? FailureCode);

public static class QaLaunchPolicy
{
    public const int SchemaVersion = 1;
    public const string Operation = "launch-revit-qa";
    public const string HealthOperation = "health";
    public const string ExpectedUser = "RAMSAI\\RepatoQA";
    public const string RequestEnvironmentVariable = "REPATO_QA_CREATE_PLAN_VIEWS_REQUEST";
    public static readonly string[] AllowedQaWorkflows = ["create-plan-views-v1"];
    public static bool IsValidRequest(QaLaunchRequest r, DateTimeOffset now) =>
        r is not null && r.SchemaVersion == SchemaVersion && r.Operation == Operation &&
        Guid.TryParse(r.RequestId, out _) && !string.IsNullOrWhiteSpace(r.RunId) &&
        !string.IsNullOrWhiteSpace(r.ClaimId) && AllowedQaWorkflows.Contains(r.QaWorkflowId) &&
        r.TestId == r.QaWorkflowId && r.ExpiresUtc > now;
}
