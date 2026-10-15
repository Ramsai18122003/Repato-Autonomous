using System.Text.Json;
using Repato.QaLaunchAgent;

int assertions = 0;
void Check(bool value, string name) { assertions++; if (!value) throw new Exception(name); }
void Reject(Action action, string name) { assertions++; try { action(); } catch { return; } throw new Exception("Accepted " + name); }
string root = Path.Combine(Path.GetTempPath(), "repato-cpv-protocol-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
try {
    var now = DateTimeOffset.UtcNow;
    var identity = new Identity();
    var evidence = new QaCandidateEvidence(1, "task-" + Guid.NewGuid().ToString("N"), Guid.NewGuid().ToString("N"),
        "create-plan-views-v1", "create-plan-views-v1", new string('a',40), "candidate", "candidate.dll", new string('A',64), new string('A',64), "manifest", new string('B',64), "provenance");
    CpvPreparationRequest Request() => new(1, CpvPreparationService.Operation, Guid.NewGuid().ToString("N"), evidence.TaskId,
        evidence.WorkflowId, Guid.NewGuid().ToString("N"), Guid.NewGuid().ToString("N"), now.AddHours(3), 7200, evidence);
    string Json(CpvPreparationRequest r) => JsonSerializer.Serialize(r, CpvPreparationService.StrictJson);
    QaAgentOptions Options(string suffix) => new("never-revit.exe", root, root, Path.Combine(root,suffix+"ledger.json"), Path.Combine(root,suffix));
    var boundary = new Boundary(); var ledger = new Ledger(); var options = Options("valid");
    var service = new CpvPreparationService(options, identity, ledger, boundary);
    var r = Request();
    var executing = (CpvPreparationReceipt)service.Handle(Json(r),now);
    Check(executing.Status == "Executing", "valid request reserves before execution");
    Check(((CpvPreparationReceipt)service.Handle(Json(r),now)).RequestId == r.RequestId, "identical retry returns existing receipt");
    Reject(()=>service.Handle(Json(r with { RunId = Guid.NewGuid().ToString("N") }),now),"same request different payload");
    Reject(()=>service.Handle(Json(Request()),now),"concurrent request");
    var restarted = new CpvPreparationService(options, identity, ledger, boundary);
    var interrupted = (CpvPreparationReceipt)restarted.Handle(JsonSerializer.Serialize(new CpvPreparationQuery(1,CpvPreparationService.StatusOperation,r.RequestId),CpvPreparationService.StrictJson),now);
    Check(interrupted.Status == "OutcomeUnknown", "interrupted execution fails closed");
    boundary.Completion.SetResult(new(new string('C',64),new string('D',64),true,"CommittedDisposableFixtureOnly"));
    // Synthetic boundary also writes the request file expected by receipt hashing.
    CpvPreparationReceipt terminal = executing;
    for(int i=0;i<200 && terminal.Status=="Executing";i++) { await Task.Delay(5); terminal=(CpvPreparationReceipt)service.Handle(JsonSerializer.Serialize(new CpvPreparationQuery(1,CpvPreparationService.StatusOperation,r.RequestId),CpvPreparationService.StrictJson),now); }
    Check(terminal.Status == "Passed" && terminal.CleanupVerified, "authenticated terminal receipt");
    Reject(()=>service.Handle(Json(Request() with { AttemptId=r.AttemptId }),now),"duplicate attempt");
    Reject(()=>service.Handle(Json(Request() with { RunId=r.RunId }),now),"duplicate run");
    foreach(var invalid in new[] {r with { AttemptId=new string('0',32) },r with { WorkflowId="bad" },r with { TaskId="other" },
        r with { ExpiresUtc=now },r with { TimeoutSeconds=0 },r with { Operation="powershell" },r with { SchemaVersion=2 }})
        Reject(()=>new CpvPreparationService(Options(Guid.NewGuid().ToString()),identity,new Ledger(),new Boundary()).Handle(Json(invalid),now),"invalid schema/identity/expiry");
    Reject(()=>service.Handle(Json(r).Replace("\"schemaVersion\":1","\"schemaVersion\":1,\"schemaVersion\":1"),now),"duplicate fields");
    Reject(()=>service.Handle(Json(r).Replace("\"schemaVersion\":1","\"arbitraryExecutable\":\"cmd.exe\",\"schemaVersion\":1"),now),"unknown fields");
    Reject(()=>service.Handle(Json(r with { CandidateEvidence=evidence with { TaskId="other" } }),now),"candidate task identity mismatch");
    Check(!QaLaunchPolicy.IsValidCandidateEvidence(evidence with { CandidateDllPath=Path.Combine(root,"arbitrary.dll") },r.TaskId,r.WorkflowId,evidence.QaWorkflowId,evidence.TestId),"production candidate root/hash policy rejects arbitrary DLL");
    Check(!QaLaunchPolicy.IsValidCandidateEvidence(evidence with { RunnerManifestPath=Path.Combine(root,"arbitrary.addin") },r.TaskId,r.WorkflowId,evidence.QaWorkflowId,evidence.TestId),"production manifest root/hash policy rejects arbitrary manifest");
    Reject(()=>new CpvPreparationService(Options("unauthorized"),new Identity{User="wrong"},new Ledger(),new Boundary()).Handle(Json(Request()),now),"unauthorized identity");
    Reject(()=>new CpvPreparationService(Options("sid"),new Identity{Sid="wrong"},new Ledger(),new Boundary()).Handle(Json(Request()),now),"wrong SID");
    Reject(()=>new CpvPreparationService(Options("session"),new Identity{Interactive=false},new Ledger(),new Boundary()).Handle(Json(Request()),now),"noninteractive");
    foreach(string code in new[]{"candidate-mismatch","manifest-mismatch","model-lock","revit-present","provenance-mismatch"}) {
        var bad=new Boundary{ValidationError=code};var l=new Ledger();
        Reject(()=>new CpvPreparationService(Options(code),identity,l,bad).Handle(Json(Request()),now),code);
        Check(l.Count==0,"invalid artifacts never reserve or launch");
    }
    foreach(string failure in new[]{"timeout","missing-result","cleanup-failure","ambiguous"}) {
        var b=new Boundary();var o=Options(failure);var s=new CpvPreparationService(o,identity,new Ledger(),b);var req=Request();s.Handle(Json(req),now);
        if(failure=="cleanup-failure") b.Completion.SetResult(new("C","D",false,"Unknown"));
        else b.Completion.SetException(failure=="timeout"?new TimeoutException():new IOException(failure));
        object response;CpvPreparationReceipt outcome;
        do {await Task.Delay(5);response=s.Handle(JsonSerializer.Serialize(new CpvPreparationQuery(1,CpvPreparationService.StatusOperation,req.RequestId),CpvPreparationService.StrictJson),now);outcome=(CpvPreparationReceipt)response;}while(outcome.Status=="Executing");
        Check(outcome.Status!="Passed" && !outcome.CleanupVerified,"failure cannot approve: "+failure);
        Reject(()=>s.Handle(Json(Request()),now),"failed/ambiguous execution blocks retry");
    }
    string model=Path.Combine(root,"model.rvt");File.WriteAllText(model,"prepared");
    string result=JsonSerializer.Serialize(new { Status="Passed",Operation=CpvPreparationService.RunnerOperation,TaskId=r.TaskId,WorkflowId=r.WorkflowId,AttemptId=r.AttemptId,RunId=r.RunId,ModelPath=model,SourceModelSha256=CpvPreparationService.FixtureSha256,PreparedModelSha256=CpvPreparationService.Hash(model),Levels=new[]{new{ Name="0",ElevationMeters=0d,ElementId=1L},new{Name="1",ElevationMeters=4d,ElementId=2L},new{Name="2",ElevationMeters=7.8d,ElementId=3L}} });
    RevitCpvPreparationBoundary.VerifyResult(result,r,model);Check(true,"exact prepared levels and result identity");
    Reject(()=>RevitCpvPreparationBoundary.VerifyResult(result.Replace("7.8","8.8"),r,model),"wrong elevation");
    Reject(()=>RevitCpvPreparationBoundary.VerifyResult(result.Replace(r.AttemptId,Guid.NewGuid().ToString("N")),r,model),"wrong result attempt");
    File.AppendAllText(model,"changed");Reject(()=>RevitCpvPreparationBoundary.VerifyResult(result,r,model),"prepared bytes mismatch");
    Console.WriteLine($"PASS: {assertions} CPV preparation protocol assertions; injected processes only; Revit launched=false.");
} finally {Directory.Delete(root,true);}

sealed class Identity:IIdentitySessionProvider {public string User{get;set;}=QaLaunchPolicy.ExpectedUser;public string Sid{get;set;}=QaLaunchPolicy.ExpectedUserSid;public int SessionId=>1;public bool Interactive{get;set;}=true;}
sealed class Ledger:IReplayLedger {readonly HashSet<string> keys=[];public int Count=>keys.Count;public bool TryReserve(string id,DateTimeOffset now)=>keys.Add(id);public bool TryReserve(QaLaunchRequest r,DateTimeOffset now)=>TryReserve(r.RequestId,now);}
sealed class Boundary:ICpvPreparationBoundary {
    public string? ValidationError{get;set;}
    public TaskCompletionSource<CpvPreparationOutcome> Completion{get;}=new(TaskCreationOptions.RunContinuationsAsynchronously);
    public void Validate(CpvPreparationRequest r){if(ValidationError!=null)throw new InvalidDataException(ValidationError);}
    public async Task<CpvPreparationOutcome> Execute(CpvPreparationRequest r,string dir){Directory.CreateDirectory(dir);File.WriteAllText(Path.Combine(dir,"tara-"+r.AttemptId+".request.json"),"synthetic");return await Completion.Task;}
}
