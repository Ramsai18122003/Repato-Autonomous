using System.IO.Pipes;
using System.Text.Json;

namespace Repato.QaLaunchAgent;

public interface IQaLaunchTransport
{
    QaLaunchResponse Send(QaLaunchRequest request, TimeSpan timeout);
}

public sealed class NamedPipeQaLaunchTransport(string pipeName = "Repato\\QaLaunch") : IQaLaunchTransport
{
    public QaLaunchResponse Send(QaLaunchRequest request, TimeSpan timeout)
    {
        using var pipe = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut, PipeOptions.WriteThrough);
        pipe.Connect((int)timeout.TotalMilliseconds);
        var json = JsonSerializer.Serialize(request);
        using var writer = new StreamWriter(pipe) { AutoFlush = true };
        writer.WriteLine(json);
        using var reader = new StreamReader(pipe);
        return JsonSerializer.Deserialize<QaLaunchResponse>(reader.ReadLine() ?? "")
            ?? throw new InvalidDataException("Empty QA launch response.");
    }
}
