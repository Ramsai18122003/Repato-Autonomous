using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;
using Autodesk.Revit.DB;

namespace Repato.Revit.TestRunner;

internal static class TestSafetyGate
{
    internal static readonly string[] ApprovedGridBubbleFixtureNames = FixtureContentPolicy.ApprovedGridNames;
    internal const string RepositoryRoot = QAPathPolicy.RepositoryRoot;
    internal const string RunsRoot = RepositoryRoot + @"\QA\TestRuns";
    internal const string ReportsRoot = RepositoryRoot + @"\QA\Reports";
    private const string FixturesRoot = RepositoryRoot + @"\QA\Fixtures";

    internal static void Verify(Document document, TestRunReport report, string? requiredFixtureId = null,
        CreatePlanViewsRequest? request = null)
    {
        if (document.IsFamilyDocument || document.IsLinked || document.IsReadOnly || document.IsModified || document.IsModifiable ||
            document.IsWorkshared || document.IsModelInCloud || document.IsDetached)
            throw new InvalidOperationException("Reject family, linked, read-only, modified, modifiable, workshared, cloud or detached documents.");
        string path = QAPathPolicy.ValidatePath(document.PathName, RunsRoot, true);
        report.DocumentPath = path;
        using (BasicFileInfo info = BasicFileInfo.Extract(path))
            if (info.IsWorkshared || info.IsCentral || info.IsLocal)
                throw new InvalidOperationException("The saved file has worksharing/central metadata.");
        string[] gridNames = new FilteredElementCollector(document).OfClass(typeof(Grid)).Cast<Grid>().Select(g => g.Name).ToArray();
        int linkCount = new FilteredElementCollector(document).OfClass(typeof(RevitLinkType)).Count();
        FixtureContentPolicy.Validate(requiredFixtureId, gridNames, linkCount);
        report.Assert(
            "fixture-content-policy",
            true,
            new { GridNames = FixtureContentPolicy.ApprovedNames(requiredFixtureId) ?? Array.Empty<string>(), RevitLinkCount = 0 },
            new { GridNames = gridNames.Order(StringComparer.Ordinal).ToArray(), RevitLinkCount = linkCount }
        );

        string sidecarPath = QAPathPolicy.ValidatePath(path + ".fixture.json", RunsRoot, false);
        using var json = JsonDocument.Parse(RecoveredFixtureProvenance.Resolve(path, request).GetRawText());
        string fixtureId = json.RootElement.GetProperty("fixtureId").GetString() ?? "";
        string expectedHash = json.RootElement.GetProperty("sourceSha256").GetString() ?? "";
        if (requiredFixtureId is not null && !string.Equals(fixtureId, requiredFixtureId, StringComparison.Ordinal))
            throw new InvalidOperationException("This test requires fixture " + requiredFixtureId + ".");
        if (!Regex.IsMatch(fixtureId, @"\A[A-Za-z0-9][A-Za-z0-9_-]{0,79}\z") ||
            !Regex.IsMatch(expectedHash, @"\A[0-9A-Fa-f]{64}\z"))
            throw new InvalidOperationException("Invalid fixture provenance sidecar.");
        string[]? approvedNames = FixtureContentPolicy.ApprovedNames(fixtureId);
        if (approvedNames is not null)
        {
            string[] declared = json.RootElement.TryGetProperty("requiredGridNames", out JsonElement names)
                ? names.EnumerateArray().Select(item => item.GetString() ?? "").ToArray()
                : [];
            if (!FixtureContentPolicy.SameNames(declared, approvedNames))
                throw new InvalidOperationException("Fixture sidecar does not declare the exact approved grid set.");
        }
        string fixturePath = QAPathPolicy.ValidatePath(Path.Combine(FixturesRoot, fixtureId + ".rvt"), FixturesRoot, true);

        TestSafetyGateProvenance.Verify(json.RootElement, TestRunReport.Hash(fixturePath), TestRunReport.Hash(path), request);

        report.FixtureId = fixtureId;
        report.FixtureSha256 = expectedHash;
        report.Assert("safety-gate", true, "Controlled local disposable fixture", path);
    }

}

