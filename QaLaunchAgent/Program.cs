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
        return 0;
    }
}
