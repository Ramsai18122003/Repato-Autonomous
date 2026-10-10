using System.IO;
using System.Text.Json;
using Autodesk.Revit.DB;
using Autodesk.Revit.UI;
using Autodesk.Revit.UI.Events;

namespace Repato.Revit.TestRunner;

// QA-only application entry point selected by Repato.CreatePlanViews.TestRunner.addin.
public sealed class CreatePlanViewsQaApplication : IExternalApplication
{
    public const string RequestEnvironmentVariable = "REPATO_QA_CREATE_PLAN_VIEWS_REQUEST";
    private string? requestPath;

    public Result OnStartup(UIControlledApplication application)
    {
        requestPath = Environment.GetEnvironmentVariable(RequestEnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(requestPath)) application.Idling += RunOnce;
        return Result.Succeeded;
    }

    public Result OnShutdown(UIControlledApplication application)
    {
        application.Idling -= RunOnce;
        return Result.Succeeded;
    }

    private void RunOnce(object? sender, IdlingEventArgs args)
    {
        if (sender is not UIApplication app) return;
        app.Idling -= RunOnce;
        CreatePlanViewsRequest? request = null;
        string? receiptPath = null;
        var report = new TestRunReport
        {
            TestId = CreatePlanViewsRequest.Test,
            FixtureId = "CreatePlanViewsEmpty",
            Inputs = new { Levels = new[] { "0", "1", "2" }, ViewType = "FloorPlan", Scale = 100, TemplateIntent = "Architectural" }
        };
        try
        {
            string path = QAPathPolicy.ValidatePath(requestPath!, QAPathPolicy.RunsRoot, false);
            receiptPath = QAPathPolicy.ValidatePath(path + ".result.json", QAPathPolicy.RunsRoot, false);
            if (File.Exists(receiptPath)) throw new InvalidOperationException("This QA request already has a result; prepare a new attempt.");
            string json = File.ReadAllText(path);
            request = CreatePlanViewsRequest.Parse(json, path);
            report.RunId = request.RunId;
            report.RequestId = request.RequestId;
            report.TaskId = request.TaskId;
            report.WorkflowId = request.WorkflowId;
            report.AttemptId = request.AttemptId;
            report.ClaimId = request.ClaimId;
            report.IdentifyAssembly();
            report.RevitVersion = $"{app.Application.VersionName}; {app.Application.VersionNumber}; {app.Application.VersionBuild}";
            report.Assert("request-identity", true, new { request.RequestId, request.TaskId, request.WorkflowId, request.AttemptId, request.RunId, request.ClaimId },
                new { request.RequestId, request.TaskId, request.WorkflowId, request.AttemptId, request.RunId, request.ClaimId });
            if (request.ExpiresUtc <= DateTimeOffset.UtcNow) throw new InvalidOperationException("QA request expired before execution.");
            if (!string.Equals(Environment.UserName, "RepatoQA", StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Automated startup is restricted to the RepatoQA Windows account.");
            if (app.Application.VersionNumber != "2025" || app.Application.Documents.Size != 0) throw new InvalidOperationException("Start a fresh Revit 2025 QA session with no open documents.");

            string manifestPath = Path.GetFullPath(request.ManifestPath);
            if (!File.Exists(manifestPath) || !TestRunReport.Hash(manifestPath).Equals(request.ManifestSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Selected runner manifest is missing or its request-bound SHA-256 changed.");
            VerifyManifestBinding(manifestPath);
            AddinIsolationPolicy.RequireAllowed(report, manifestPath, request.ManifestSha256);

            string model = QAPathPolicy.ValidatePath(request.ModelPath, QAPathPolicy.RunsRoot, true);
            if (!Path.GetDirectoryName(model)!.Equals(Path.GetDirectoryName(path), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Request and disposable model must be in the same attempt directory.");
            if (!TestRunReport.Hash(model).Equals(request.ModelSha256, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Disposable model SHA-256 does not match the launch request.");
            string fixture = QAPathPolicy.ValidatePath(Path.Combine(QAPathPolicy.RepositoryRoot, "QA", "Fixtures", "CreatePlanViewsEmpty.rvt"),
                Path.Combine(QAPathPolicy.RepositoryRoot, "QA", "Fixtures"), true);
            string sidecar = QAPathPolicy.ValidatePath(model + ".fixture.json", QAPathPolicy.RunsRoot, false);
            using (var provenance = JsonDocument.Parse(File.ReadAllText(sidecar)))
            {
                JsonElement root = provenance.RootElement;
                string fixtureHash = root.GetProperty("sourceSha256").GetString() ?? "";
                if (root.GetProperty("fixtureId").GetString() != "CreatePlanViewsEmpty" ||
                    !fixtureHash.Equals(TestRunReport.Hash(fixture), StringComparison.OrdinalIgnoreCase) ||
                    !fixtureHash.Equals(request.ModelSha256, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Controlled CreatePlanViewsEmpty fixture provenance failed.");
                report.FixtureSha256 = fixtureHash;
            }
            using (BasicFileInfo info = BasicFileInfo.Extract(model))
                if (info.IsWorkshared || info.IsCentral || info.IsLocal || info.Format != "2025")
                    throw new InvalidOperationException("Only the disposable local, non-workshared Revit 2025 fixture is allowed.");

            app.OpenAndActivateDocument(model);
            if (request.ExpiresUtc <= DateTimeOffset.UtcNow) throw new InvalidOperationException("QA request expired while opening the disposable model.");
            Document document = app.ActiveUIDocument?.Document ?? throw new InvalidOperationException("QA model did not become active.");
            TestSafetyGate.Verify(document, report, "CreatePlanViewsEmpty");
            Execute(document, report);
            report.RuntimeModelSha256 = TestRunReport.Hash(model);
            report.Assert("runtime-model-restored", report.RuntimeModelSha256.Equals(request.ModelSha256, StringComparison.OrdinalIgnoreCase), request.ModelSha256, report.RuntimeModelSha256);
        }
        catch (Exception ex)
        {
            report.Status = "Failed";
            report.Errors.Add("Create Plan Views runner failure: " + ex);
        }
        finally
        {
            report.FinishedUtc = DateTimeOffset.UtcNow;
            report.DurationMilliseconds = (report.FinishedUtc - report.StartedUtc).TotalMilliseconds;
            if (report.RollbackStatus != "RolledBack") report.Status = "Failed";
            try
            {
                string reportFile = report.Write();
                if (request is not null && receiptPath is not null)
                    QaRunnerFoundation.WriteReceiptAtomic(receiptPath, CreatePlanViewsResultContract.CreateReceipt(request,
                        report.RequestId, report.TaskId, report.WorkflowId, report.TestId, report.AttemptId, report.RunId,
                        report.ClaimId, report.Status, reportFile));
            }
            catch (Exception ex)
            {
                app.Application.WriteJournalComment("Repato Create Plan Views QA evidence failure: " + ex, false);
            }
        }
    }

    private static void VerifyManifestBinding(string manifestPath)
    {
        var xml = new System.Xml.XmlDocument { XmlResolver = null };
        xml.Load(manifestPath);
        var application = xml.SelectSingleNode("/RevitAddIns/AddIn[@Type='Application']") as System.Xml.XmlElement
            ?? throw new InvalidDataException("Selected manifest has no application entry.");
        if (application.SelectSingleNode("FullClassName")?.InnerText != typeof(CreatePlanViewsQaApplication).FullName)
            throw new InvalidDataException("Selected manifest does not bind this exact Create Plan Views runner class.");
        string assembly = application.SelectSingleNode("Assembly")?.InnerText ?? "";
        string assemblyPath = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(manifestPath)!, assembly));
        if (!File.Exists(assemblyPath) || !Path.GetFullPath(typeof(CreatePlanViewsQaApplication).Assembly.Location).Equals(assemblyPath, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Manifest assembly path does not resolve to the loaded candidate assembly.");
    }

    private static void Execute(Document document, TestRunReport report)
    {
        var levels = new[] { "0", "1", "2" }.Select(name =>
            new FilteredElementCollector(document).OfClass(typeof(Level)).Cast<Level>()
                .SingleOrDefault(level => level.Name.Equals(name, StringComparison.OrdinalIgnoreCase)))
            .ToArray();
        if (levels.Any(level => level is null)) throw new InvalidOperationException("Required levels 0, 1, and 2 are not present in the controlled fixture.");
        report.Assert("required-levels-present", true, new[] { "0", "1", "2" }, levels.Select(level => level!.Name).ToArray());
        ViewFamilyType floorPlanType = new FilteredElementCollector(document).OfClass(typeof(ViewFamilyType)).Cast<ViewFamilyType>()
            .SingleOrDefault(type => type.ViewFamily == ViewFamily.FloorPlan) ?? throw new InvalidOperationException("Floor-plan view family type is unavailable.");
        ViewPlan template = new FilteredElementCollector(document).OfClass(typeof(ViewPlan)).Cast<ViewPlan>()
            .SingleOrDefault(view => view.IsTemplate && view.Name.Contains("Architectural", StringComparison.OrdinalIgnoreCase))
            ?? throw new InvalidOperationException("Architectural view template is unavailable.");
        report.Assert("architectural-template-intent", true, "Architectural", template.Name);

        var baselinePlanIds = new FilteredElementCollector(document).OfClass(typeof(ViewPlan)).Cast<ViewPlan>()
            .Select(view => view.Id.Value).Order().ToArray();
        using var group = new TransactionGroup(document, "Repato QA Create Plan Views - rollback required");
        if (group.Start() != TransactionStatus.Started) throw new InvalidOperationException("Could not start QA transaction group.");
        report.RollbackStatus = "Required";
        try
        {
            using var transaction = new Transaction(document, "Create Plan Views QA");
            if (transaction.Start() != TransactionStatus.Started) throw new InvalidOperationException("Could not start Create Plan Views transaction.");
            foreach (Level level in levels!)
            {
                ViewPlan view = ViewPlan.Create(document, floorPlanType.Id, level.Id);
                view.Name = "Floor Plan - Level " + level.Name;
                view.Scale = 100;
                view.ViewTemplateId = template.Id;
                report.CreatedIds.Add(view.Id.Value.ToString());
                bool matches = view.ViewType == ViewType.FloorPlan && view.GenLevel?.Id == level.Id && view.Scale == 100 &&
                    view.Name == "Floor Plan - Level " + level.Name && view.ViewTemplateId == template.Id;
                report.Assert("created-floor-plan-level-" + level.Name, matches,
                    new { ViewType = "FloorPlan", Level = level.Name, Scale = 100, Template = template.Name },
                    new { ViewType = view.ViewType.ToString(), Level = view.GenLevel?.Name, view.Scale, view.Name, TemplateId = view.ViewTemplateId.Value });
                if (!matches) throw new InvalidOperationException("Created floor plan did not meet the requested view contract for level " + level.Name + ".");
            }
            if (transaction.Commit() != TransactionStatus.Committed) throw new InvalidOperationException("Create Plan Views transaction did not commit for inspection.");
        }
        finally
        {
            report.RollbackStatus = group.RollBack().ToString();
        }
        long[] finalPlanIds = new FilteredElementCollector(document).OfClass(typeof(ViewPlan)).Cast<ViewPlan>()
            .Select(view => view.Id.Value).Order().ToArray();
        bool restored = baselinePlanIds.SequenceEqual(finalPlanIds);
        report.Assert("rollback-status", report.RollbackStatus == "RolledBack", "RolledBack", report.RollbackStatus);
        report.Assert("baseline-plan-views-restored", restored, baselinePlanIds, finalPlanIds);
        if (!restored || report.RollbackStatus != "RolledBack") throw new InvalidOperationException("Transaction rollback did not restore the baseline plan views.");
        report.Status = report.Errors.Count == 0 && report.Assertions.Count > 0 && report.Assertions.All(assertion => assertion.Passed) ? "Passed" : "Failed";
    }
}
