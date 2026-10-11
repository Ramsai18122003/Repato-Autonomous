using System.IO;
using System.Text.Json;

namespace Repato.Revit.TestRunner;

internal sealed record CreatePlanViewsFixturePreparationRequest(
    string TaskId,
    string WorkflowId,
    string AttemptId,
    string RunId,
    string RequestPath,
    string ModelPath,
    string ModelSha256,
    string OutputPath,
    DateTimeOffset ExpiresUtc)
{
    internal static CreatePlanViewsFixturePreparationRequest Parse(string json, string actualRequestPath)
    {
        using JsonDocument document = JsonDocument.Parse(json);
        JsonElement root = document.RootElement;
        string Text(string name) => root.GetProperty(name).GetString() ?? throw new InvalidOperationException($"Missing {name}.");
        string taskId = Text("taskId"), workflowId = Text("workflowId"), attemptId = Text("attemptId"), runId = Text("runId");
        string declaredRequestPath = Path.GetFullPath(Text("requestPath"));
        string modelPath = Path.GetFullPath(Text("modelPath")), outputPath = Path.GetFullPath(Text("outputPath"));
        string modelSha256 = Text("modelSha256");
        DateTimeOffset expiresUtc = root.GetProperty("expiresUtc").GetDateTimeOffset();
        if (Text("operation") != "prepare-disposable-create-plan-views-fixture")
            throw new InvalidOperationException("Unknown fixture preparation operation.");
        if (!Guid.TryParseExact(attemptId, "N", out _) || !Guid.TryParseExact(runId, "N", out _))
            throw new InvalidOperationException("Fixture preparation attempt/run IDs must be GUID N format.");
        if (!declaredRequestPath.Equals(Path.GetFullPath(actualRequestPath), StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Fixture preparation request path identity mismatch.");
        if (string.IsNullOrWhiteSpace(taskId) || !Guid.TryParseExact(workflowId, "N", out _))
            throw new InvalidOperationException("Fixture preparation task/workflow identity is invalid.");
        if (modelSha256.Length != 64 || !modelSha256.All(Uri.IsHexDigit))
            throw new InvalidOperationException("Fixture preparation model hash is invalid.");
        string requestDirectory = Path.GetDirectoryName(Path.GetFullPath(actualRequestPath))!;
        if (!Path.GetDirectoryName(modelPath)!.Equals(requestDirectory, StringComparison.OrdinalIgnoreCase) ||
            !Path.GetDirectoryName(outputPath)!.Equals(requestDirectory, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Fixture preparation request, model, and output must share one attempt directory.");
        if (expiresUtc <= DateTimeOffset.UtcNow)
            throw new InvalidOperationException("Fixture preparation request expired.");
        return new(taskId, workflowId, attemptId, runId, declaredRequestPath, modelPath, modelSha256.ToUpperInvariant(), outputPath, expiresUtc);
    }
}
