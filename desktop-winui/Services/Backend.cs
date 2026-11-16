using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace InvisMark.Desktop.Services;

/// <summary>嵌入结果（对应 CLI `embed --out` 的 JSON）</summary>
public sealed class EmbedInfo
{
    public string AssetId { get; init; } = "";
    public string TraceId { get; init; } = "";
    public string ResourceCode { get; init; } = "";
    public string? CustomText { get; init; }
    public int UserIndex { get; init; }
    public double Psnr { get; init; }
    public double Ssim { get; init; }
    public int BlocksPerBit { get; init; }
    public string EmbeddedAt { get; init; } = "";
    public string Output { get; init; } = "";
    public double ElapsedMs { get; init; }
}

/// <summary>提取结果（对应 CLI `extract` 的 JSON）</summary>
public sealed class ExtractInfo
{
    public bool Found { get; init; }
    public string TraceId { get; init; } = "";
    public string ResourceCode { get; init; } = "";
    public string? CustomText { get; init; }
    public int UserIndex { get; init; }
    public string EmbeddedAt { get; init; } = "";
    public double Confidence { get; init; }
    public int CorrectedBytes { get; init; }
    public double Ber { get; init; }
    public bool Registered { get; init; }
    public double ElapsedMs { get; init; }
}

public sealed class BatchItem
{
    public string Src { get; init; } = "";
    public string Dst { get; init; } = "";
    public bool Ok { get; init; }
    public string TraceId { get; init; } = "";
    public string Error { get; init; } = "";
    public double Psnr { get; init; }
}

/// <summary>
/// 本地后端：调用随包分发的 InvisMarkCLI.exe（PyInstaller onefile）。
/// 桌面端不重复实现算法，保证与 Python 参考实现/移动端同一套语义。
/// </summary>
public sealed class Backend
{
    private readonly string _cli;
    private readonly string _dbPath;
    private readonly string _dataDir;

    public Backend()
    {
        var baseDir = AppContext.BaseDirectory;
        var candidates = new[]
        {
            Path.Combine(baseDir, "backend", "InvisMarkCLI.exe"),
            Path.Combine(baseDir, "InvisMarkCLI.exe"),
        };
        foreach (var candidate in candidates)
        {
            if (File.Exists(candidate))
            {
                _cli = candidate;
                break;
            }
        }
        _cli ??= candidates[0];

        // 便携数据目录：跟着程序走，避免受限账户/只读目录写不了 %APPDATA%
        _dataDir = Path.Combine(baseDir, "data");
        try
        {
            Directory.CreateDirectory(_dataDir);
        }
        catch
        {
            _dataDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "InvisMark");
            Directory.CreateDirectory(_dataDir);
        }
        _dbPath = Path.Combine(_dataDir, "invismark.db");
    }

    public bool Available => File.Exists(_cli);
    public string CliPath => _cli;
    public string DataDir => _dataDir;

    public async Task<(int Code, string Stdout, string Stderr)> RunAsync(params string[] args)
    {
        if (!Available)
        {
            return (-1, "", "未找到后端 InvisMarkCLI.exe（应位于程序目录 backend/ 下）");
        }
        var psi = new ProcessStartInfo(_cli)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        if (args.Length > 0)
        {
            psi.ArgumentList.Add(args[0]);
            psi.ArgumentList.Add("--db");
            psi.ArgumentList.Add(_dbPath);
            psi.ArgumentList.Add("--data");
            psi.ArgumentList.Add(_dataDir);
        }
        foreach (var arg in args.Skip(1))
        {
            psi.ArgumentList.Add(arg);
        }
        using var process = new Process { StartInfo = psi };
        process.Start();
        var stdout = await process.StandardOutput.ReadToEndAsync().ConfigureAwait(false);
        var stderr = await process.StandardError.ReadToEndAsync().ConfigureAwait(false);
        await process.WaitForExitAsync().ConfigureAwait(false);
        return (process.ExitCode, stdout, stderr);
    }

    public async Task<EmbedInfo> EmbedAsync(string input, string output, string resourceCode, string customText = "", string user = "desktop")
    {
        var (code, stdout, stderr) = await RunAsync("embed", "--in", input, "--out", output,
            "--resource", resourceCode ?? "", "--text", customText ?? "", "--user", user).ConfigureAwait(false);
        if (code != 0)
        {
            throw new BackendException(Friendly(stderr, "嵌入失败"));
        }
        using var doc = JsonDocument.Parse(stdout);
        var root = doc.RootElement;
        var quality = root.TryGetProperty("quality", out var q) ? q : default;
        double ReadDouble(JsonElement e, string name) =>
            e.ValueKind == JsonValueKind.Object && e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number
                ? v.GetDouble() : 0;
        int ReadInt(JsonElement e, string name) =>
            e.ValueKind == JsonValueKind.Object && e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number
                ? v.GetInt32() : 0;
        string ReadStr(JsonElement e, string name) =>
            e.ValueKind == JsonValueKind.Object && e.TryGetProperty(name, out var v) ? v.GetString() ?? "" : "";

        return new EmbedInfo
        {
            AssetId = ReadStr(root, "asset_id"),
            TraceId = ReadStr(root, "trace_id"),
            ResourceCode = ReadStr(root, "resource_code"),
            CustomText = ReadStr(root, "custom_text") is { Length: > 0 } ct ? ct : null,
            UserIndex = ReadInt(root, "user_index"),
            Psnr = ReadDouble(quality, "psnr"),
            Ssim = ReadDouble(quality, "ssim"),
            BlocksPerBit = ReadInt(quality, "blocks_per_bit"),
            EmbeddedAt = ReadStr(root, "embedded_at"),
            Output = ReadStr(root, "output"),
            ElapsedMs = ReadDouble(root, "elapsed_ms"),
        };
    }

    public async Task<ExtractInfo> ExtractAsync(string input, string requester = "desktop")
    {
        var (code, stdout, stderr) = await RunAsync("extract", "--in", input, "--requester", requester)
            .ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(stdout))
        {
            throw new BackendException(Friendly(stderr, "检测失败"));
        }
        using var doc = JsonDocument.Parse(stdout);
        var root = doc.RootElement;
        bool ReadBool(string name) =>
            root.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.True;
        string ReadStr(string name) =>
            root.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? "" : "";
        double ReadDouble(string name) =>
            root.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : 0;
        int ReadInt(string name) =>
            root.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetInt32() : 0;

        return new ExtractInfo
        {
            Found = ReadBool("found"),
            TraceId = ReadStr("trace_id"),
            ResourceCode = ReadStr("resource_code"),
            CustomText = ReadStr("custom_text") is { Length: > 0 } ct2 ? ct2 : null,
            UserIndex = ReadInt("user_index"),
            EmbeddedAt = ReadStr("embedded_at"),
            Confidence = ReadDouble("confidence"),
            CorrectedBytes = ReadInt("corrected_bytes"),
            Ber = ReadDouble("ber"),
            Registered = ReadBool("registered"),
            ElapsedMs = ReadDouble("elapsed_ms"),
        };
    }

    public async Task<(int Count, int Ok, List<BatchItem> Items)> BatchAsync(string inputDir, string outputDir, string resource)
    {
        var (code, stdout, stderr) = await RunAsync("batch", "--in", inputDir, "--out", outputDir,
            "--resource", resource ?? "").ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(stdout))
        {
            throw new BackendException(Friendly(stderr, "批量处理失败"));
        }
        using var doc = JsonDocument.Parse(stdout);
        var root = doc.RootElement;
        var items = new List<BatchItem>();
        if (root.TryGetProperty("results", out var results) && results.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in results.EnumerateArray())
            {
                string Str(string n) => item.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.String
                    ? v.GetString() ?? "" : "";
                double Num(string n) => item.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.Number
                    ? v.GetDouble() : 0;
                items.Add(new BatchItem
                {
                    Src = Str("src"),
                    Dst = Str("dst"),
                    Ok = item.TryGetProperty("ok", out var ok) && ok.ValueKind == JsonValueKind.True,
                    TraceId = Str("trace_id"),
                    Error = Str("error"),
                    Psnr = Num("psnr"),
                });
            }
        }
        return (root.TryGetProperty("count", out var c) ? c.GetInt32() : items.Count,
                root.TryGetProperty("ok", out var o) ? o.GetInt32() : 0,
                items);
    }

    public async Task<(bool Ok, string Raw)> VerifyChainAsync()
    {
        var (code, stdout, stderr) = await RunAsync("verify").ConfigureAwait(false);
        return (code == 0 && !string.IsNullOrWhiteSpace(stdout), string.IsNullOrWhiteSpace(stdout) ? stderr : stdout);
    }

    public async Task<string> EvidenceAsync(string traceId, string output)
    {
        var (code, stdout, stderr) = await RunAsync("evidence", traceId, "--out", output).ConfigureAwait(false);
        if (code != 0)
        {
            throw new BackendException(Friendly(stderr, "证据包生成失败"));
        }
        return output;
    }

    private static string Friendly(string stderr, string fallback)
    {
        if (string.IsNullOrWhiteSpace(stderr))
        {
            return fallback;
        }
        var text = stderr.Trim();
        return text.Length > 400 ? text[..400] : text;
    }
}

public sealed class BackendException : Exception
{
    public BackendException(string message) : base(message)
    {
    }
}


