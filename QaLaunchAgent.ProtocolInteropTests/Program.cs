using System.Text.Json;
using System.Text;
using Repato.QaLaunchAgent;
if (args.Length == 2 && args[0] == "--candidate-evidence")
{
    using var input = JsonDocument.Parse(File.ReadAllText(args[1]));
    foreach (var item in input.RootElement.EnumerateArray())
    {
        var operation = item.GetProperty("operation").GetString();
        var json = item.GetRawText();
        if (operation == QaLaunchPolicy.StageOperation)
        {
            var stageRequest = JsonSerializer.Deserialize<QaStageRequest>(json, QaLaunchPolicy.JsonOptions) ?? throw new Exception("Stage deserialization failed.");
            AssertEvidence(stageRequest.CandidateEvidence, stageRequest.TaskId!, stageRequest.WorkflowId!, stageRequest.QaWorkflowId, stageRequest.TestId);
            Console.WriteLine(JsonSerializer.Serialize(stageRequest, QaLaunchPolicy.JsonOptions));
        }
        else if (operation == QaLaunchPolicy.ValidateDeploymentOperation)
        {
            var validationRequest = JsonSerializer.Deserialize<QaDeploymentValidationRequest>(json, QaLaunchPolicy.JsonOptions) ?? throw new Exception("Deployment validation deserialization failed.");
            AssertEvidence(validationRequest.CandidateEvidence, validationRequest.TaskId!, validationRequest.WorkflowId!, validationRequest.QaWorkflowId, validationRequest.TestId);
            Console.WriteLine(JsonSerializer.Serialize(validationRequest, QaLaunchPolicy.JsonOptions));
        }
        else throw new Exception("Unexpected operation.");
    }
    return;
}

static void AssertEvidence(QaCandidateEvidence? e, string task, string workflow, string qa, string test)
{
    if (e is null || e.SchemaVersion != 1 || e.TaskId != task || e.WorkflowId != workflow || e.QaWorkflowId != qa || e.TestId != test || string.IsNullOrWhiteSpace(e.CandidateSourceCommit) || string.IsNullOrWhiteSpace(e.CandidateDirectory) || string.IsNullOrWhiteSpace(e.CandidateDllPath) || string.IsNullOrWhiteSpace(e.CandidateDllSha256) || string.IsNullOrWhiteSpace(e.NeilBuildArtifactSha256) || string.IsNullOrWhiteSpace(e.RunnerManifestPath) || string.IsNullOrWhiteSpace(e.RunnerManifestSha256) || string.IsNullOrWhiteSpace(e.CandidateProvenancePath)) throw new Exception("CandidateEvidence validation failed.");
    if (e.CandidateDllPath is null || e.RunnerManifestPath is null || e.CandidateProvenancePath is null) throw new Exception("CandidateEvidence path was lost.");
}

if (args.Length == 1)
{
    var fixtureJson = File.ReadAllText(args[0]);
    Console.WriteLine(QaLaunchPolicy.CanonicalRequestSha256(fixtureJson));
    return;
}
if (args.Length == 2 && args[0] == "--canonical")
{
    using var document = JsonDocument.Parse(File.ReadAllText(args[1]));
    using var stream = new MemoryStream();
    using (var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = false }))
    {
        writer.WriteStartObject();
        foreach (var property in document.RootElement.EnumerateObject().OrderBy(p => p.Name, StringComparer.Ordinal))
        {
            writer.WritePropertyName(property.Name);
            if (property.Name.Equals("requestSha256", StringComparison.OrdinalIgnoreCase)) writer.WriteStringValue(QaLaunchPolicy.RequestSha256Placeholder);
            else property.Value.WriteTo(writer);
        }
        writer.WriteEndObject();
    }
    Console.Write(Encoding.UTF8.GetString(stream.ToArray()));
    return;
}
var request = new QaLaunchRequest(2, "launch-revit-qa", "11111111-1111-1111-1111-111111111111", "task-1", "workflow-1", "create-plan-views-v1", "create-plan-views-v1", "22222222-2222-2222-2222-222222222222", "33333333-3333-3333-3333-333333333333", "44444444-4444-4444-4444-444444444444", @"C:\Repato-Autonomous\Source\QA\TestRuns\run\request.json", new string('A',64), @"C:\Repato-Autonomous\Source\QA\TestRuns\run\model.rvt", new string('B',64), @"C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.addin", new string('C',64), DateTimeOffset.UtcNow.AddMinutes(5));
var camelJson=JsonSerializer.Serialize(request, QaLaunchPolicy.JsonOptions);
var rq=JsonSerializer.Deserialize<QaLaunchRequest>(camelJson, QaLaunchPolicy.JsonOptions)!;
if(rq.SchemaVersion!=2||rq.Operation!=QaLaunchPolicy.Operation||rq.RequestId!=request.RequestId||rq.AttemptId!=request.AttemptId)throw new Exception("Request interoperability failed.");
var integrityRequest = request with { RequestSha256 = QaLaunchPolicy.CanonicalRequestSha256(camelJson) };
var integrityJson = JsonSerializer.Serialize(integrityRequest, QaLaunchPolicy.JsonOptions);
if(!QaLaunchPolicy.CanonicalRequestSha256(integrityJson).Equals(integrityRequest.RequestSha256, StringComparison.OrdinalIgnoreCase))throw new Exception("Request integrity positive case failed.");
var tamperedJson = integrityJson.Replace("task-1", "task-tampered", StringComparison.Ordinal);
if(QaLaunchPolicy.CanonicalRequestSha256(tamperedJson).Equals(integrityRequest.RequestSha256, StringComparison.OrdinalIgnoreCase))throw new Exception("Request integrity tamper case was accepted.");
var response=new QaLaunchResponseV2(2,QaLaunchPolicy.Operation,request.RequestId,request.RequestId,true,4242,QaLaunchPolicy.ExpectedUser,QaLaunchPolicy.ExpectedUserSid,16,DateTimeOffset.UtcNow,@"E:\revit\Revit 2025\Revit.exe",request.RequestPath,request.TaskId,request.WorkflowId,request.QaWorkflowId,request.TestId,request.AttemptId,request.RunId,null);
var rs=JsonSerializer.Deserialize<QaLaunchResponseV2>(JsonSerializer.Serialize(response))!;
if(!rs.Accepted||rs.CorrelationId!=request.RequestId||rs.Sid!=QaLaunchPolicy.ExpectedUserSid||rs.RunId!=request.RunId)throw new Exception("Response interoperability failed.");
Console.WriteLine("C# protocol v2 request/response interoperability passed.");
