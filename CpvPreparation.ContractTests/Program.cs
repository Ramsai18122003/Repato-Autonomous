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
    Check(JsonSerializer.SerializeToElement(service.Capabilities()).GetProperty("reconciliationOperation").GetString()==CpvPreparationService.ReconcileOperation,"authenticated capabilities advertise fixed reconciliation operation");
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
    using (File.Open(model,FileMode.Open,FileAccess.ReadWrite,FileShare.None))
        Reject(()=>RevitCpvPreparationBoundary.VerifyResultAfterChildExit(result,r,model,()=>false),"result verification waits for owned Revit child exit");
    Reject(()=>RevitCpvPreparationBoundary.OpenModelExclusivelyAfterChildExit(model,()=>false,TimeSpan.FromMilliseconds(100)).GetAwaiter().GetResult(),"exclusive model open rejects a live child");
    RevitCpvPreparationBoundary.VerifyResultAfterChildExit(result,r,model,()=>true);Check(true,"exact prepared levels and result identity after child exit");
    var delayedLock=File.Open(model,FileMode.Open,FileAccess.ReadWrite,FileShare.None);
    var delayedRelease=Task.Run(async()=>{await Task.Delay(200);delayedLock.Dispose();});
    using(var acquired=RevitCpvPreparationBoundary.OpenModelExclusivelyAfterChildExit(model,()=>true,TimeSpan.FromSeconds(2),TimeSpan.FromMilliseconds(25)).GetAwaiter().GetResult())
        Check(acquired.CanRead,"exclusive model validation waits for delayed file release after child exit");
    delayedRelease.GetAwaiter().GetResult();
    Reject(()=>RevitCpvPreparationBoundary.VerifyResult(result.Replace("7.8","8.8"),r,model),"wrong elevation");
    Reject(()=>RevitCpvPreparationBoundary.VerifyResult(result.Replace(r.AttemptId,Guid.NewGuid().ToString("N")),r,model),"wrong result attempt");
    File.AppendAllText(model,"changed");Reject(()=>RevitCpvPreparationBoundary.VerifyResult(result,r,model),"prepared bytes mismatch");
    (CpvPreparationReceipt Receipt,CpvPreparationService Service,CpvPreparationReconciliation Query,string Store,string RequestJson) ReconciliationCase(string name, Boundary boundary, bool corruptModel = false, bool resultPresent = false, bool lockPresent = false, bool corruptRunner = false, bool wrongIdentity = false)
    {
        string testRoot=Path.Combine(root,"reconcile-"+name),logRoot=Path.Combine(testRoot,"logs"),store=Path.Combine(logRoot,"CpvPreparation"),runtime=Path.Combine(testRoot,"runtime");Directory.CreateDirectory(store);Directory.CreateDirectory(runtime);
        var rr=Request();string run=Path.Combine(runtime,"cpv-preparation-"+rr.RunId);Directory.CreateDirectory(run);
        string modelPath=Path.Combine(run,"model.rvt"),runnerPath=Path.Combine(run,"tara-"+rr.AttemptId+".request.json");
        File.Copy(@"C:\Repato-Autonomous\Source\QA\Fixtures\CreatePlanViewsEmpty.rvt",modelPath);
        if(corruptModel)File.AppendAllText(modelPath,"corrupt");
        var runner=new {schemaVersion=1,operation=CpvPreparationService.RunnerOperation,requestId=rr.AttemptId,taskId=rr.TaskId,workflowId=rr.WorkflowId,attemptId=rr.AttemptId,runId=rr.RunId,requestPath=runnerPath,modelPath,modelSha256=CpvPreparationService.FixtureSha256,selectedManifestPath=QaLaunchPolicy.ExpectedRunnerManifestPath,selectedManifestSha256=rr.CandidateEvidence.RunnerManifestSha256,outputPath=runnerPath+".preparation.json",expiresUtc=rr.ExpiresUtc};
        File.WriteAllText(runnerPath,JsonSerializer.Serialize(runner));if(corruptRunner)File.WriteAllText(runnerPath,"{}");if(resultPresent)File.WriteAllText(runnerPath+".preparation.json","{}");if(lockPresent)File.WriteAllText(modelPath+".slog","");
        var rec=new CpvPreparationReceipt(1,CpvPreparationService.Operation,rr.RequestId,rr.TaskId,rr.WorkflowId,rr.AttemptId,rr.RunId,"OutcomeUnknown",identity.User,identity.Sid,identity.SessionId,rr.CandidateEvidence.CandidateDllSha256,rr.CandidateEvidence.RunnerManifestSha256,modelPath,"",runnerPath,"","","",false,"Unknown","preparation-failed-reconcile-required",rr.ExpiresUtc);
        string requestJson=Json(rr);File.WriteAllText(Path.Combine(store,"active.json"),requestJson);File.WriteAllText(Path.Combine(store,rr.RequestId+".request.json"),requestJson);File.WriteAllText(Path.Combine(store,rr.RequestId+".failure.txt"),"System.IO.InvalidDataException: preparation-exited-without-result");File.WriteAllText(Path.Combine(store,rr.RequestId+".json"),JsonSerializer.Serialize(rec,CpvPreparationService.StrictJson));
        var svc=new CpvPreparationService(Options("reconcile-"+name) with {LogRoot=logRoot,RuntimeRoot=runtime},identity,new Ledger(),boundary);
        var query=new CpvPreparationReconciliation(1,CpvPreparationService.ReconcileOperation,rr.RequestId,rr.TaskId,wrongIdentity?Guid.NewGuid().ToString("N"):rr.WorkflowId,rr.AttemptId,rr.RunId);
        var terminal=(CpvPreparationReceipt)svc.Handle(JsonSerializer.Serialize(query,CpvPreparationService.StrictJson),now);
        return (terminal,svc,query,store,requestJson);
    }
    var reconcileBoundary=new Boundary();
    var failedReconciled=ReconciliationCase("valid",reconcileBoundary);
    Check(failedReconciled.Receipt.Status=="FailedReconciled" && !failedReconciled.Receipt.CleanupVerified && failedReconciled.Receipt.FailureCode=="preparation-exited-without-result","valid evidence reconciles only to terminal failure");
    Check(!File.Exists(Path.Combine(failedReconciled.Store,"active.json")),"validated agent reconciliation removes only its active marker");
    Reject(()=>ReconciliationCase("identity-mismatch",new Boundary(),wrongIdentity:true),"identity-mismatch");
    Reject(()=>ReconciliationCase("bad-model",new Boundary(),corruptModel:true),"model-hash-mismatch");
    Reject(()=>ReconciliationCase("bad-runner",new Boundary(),corruptRunner:true),"runner-request-mismatch");
    Reject(()=>ReconciliationCase("result",new Boundary(),resultPresent:true),"result-or-lock");
    Reject(()=>ReconciliationCase("lock",new Boundary(),lockPresent:true),"result-or-lock");
    var uncertainProcess=new Boundary{ReconciliationError="reconciliation-process-state-unknown"};Reject(()=>ReconciliationCase("process-unknown",uncertainProcess),"process-state-unknown");
    Check(true,"unreadable process evidence fails closed through injected boundary");
    var replayed=(CpvPreparationReceipt)failedReconciled.Service.Handle(JsonSerializer.Serialize(failedReconciled.Query,CpvPreparationService.StrictJson),now);
    Check(replayed.Status=="FailedReconciled","duplicate agent reconciliation is idempotent after marker removal");
    File.WriteAllText(Path.Combine(failedReconciled.Store,"active.json"),failedReconciled.RequestJson);
    string receiptPath=Path.Combine(failedReconciled.Store,replayed.RequestId+".json");
    var interruptedReceipt=replayed with {Status="OutcomeUnknown",RequestSha256="",FailureCode="preparation-failed-reconcile-required",RollbackStatus="Unknown"};
    File.WriteAllText(receiptPath,JsonSerializer.Serialize(interruptedReceipt,CpvPreparationService.StrictJson));
    string orphanedPartial=receiptPath+".crash.reconcile.partial";File.WriteAllText(orphanedPartial,"interrupted partial evidence");
    var resumed=(CpvPreparationReceipt)failedReconciled.Service.Handle(JsonSerializer.Serialize(failedReconciled.Query,CpvPreparationService.StrictJson),now);
    Check(resumed.Status=="FailedReconciled" && File.Exists(orphanedPartial) && !File.Exists(Path.Combine(failedReconciled.Store,"active.json")),"interrupted partial is preserved while terminal receipt resumes safely");
    (CpvPreparationRecoveryCommit Commit,CpvPreparationService Service,string Store,string OriginalJson,CpvPreparationCompletedRecovery Query) CompletedRecoveryCase(string name, bool corruptResult=false, bool missingResult=false, bool wrongBinding=false, bool expiredAuthorization=false, bool corruptModel=false)
    {
        string testRoot=Path.Combine(root,"completed-recovery-"+name),logRoot=Path.Combine(testRoot,"logs"),store=Path.Combine(logRoot,"CpvPreparation"),runtime=Path.Combine(testRoot,"runtime");Directory.CreateDirectory(store);Directory.CreateDirectory(runtime);
        var rr=Request();string run=Path.Combine(runtime,"cpv-preparation-"+rr.RunId);Directory.CreateDirectory(run);
        string modelPath=Path.Combine(run,"model.rvt"),runnerPath=Path.Combine(run,"tara-"+rr.AttemptId+".request.json"),resultPath=runnerPath+".preparation.json";
        File.Copy(@"C:\Repato-Autonomous\Source\QA\Fixtures\CreatePlanViewsEmpty.rvt",modelPath);
        if(corruptModel) File.AppendAllText(modelPath,"changed");
        string modelHash=CpvPreparationService.Hash(modelPath);
        var runner=new {schemaVersion=1,operation=CpvPreparationService.RunnerOperation,requestId=rr.AttemptId,taskId=rr.TaskId,workflowId=rr.WorkflowId,attemptId=rr.AttemptId,runId=rr.RunId,requestPath=runnerPath,modelPath,modelSha256=CpvPreparationService.FixtureSha256,selectedManifestPath=QaLaunchPolicy.ExpectedRunnerManifestPath,selectedManifestSha256=rr.CandidateEvidence.RunnerManifestSha256,outputPath=resultPath,expiresUtc=rr.ExpiresUtc};
        File.WriteAllText(runnerPath,JsonSerializer.Serialize(runner));
        string result=JsonSerializer.Serialize(new {Status="Passed",Operation=CpvPreparationService.RunnerOperation,TaskId=rr.TaskId,WorkflowId=rr.WorkflowId,AttemptId=rr.AttemptId,RunId=rr.RunId,ModelPath=modelPath,SourceModelSha256=CpvPreparationService.FixtureSha256,PreparedModelSha256=modelHash,Levels=new[]{new{Name="0",ElevationMeters=0d,ElementId=101L},new{Name="1",ElevationMeters=4d,ElementId=202L},new{Name="2",ElevationMeters=7.8d,ElementId=303L}}});
        if(!missingResult) File.WriteAllText(resultPath,corruptResult?result.Replace(rr.RunId,Guid.NewGuid().ToString("N")):result);
        var original=new CpvPreparationReceipt(1,CpvPreparationService.Operation,rr.RequestId,rr.TaskId,rr.WorkflowId,rr.AttemptId,rr.RunId,"OutcomeUnknown",identity.User,identity.Sid,identity.SessionId,rr.CandidateEvidence.CandidateDllSha256,rr.CandidateEvidence.RunnerManifestSha256,modelPath,"",runnerPath,"","","",false,"Unknown","preparation-failed-reconcile-required",rr.ExpiresUtc);
        string originalJson=JsonSerializer.Serialize(original,CpvPreparationService.StrictJson),requestJson=Json(rr);
        string originalPath=Path.Combine(store,rr.RequestId+".json"),requestPath=Path.Combine(store,rr.RequestId+".request.json");
        File.WriteAllText(originalPath,originalJson);File.WriteAllText(requestPath,requestJson);File.WriteAllText(Path.Combine(store,"active.json"),requestJson);string failurePath=Path.Combine(store,rr.RequestId+".failure.txt");File.WriteAllText(failurePath,"IOException: model remained locked after Revit child exit");
        var q=new CpvPreparationCompletedRecovery(1,CpvPreparationService.RecoverCompletedOperation,rr.RequestId,rr.TaskId,rr.WorkflowId,rr.AttemptId,rr.RunId,Guid.NewGuid().ToString("N"),101,new string('E',64),expiredAuthorization?now.AddMinutes(-1):now.AddMinutes(10),CpvPreparationService.Hash(originalPath),CpvPreparationService.Hash(Path.Combine(store,"active.json")),CpvPreparationService.Hash(failurePath),CpvPreparationService.Hash(requestPath),missingResult?new string('0',64):CpvPreparationService.Hash(resultPath),wrongBinding?new string('0',64):modelHash);
        var svc=new CpvPreparationService(Options("completed-"+name) with {LogRoot=logRoot,RuntimeRoot=runtime},identity,new Ledger(),boundary);
        return (null!,svc,store,originalJson,q);
    }
    var completedBoundary=new Boundary();
    var completed=CompletedRecoveryCase("valid");
    var committed=(CpvPreparationRecoveryCommit)completed.Service.Handle(JsonSerializer.Serialize(completed.Query,CpvPreparationService.StrictJson),now);
    Check(committed.Receipt.Status=="Passed" && committed.Receipt.CleanupVerified && committed.Receipt.RollbackStatus=="CommittedDisposableFixtureOnly","authenticated recovery requires passed result and exclusive model verification");
    Check(File.ReadAllText(Path.Combine(completed.Store,completed.Query.RequestId+".json"))==completed.OriginalJson,"recovery preserves original failure receipt bytes");
    Check(!File.Exists(Path.Combine(completed.Store,"active.json")) && File.Exists(Path.Combine(completed.Store,completed.Query.RequestId+".recovered.json")),"recovery receipt is durable before exact active marker removal");
    var recoveredStatus=(CpvPreparationReceipt)completed.Service.Handle(JsonSerializer.Serialize(new CpvPreparationQuery(1,CpvPreparationService.StatusOperation,completed.Query.RequestId),CpvPreparationService.StrictJson),now);
    Check(recoveredStatus.Status=="Passed" && recoveredStatus.ModelSha256==completed.Query.ModelSha256,"status exposes verified recovery only after marker removal");
    var recoveryCommitStatus=(CpvPreparationRecoveryCommit)completed.Service.Handle(JsonSerializer.Serialize(new CpvPreparationCompletedRecoveryStatus(1,CpvPreparationService.RecoverCompletedStatusOperation,completed.Query.RequestId),CpvPreparationService.StrictJson),now);
    Check(recoveryCommitStatus.RecoveryApprovalId==completed.Query.RecoveryApprovalId && recoveryCommitStatus.ExpectedTaskRevision==completed.Query.ExpectedTaskRevision,"authenticated recovery status binds terminal evidence to approval and task revision");
    Reject(()=>completed.Service.Handle(JsonSerializer.Serialize(completed.Query,CpvPreparationService.StrictJson),now),"duplicate completed recovery after terminal commit");
    foreach(var item in new[]{CompletedRecoveryCase("bad-result",corruptResult:true),CompletedRecoveryCase("missing-result",missingResult:true),CompletedRecoveryCase("model-binding",wrongBinding:true),CompletedRecoveryCase("bad-model",corruptModel:true),CompletedRecoveryCase("expired",expiredAuthorization:true)})
    {
        Reject(()=>item.Service.Handle(JsonSerializer.Serialize(item.Query,CpvPreparationService.StrictJson),now),"invalid completed recovery evidence or expiry");
        Check(File.Exists(Path.Combine(item.Store,"active.json")),"failed recovery preserves active marker");
    }
    Console.WriteLine($"PASS: {assertions} CPV preparation protocol assertions; injected processes only; Revit launched=false.");
} finally {Directory.Delete(root,true);}

sealed class Identity:IIdentitySessionProvider {public string User{get;set;}=QaLaunchPolicy.ExpectedUser;public string Sid{get;set;}=QaLaunchPolicy.ExpectedUserSid;public int SessionId=>1;public bool Interactive{get;set;}=true;}
sealed class Ledger:IReplayLedger {readonly HashSet<string> keys=[];public int Count=>keys.Count;public bool TryReserve(string id,DateTimeOffset now)=>keys.Add(id);public bool TryReserve(QaLaunchRequest r,DateTimeOffset now)=>TryReserve(r.RequestId,now);}
sealed class Boundary:ICpvPreparationBoundary {
    public string? ValidationError{get;set;}
    public string? ReconciliationError{get;set;}
    public TaskCompletionSource<CpvPreparationOutcome> Completion{get;}=new(TaskCreationOptions.RunContinuationsAsynchronously);
    public void Validate(CpvPreparationRequest r){if(ValidationError!=null)throw new InvalidDataException(ValidationError);}
    public IDisposable ValidateReconciliation(CpvPreparationRequest r,CpvPreparationReceipt receipt){if(ReconciliationError!=null)throw new InvalidDataException(ReconciliationError);var stream=File.Open(receipt.ModelPath,FileMode.Open,FileAccess.Read,FileShare.None);if(Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(stream))!=CpvPreparationService.FixtureSha256){stream.Dispose();throw new InvalidDataException("reconciliation-model-hash-mismatch");}return stream;}
    public async Task<CpvPreparationOutcome> Execute(CpvPreparationRequest r,string dir){Directory.CreateDirectory(dir);File.WriteAllText(Path.Combine(dir,"tara-"+r.AttemptId+".request.json"),"synthetic");return await Completion.Task;}
}
