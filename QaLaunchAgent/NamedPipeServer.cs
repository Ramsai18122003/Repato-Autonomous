using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;

namespace Repato.QaLaunchAgent;

public sealed class NamedPipeLaunchServer(QaAgentOptions options, LaunchCoordinator coordinator)
{
    public async Task ServeOnceAsync(CancellationToken cancellationToken)
    {
        var security = new PipeSecurity();
        security.SetAccessRuleProtection(true, false);
        security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), PipeAccessRights.FullControl, AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null), PipeAccessRights.FullControl, AccessControlType.Allow));
        if (!string.IsNullOrWhiteSpace(options.OrchestrationSid)) security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(options.OrchestrationSid), PipeAccessRights.ReadWrite, AccessControlType.Allow));
        using var pipe = NamedPipeServerStreamAcl.Create(options.PipeName, PipeDirection.InOut, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 8192, 8192, security);
        await pipe.WaitForConnectionAsync(cancellationToken);
        using var reader = new StreamReader(pipe);
        var line = await reader.ReadLineAsync(cancellationToken);
        if (line is null || line.Length > 32768) throw new InvalidDataException("Bounded request rejected.");
        QaLaunchResponse response;
        try { response = coordinator.Handle(JsonSerializer.Deserialize<QaLaunchRequest>(line) ?? throw new InvalidDataException(), DateTimeOffset.UtcNow); }
        catch { response = new(1, "", false, null, null, null, null, null, null, null, "malformed-request"); }
        using var writer = new StreamWriter(pipe) { AutoFlush = true };
        await writer.WriteLineAsync(JsonSerializer.Serialize(response));
    }
}
