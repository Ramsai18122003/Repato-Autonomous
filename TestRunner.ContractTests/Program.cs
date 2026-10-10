using System.Text.Json;
using Repato.Revit.TestRunner;

static void Check(bool value, string reason) { if (!value) throw new InvalidOperationException("FAILED: " + reason); }
static void Reject(Action action, string reason) { try { action(); } catch { return; } throw new InvalidOperationException("FAILED: " + reason); }

string tempRequest = Path.Combine(Path.GetTempPath(), "repato-request-" + Guid.NewGuid().ToString("N") + ".json");
string modelHash = new('A', 64), manifestHash = new('B', 64), artifactHash = new('C', 64);
var jsonObject = new Dictionary<string, object?>
{
    ["schemaVersion"] = 2, ["operation"] = "launch-revit-qa", ["requestId"] = Guid.NewGuid().ToString("N"),
    ["taskId"] = "task-synthetic", ["workflowId"] = Guid.NewGuid().ToString("N"), ["qaWorkflowId"] = CreatePlanViewsRequest.Test,
    ["testId"] = CreatePlanViewsRequest.Test, ["attemptId"] = Guid.NewGuid().ToString("N"), ["runId"] = Guid.NewGuid().ToString("N"),
    ["claimId"] = Guid.NewGuid().ToString("N"), ["requestPath"] = tempRequest, ["requestSha256"] = new string('0', 64),
    ["modelPath"] = Path.Combine(Path.GetTempPath(), "model.rvt"), ["modelSha256"] = modelHash,
    ["manifestPath"] = Path.Combine(Path.GetTempPath(), "Repato.CreatePlanViews.TestRunner.addin"), ["manifestSha256"] = manifestHash,
    ["expiresUtc"] = DateTimeOffset.UtcNow.AddMinutes(5)
};
string placeholderJson = JsonSerializer.Serialize(jsonObject);
jsonObject["requestSha256"] = CreatePlanViewsRequest.CanonicalSha256(placeholderJson);
string requestJson = JsonSerializer.Serialize(jsonObject);
var request = CreatePlanViewsRequest.Parse(requestJson, tempRequest);
Check(request.RequestId == (string)jsonObject["requestId"]!, "request id parsed and bound");
Check(request.AttemptId == (string)jsonObject["attemptId"]! && request.RunId == (string)jsonObject["runId"]!, "attempt/run identity parsed");
Reject(() => CreatePlanViewsRequest.Parse(requestJson.Replace("task-synthetic", "task-tampered"), tempRequest), "tampered request self-hash rejected");
Reject(() => CreatePlanViewsRequest.Parse(requestJson, tempRequest + ".other"), "request path binding enforced");
Reject(() => CreatePlanViewsRequest.Parse(requestJson.Replace(CreatePlanViewsRequest.Test, "other-test"), tempRequest), "wrong test contract rejected");
Reject(() => CreatePlanViewsRequest.Parse(requestJson.Replace("\"schemaVersion\":2", "\"schemaVersion\":1"), tempRequest), "wrong schema rejected");

string reportPath = Path.Combine(Path.GetTempPath(), request.RunId + ".json");
var identity = new Dictionary<string, object?>
{
    ["RequestId"] = request.RequestId, ["TaskId"] = request.TaskId, ["WorkflowId"] = request.WorkflowId,
    ["TestId"] = request.TestId, ["AttemptId"] = request.AttemptId, ["RunId"] = request.RunId, ["ClaimId"] = request.ClaimId
};
var passingReport = new Dictionary<string, object?>(identity)
{
    ["Status"] = "Passed", ["RollbackStatus"] = "RolledBack", ["FixtureSha256"] = modelHash,
    ["RuntimeModelSha256"] = modelHash, ["FinishedUtc"] = DateTimeOffset.UtcNow,
    ["AssemblyIdentity"] = new { Sha256 = artifactHash }, ["Errors"] = Array.Empty<string>(),
    ["Assertions"] = new[] { new { Passed = true } }
};
var receipt = new Dictionary<string, object?>(identity)
{
    ["QaWorkflowId"] = request.QaWorkflowId, ["ReportPath"] = reportPath, ["Status"] = "Passed"
};
string passingReportJson = JsonSerializer.Serialize(passingReport), passingReceiptJson = JsonSerializer.Serialize(receipt);
Check(CreatePlanViewsResultContract.IsPassing(passingReceiptJson, passingReportJson, request, artifactHash), "canonical passing report/receipt contract accepted");
Check(!CreatePlanViewsResultContract.IsPassing(passingReceiptJson, passingReportJson.Replace("RolledBack", "Committed"), request, artifactHash), "missing rollback proof rejected");
Check(!CreatePlanViewsResultContract.IsPassing(passingReceiptJson.Replace(request.RequestId, Guid.NewGuid().ToString("N")), passingReportJson, request, artifactHash), "unmatched receipt request id rejected");
Check(!CreatePlanViewsResultContract.IsPassing(passingReceiptJson, passingReportJson.Replace("Passed", "Failed"), request, artifactHash), "failed report cannot pass");
Check(!CreatePlanViewsResultContract.IsPassing(passingReceiptJson, passingReportJson, request, new string('D', 64)), "candidate hash mismatch rejected");

var failedReceipt = CreatePlanViewsResultContract.CreateReceipt(request, request.RequestId, request.TaskId, request.WorkflowId,
    request.TestId, request.AttemptId, request.RunId, request.ClaimId, "Failed", reportPath);
Check(failedReceipt.Status == "Failed" && failedReceipt.RequestId == request.RequestId, "negative runner result remains request-bound and terminally failed");
var failedReportJson = JsonSerializer.Serialize(new Dictionary<string, object?>(identity)
{
    ["Status"] = "Failed", ["RollbackStatus"] = "NotStarted", ["Errors"] = new[] { "Architectural template is unavailable." },
    ["FinishedUtc"] = DateTimeOffset.UtcNow, ["Assertions"] = Array.Empty<object>()
});
Check(!CreatePlanViewsResultContract.IsPassing(JsonSerializer.Serialize(failedReceipt), failedReportJson, request, artifactHash), "failed report and its exact error are retained but cannot pass");
Reject(() => CreatePlanViewsResultContract.CreateReceipt(request, request.RequestId, request.TaskId, request.WorkflowId,
    request.TestId, request.AttemptId, Guid.NewGuid().ToString("N"), request.ClaimId, "Passed", reportPath), "mismatched result run identity rejected");
Console.WriteLine("Create Plan Views runner contract tests passed: request parsing/binding, result identity, failed reporting, canonical verifier expectations.");
