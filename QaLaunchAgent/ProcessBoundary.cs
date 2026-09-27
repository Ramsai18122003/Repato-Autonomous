using System.Diagnostics;
using System.Security.Principal;

namespace Repato.QaLaunchAgent;

public sealed record ChildLaunchResult(int Pid, string User, int SessionId, string ImagePath, DateTimeOffset LaunchUtc);
public interface IIdentitySessionProvider { string User { get; } string Sid { get; } int SessionId { get; } bool Interactive { get; } }
public interface IChildProcessLauncher { ChildLaunchResult Launch(QaLaunchRequest request, QaAgentOptions options); }
public interface IChildProcessVerifier { bool Verify(ChildLaunchResult result, QaLaunchRequest request, QaAgentOptions options); }

public sealed class CurrentIdentitySessionProvider : IIdentitySessionProvider
{
    public string User => WindowsIdentity.GetCurrent().Name;
    public string Sid => WindowsIdentity.GetCurrent().User?.Value ?? "";
    public int SessionId => Process.GetCurrentProcess().SessionId;
    public bool Interactive => Environment.UserInteractive;
}

public sealed class RevitChildProcessLauncher : IChildProcessLauncher
{
    public ChildLaunchResult Launch(QaLaunchRequest request, QaAgentOptions options)
    {
        var psi = new ProcessStartInfo(options.RevitExe) { UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(options.RevitExe)! };
        psi.Environment[QaLaunchPolicy.RequestEnvironmentVariable] = request.RequestPath;
        using var process = Process.Start(psi) ?? throw new InvalidOperationException("Revit process creation failed.");
        return new ChildLaunchResult(process.Id, WindowsIdentity.GetCurrent().Name, process.SessionId, options.RevitExe, DateTimeOffset.UtcNow);
    }
}

public sealed class StrictChildProcessVerifier : IChildProcessVerifier
{
    public bool Verify(ChildLaunchResult result, QaLaunchRequest request, QaAgentOptions options) =>
        result.Pid > 0 && result.User.Equals(options.ExpectedUser, StringComparison.OrdinalIgnoreCase) &&
        result.ImagePath.Equals(options.RevitExe, StringComparison.OrdinalIgnoreCase) &&
        result.SessionId == Process.GetCurrentProcess().SessionId;
}
