using System.IO;
using System.Security.Cryptography;
using System.Text.Json;

namespace Repato.Revit.TestRunner;

internal static class CreatePlanViewsPreparationEvidenceContract
{
    internal static void Verify(CreatePlanViewsRequest request, string sourceFixturePath, string disposableModelPath)
    {
        if (!Hash(sourceFixturePath).Equals(request.FixtureSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Authoritative source fixture SHA-256 does not match the request-bound preparation evidence.");
        if (!Hash(disposableModelPath).Equals(request.ModelSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Disposable model SHA-256 does not match the launch request.");
        if (!Hash(request.FixturePreparationRequestPath).Equals(request.FixturePreparationRequestSha256, StringComparison.OrdinalIgnoreCase) ||
            !Hash(request.FixturePreparationResultPath).Equals(request.FixturePreparationResultSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Correlated fixture-preparation request/result SHA-256 mismatch.");

        CreatePlanViewsFixturePreparationRequest preparationRequest = CreatePlanViewsFixturePreparationRequest.Parse(
            File.ReadAllText(request.FixturePreparationRequestPath), request.FixturePreparationRequestPath);
        using JsonDocument resultDocument = JsonDocument.Parse(File.ReadAllText(request.FixturePreparationResultPath));
        JsonElement result = resultDocument.RootElement;
        string Text(string name) => result.TryGetProperty(name, out JsonElement value) && value.ValueKind == JsonValueKind.String
            ? value.GetString() ?? "" : "";

        if (preparationRequest.TaskId != request.TaskId || preparationRequest.WorkflowId != request.WorkflowId ||
            preparationRequest.AttemptId != request.FixturePreparationAttemptId || preparationRequest.RunId != request.FixturePreparationRunId ||
            !Path.GetFullPath(preparationRequest.OutputPath).Equals(Path.GetFullPath(request.FixturePreparationResultPath), StringComparison.OrdinalIgnoreCase) ||
            !preparationRequest.ModelSha256.Equals(request.FixtureSha256, StringComparison.OrdinalIgnoreCase) ||
            Text("Status") != "Passed" || Text("Operation") != "prepare-disposable-create-plan-views-fixture" ||
            Text("TaskId") != request.TaskId || Text("WorkflowId") != request.WorkflowId ||
            Text("AttemptId") != request.FixturePreparationAttemptId || Text("RunId") != request.FixturePreparationRunId ||
            !Path.GetFullPath(Text("ModelPath")).Equals(Path.GetFullPath(preparationRequest.ModelPath), StringComparison.OrdinalIgnoreCase) ||
            !Text("SourceModelSha256").Equals(request.FixtureSha256, StringComparison.OrdinalIgnoreCase) ||
            !Text("PreparedModelSha256").Equals(request.ModelSha256, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Fixture-preparation evidence identity or source/prepared hash correlation failed.");
    }

    private static string Hash(string path)
    {
        using FileStream stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }
}
