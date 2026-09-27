using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Repato.QaLaunchAgent;

public interface IReplayLedger { bool TryReserve(QaLaunchRequest request, DateTimeOffset now); }

public sealed class FileReplayLedger(string path) : IReplayLedger
{
    private sealed record Entry(string RequestId, string RunId, string PayloadHash, DateTimeOffset SeenUtc);
    private readonly object gate = new();
    public bool TryReserve(QaLaunchRequest request, DateTimeOffset now)
    {
        lock (gate)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var entries = File.Exists(path) ? JsonSerializer.Deserialize<List<Entry>>(File.ReadAllText(path)) ?? [] : [];
            entries.RemoveAll(e => e.SeenUtc < now.AddHours(-24));
            var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(request))));
            var old = entries.FirstOrDefault(e => e.RequestId == request.RequestId);
            if (old is not null) return false;
            entries.Add(new Entry(request.RequestId, request.RunId, hash, now));
            var temp = path + ".tmp";
            File.WriteAllText(temp, JsonSerializer.Serialize(entries));
            File.Move(temp, path, true);
            return true;
        }
    }
}
