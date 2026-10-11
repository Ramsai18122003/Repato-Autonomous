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
        security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(options.ClientSid), PipeAccessRights.ReadWrite, AccessControlType.Allow));
        using var pipe = NamedPipeServerStreamAcl.Create(options.PipeName, PipeDirection.InOut, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 8192, 8192, security);
        await pipe.WaitForConnectionAsync(cancellationToken);
        using var reader = new StreamReader(pipe);
        var line = await reader.ReadLineAsync(cancellationToken);
        if (line is null || line.Length > 32768) throw new InvalidDataException("Bounded request rejected.");
        object response;
        try
        {
            using var document = JsonDocument.Parse(line);
            var operation = document.RootElement.TryGetProperty("operation", out var op) ? op.GetString() : null;
            if (operation == QaLaunchPolicy.HealthOperation)
            {
                var identity = WindowsIdentity.GetCurrent();
                response = new QaHealthResponse(1, QaLaunchPolicy.HealthOperation, true, identity.Name, identity.User?.Value ?? "", System.Diagnostics.Process.GetCurrentProcess().SessionId, Environment.UserInteractive, null);
            }
            else if (operation == QaLaunchPolicy.PreflightOperation)
            {
                var request = JsonSerializer.Deserialize<QaPreflightRequest>(line, QaLaunchPolicy.JsonOptions);
                response = coordinator.HandlePreflight(request);
            }
            else if (operation == QaLaunchPolicy.StageOperation)
            {
                var request = JsonSerializer.Deserialize<QaStageRequest>(line, QaLaunchPolicy.JsonOptions) ?? throw new InvalidDataException();
                response = coordinator.HandleStage(request, DateTimeOffset.UtcNow);
            }
            else if (operation == QaLaunchPolicy.ValidateDeploymentOperation)
            {
                var request = JsonSerializer.Deserialize<QaDeploymentValidationRequest>(line, QaLaunchPolicy.JsonOptions) ?? throw new InvalidDataException();
                response = coordinator.HandleDeploymentValidation(request, DateTimeOffset.UtcNow);
            }
            else
            {
                var request = JsonSerializer.Deserialize<QaLaunchRequest>(line, QaLaunchPolicy.JsonOptions) ?? throw new InvalidDataException();
                response = coordinator.Handle(request, DateTimeOffset.UtcNow, line);
            }
        }
        catch { response = new QaLaunchResponseV2(2, QaLaunchPolicy.Operation, "", "", false, null, null, null, null, null, null, null, null, null, null, null, null, null, "malformed-request"); }
        try
        {
            using var writer = new StreamWriter(pipe, leaveOpen: true) { AutoFlush = true };
            await writer.WriteLineAsync(SerializeResponse(response));
        }
        catch (IOException)
        {
            // A client may time out while a bounded staging/validation adapter is still running.
            // Its disconnect must not terminate the long-lived scheduled-task listener.
        }
    }

    public static string SerializeResponse(object response) =>
        JsonSerializer.Serialize(response, response.GetType(), QaLaunchPolicy.JsonOptions);
}
