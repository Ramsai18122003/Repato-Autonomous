using System.Text.Json;
using System.Text.Json.Nodes;
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
var adapterJson="""{"schemaVersion":1,"operation":"validate-qa-deployment","requestId":"29244cda85b2416993130645675a7892","succeeded":true,"candidateCommit":"fcf624ee3ed1c84fcc2bb78e4bf46d92090b98f3","candidateSha256":"7EC1C819C771DCE4EC4ADCADB93B0245D243F6675EC0F0B070B03303B1F412C2","qaWorkflowId":"create-plan-views-v1","testId":"create-plan-views-v1","validationIdentity":"RAMSAI\\RepatoQA","qaAddinRoot":"C:\\Users\\RepatoQA\\AppData\\Roaming\\Autodesk\\Revit\\Addins\\2025\\RepatoQA","isolationPassed":true,"errorCode":null,"errorMessage":null,"runnerManifestPath":"C:\\Users\\RepatoQA\\AppData\\Roaming\\Autodesk\\Revit\\Addins\\2025\\Repato.CreatePlanViews.TestRunner.addin","runnerManifestSha256":"AF4DBFA78E61524DE7BD3B84178C6B70ED8D29D0A95BA17780826E09BE689D4F","manifestIntegrityPassed":true}""";
var adapterResponse = StagingAdapter.DeserializeDeploymentValidationResponse(adapterJson);
if (!QaLaunchPolicy.CanPassDeploymentValidation(adapterResponse)) throw new Exception("Valid adapter deployment response was rejected.");
var pipeJson = NamedPipeLaunchServer.SerializeResponse(adapterResponse);
var pipeResponse = JsonSerializer.Deserialize<QaDeploymentValidationResponse>(pipeJson, QaLaunchPolicy.JsonOptions)!;
if (pipeResponse.RunnerManifestPath != adapterResponse.RunnerManifestPath || pipeResponse.RunnerManifestSha256 != adapterResponse.RunnerManifestSha256 || pipeResponse.ManifestIntegrityPassed != true) throw new Exception("Named-pipe serialization dropped deployment manifest evidence.");
var withoutEvidence = StagingAdapter.DeserializeDeploymentValidationResponse("""{"schemaVersion":1,"operation":"validate-qa-deployment","requestId":"29244cda85b2416993130645675a7892","succeeded":true,"isolationPassed":true}""");
if (withoutEvidence.RunnerManifestPath is not null || withoutEvidence.RunnerManifestSha256 is not null || withoutEvidence.ManifestIntegrityPassed is not null || QaLaunchPolicy.CanPassDeploymentValidation(withoutEvidence)) throw new Exception("Missing deployment manifest evidence received unsafe defaults.");
var pipeMissingJson = NamedPipeLaunchServer.SerializeResponse(withoutEvidence);
if (!pipeMissingJson.Contains("\"runnerManifestPath\":null", StringComparison.Ordinal) || !pipeMissingJson.Contains("\"runnerManifestSha256\":null", StringComparison.Ordinal) || !pipeMissingJson.Contains("\"manifestIntegrityPassed\":null", StringComparison.Ordinal)) throw new Exception("Missing manifest evidence defaults were not explicit at the named-pipe boundary.");
foreach (var field in new[] { "runnerManifestPath", "runnerManifestSha256", "manifestIntegrityPassed" })
{
    var withoutOneField = JsonNode.Parse(adapterJson)!.AsObject();
    withoutOneField.Remove(field);
    var incomplete = StagingAdapter.DeserializeDeploymentValidationResponse(withoutOneField.ToJsonString());
    if (QaLaunchPolicy.CanPassDeploymentValidation(incomplete)) throw new Exception($"Missing {field} was accepted for successful validation.");
}
foreach (var malformed in new[]
{
    adapterJson.Replace("AF4DBFA78E61524DE7BD3B84178C6B70ED8D29D0A95BA17780826E09BE689D4F", "not-a-sha256", StringComparison.Ordinal),
    adapterJson.Replace("C:\\\\Users\\\\RepatoQA\\\\AppData\\\\Roaming\\\\Autodesk\\\\Revit\\\\Addins\\\\2025\\\\Repato.CreatePlanViews.TestRunner.addin", "C:\\\\unexpected.addin", StringComparison.Ordinal),
    adapterJson.Replace("\"manifestIntegrityPassed\":true", "\"manifestIntegrityPassed\":\"true\"", StringComparison.Ordinal)
})
{
    try
    {
        var invalid = StagingAdapter.DeserializeDeploymentValidationResponse(malformed);
        if (QaLaunchPolicy.CanPassDeploymentValidation(invalid)) throw new Exception("Malformed deployment manifest evidence was accepted.");
    }
    catch (System.Text.Json.JsonException) { }
}
var explicitNegative = adapterResponse with { ManifestIntegrityPassed = false };
if (!QaLaunchPolicy.HasValidDeploymentManifestEvidence(explicitNegative) || QaLaunchPolicy.CanPassDeploymentValidation(explicitNegative)) throw new Exception("Explicit negative manifest evidence passed validation.");
Console.WriteLine("C# protocol v2 request/response interoperability passed.");
