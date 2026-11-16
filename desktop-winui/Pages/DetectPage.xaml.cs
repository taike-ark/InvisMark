using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using InvisMark.Desktop.Services;

namespace InvisMark.Desktop.Pages;

public sealed partial class DetectPage : Page
{
    private string? _inputPath;
    private string? _traceId;
    private bool _found;

    public DetectPage()
    {
        InitializeComponent();
    }

    private async void OnPickClick(object sender, RoutedEventArgs e)
    {
        var file = await Pickers.PickImageAsync();
        if (file is null)
        {
            return;
        }
        _inputPath = file.Path;
        FileText.Text = _inputPath;
        DetectButton.IsEnabled = true;
        ErrorBar.IsOpen = false;
        ResultCard.Visibility = Visibility.Collapsed;
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        e.AcceptedOperation = DataPackageOperation.Copy;
    }

    private async void OnDrop(object sender, DragEventArgs e)
    {
        if (!e.DataView.Contains(StandardDataFormats.StorageItems))
        {
            return;
        }
        var items = await e.DataView.GetStorageItemsAsync();
        if (items.Count > 0 && items[0] is StorageFile file && File.Exists(file.Path))
        {
            _inputPath = file.Path;
            FileText.Text = _inputPath;
            DetectButton.IsEnabled = true;
            ResultCard.Visibility = Visibility.Collapsed;
        }
    }

    private async void OnDetectClick(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_inputPath))
        {
            return;
        }
        DetectButton.IsEnabled = false;
        PickButton.IsEnabled = false;
        Busy.IsActive = true;
        ErrorBar.IsOpen = false;
        StatusText.Text = "正在检测…";
        try
        {
            var info = await MainWindow.Host.Backend.ExtractAsync(_inputPath);
            _found = info.Found;
            _traceId = info.TraceId;

            ResultCard.Visibility = Visibility.Visible;
            if (info.Found)
            {
                ResultIcon.Glyph = "\uE73E";
                ResultIcon.Foreground = new SolidColorBrush(Colors.SeaGreen);
                ResultTitle.Text = "命中 · 可追溯";
                TraceText.Text = info.TraceId;
                ResourceText.Text = info.ResourceCode;
                TimeText.Text = info.EmbeddedAt.Replace("T", " ").Replace("+00:00", " UTC");
                ConfidenceText.Text = $"{info.Confidence * 100:F1}%";
                StatsText.Text = $"{info.CorrectedBytes} 字节 / {info.ElapsedMs:F0} ms";
                EvidenceButton.IsEnabled = true;
                HintText.Text = "";
            }
            else
            {
                ResultIcon.Glyph = "\uE711";
                ResultIcon.Foreground = new SolidColorBrush(Colors.OrangeRed);
                ResultTitle.Text = "未检出有效追溯码";
                TraceText.Text = "—";
                ResourceText.Text = "—";
                TimeText.Text = "—";
                ConfidenceText.Text = "—";
                StatsText.Text = $"— / {info.ElapsedMs:F0} ms";
                EvidenceButton.IsEnabled = false;
                HintText.Text = "可能从未嵌入，或被强压缩/裁剪破坏";
            }
            StatusText.Text = "";
        }
        catch (Exception ex)
        {
            ErrorBar.Message = ex.Message;
            ErrorBar.IsOpen = true;
            StatusText.Text = "";
        }
        finally
        {
            Busy.IsActive = false;
            DetectButton.IsEnabled = true;
            PickButton.IsEnabled = true;
        }
    }

    private async void OnEvidenceClick(object sender, RoutedEventArgs e)
    {
        if (!_found || string.IsNullOrEmpty(_traceId))
        {
            return;
        }
        var file = await Pickers.SaveFileAsync($"evidence-{_traceId[..8]}", "ZIP 证据包", ".zip");
        if (file is null)
        {
            return;
        }
        try
        {
            Busy.IsActive = true;
            HintText.Text = "正在生成证据包…";
            await MainWindow.Host.Backend.EvidenceAsync(_traceId, file.Path);
            HintText.Text = "证据包已保存";
            Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{file.Path}\"") { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            ErrorBar.Message = ex.Message;
            ErrorBar.IsOpen = true;
            HintText.Text = "";
        }
        finally
        {
            Busy.IsActive = false;
        }
    }

    private void OnCopyClick(object sender, RoutedEventArgs e)
    {
        if (!_found || string.IsNullOrEmpty(_traceId))
        {
            return;
        }
        var package = new DataPackage();
        package.SetText(_traceId);
        Clipboard.SetContent(package);
        HintText.Text = "trace_id 已复制";
    }
}
