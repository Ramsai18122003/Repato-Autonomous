using System.Security.Principal;

namespace Repato.QaLaunchAgent;

internal static class Program
{
    // Phase 1 deliberately exposes no live listener. Phase 2 will bind the
    // restricted named pipe only after one-time RepatoQA installation.
    public static int Main(string[] args)
    {
        if (!OperatingSystem.IsWindows()) return 2;
        if (!string.Equals(WindowsIdentity.GetCurrent().Name, QaLaunchPolicy.ExpectedUser, StringComparison.OrdinalIgnoreCase)) return 3;
        var options = new QaAgentOptions(
            @"E:\revit\Revit 2025\Revit.exe",
            @"C:\Repato-Autonomous\Source\QA\TestRuns",
            @"C:\Users\RepatoQA\AppData\Roaming\Autodesk\Revit\Addins\2025",
            @"C:\Users\RepatoQA\AppData\Local\Repato\QaLaunchAgent\replay.json");
        var coordinator = new LaunchCoordinator(options, new CurrentIdentitySessionProvider(), new FileReplayLedger(options.ReplayLedgerPath), new RevitChildProcessLauncher(), new StrictChildProcessVerifier());
        var server = new NamedPipeLaunchServer(options, coordinator);
        while (true) server.ServeOnceAsync(CancellationToken.None).GetAwaiter().GetResult();
    }
}
