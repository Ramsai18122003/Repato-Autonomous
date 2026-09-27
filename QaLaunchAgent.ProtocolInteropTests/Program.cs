using System.Text.Json;
using Repato.QaLaunchAgent;
var request = new QaLaunchRequest(2, "launch-revit-qa", "11111111-1111-1111-1111-111111111111", "task-1", "workflow-1", "create-plan-views-v1", "create-plan-views-v1", "22222222-2222-2222-2222-222222222222", "33333333-3333-3333-3333-333333333333", "44444444-4444-4444-4444-444444444444", @"C:\Repato-Autonomous\Source\QA\TestRuns\run\request.json", new string('A',64), @"C:\Repato-Autonomous\Source\QA\TestRuns\run\model.rvt", new string('B',64), @"C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025\Repato.addin", new string('C',64), DateTimeOffset.UtcNow.AddMinutes(5));
var rq=JsonSerializer.Deserialize<QaLaunchRequest>(JsonSerializer.Serialize(request))!;
if(rq.SchemaVersion!=2||rq.Operation!=QaLaunchPolicy.Operation||rq.RequestId!=request.RequestId||rq.AttemptId!=request.AttemptId)throw new Exception("Request interoperability failed.");
var response=new QaLaunchResponseV2(2,QaLaunchPolicy.Operation,request.RequestId,request.RequestId,true,4242,QaLaunchPolicy.ExpectedUser,QaLaunchPolicy.ExpectedUserSid,16,DateTimeOffset.UtcNow,@"E:\revit\Revit 2025\Revit.exe",request.RequestPath,request.TaskId,request.WorkflowId,request.QaWorkflowId,request.TestId,request.AttemptId,request.RunId,null);
var rs=JsonSerializer.Deserialize<QaLaunchResponseV2>(JsonSerializer.Serialize(response))!;
if(!rs.Accepted||rs.CorrelationId!=request.RequestId||rs.Sid!=QaLaunchPolicy.ExpectedUserSid||rs.RunId!=request.RunId)throw new Exception("Response interoperability failed.");
Console.WriteLine("C# protocol v2 request/response interoperability passed.");
