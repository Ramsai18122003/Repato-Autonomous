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

public static class QaLaunchPolicy
{
    public const int SchemaVersion = 1;
    public const int LaunchSchemaVersion = 2;
    public const string Operation = "launch-revit-qa";
    public const string HealthOperation = "health";
    public const string ExpectedUser = "RAMSAI\\RepatoQA";
    public const string ExpectedUserSid = "S-1-5-21-1031246752-3872016183-2454652381-1015";
    public const string ClientAccount = "RAMSAI\\rsgud";
    public const string ClientSid = "S-1-5-21-1031246752-3872016183-2454652381-1001";
    public const string LogRoot = @"C:\Users\RepatoQA\AppData\Local\Repato\QaLaunchAgent\Logs";
    public const string RequestEnvironmentVariable = "REPATO_QA_CREATE_PLAN_VIEWS_REQUEST";
    public static readonly string[] AllowedQaWorkflows = ["create-plan-views-v1"];
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
