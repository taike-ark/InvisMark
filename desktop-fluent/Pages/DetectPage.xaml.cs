using System;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;

namespace InvisMark.Desktop.Pages;

public partial class DetectPage : UserControl
{
    private string? _inputPath;
    private string? _traceId;
    private bool _found;

    public DetectPage()
    {
        InitializeComponent();
    }

    private void OnPickClick(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "选择要检测的图片",
            Filter = "图片|*.png;*.jpg;*.jpeg;*.bmp;*.webp;*.tif;*.tiff|所有文件|*.*",
        };
        if (dialog.ShowDialog() == true)
        {
            LoadInput(dialog.FileName);
        }
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private void OnDrop(object sender, DragEventArgs e)
    {
        if (e.Data.GetData(DataFormats.FileDrop) is string[] { Length: > 0 } files && File.Exists(files[0]))
        {
            LoadInput(files[0]);
        }
    }

    private void LoadInput(string path)
    {
        _inputPath = path;
        FileText.Text = path;
        DetectButton.IsEnabled = true;
        ErrorText.Visibility = Visibility.Collapsed;
        ResultCard.Visibility = Visibility.Collapsed;
    }

    private async void OnDetectClick(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_inputPath))
        {
            return;
        }
        DetectButton.IsEnabled = false;
        Busy.Visibility = Visibility.Visible;
        ErrorText.Visibility = Visibility.Collapsed;
        StatusText.Text = "正在检测…";
        try
        {
            var info = await MainWindow.Host.Backend.ExtractAsync(_inputPath);
            _found = info.Found;
            _traceId = info.TraceId;
            ResultCard.Visibility = Visibility.Visible;

            if (info.Found)
            {
                ResultIcon.Text = "\uE73E";
                ResultIcon.Foreground = (Brush)FindResource("SuccessBrush");
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
                ResultIcon.Text = "\uE711";
                ResultIcon.Foreground = (Brush)FindResource("DangerBrush");
                ResultTitle.Text = "未检出有效追溯码";
                TraceText.Text = "—";
                ResourceText.Text = "—";
                TimeText.Text = "—";
                ConfidenceText.Text = "—";
                StatsText.Text = $"— / {info.ElapsedMs:F0} ms";
                EvidenceButton.IsEnabled = false;
                HintText.Text = "可能从未嵌入，或被强压缩、裁剪破坏";
            }
            StatusText.Text = "";
        }
        catch (Exception ex)
        {
            ErrorText.Text = ex.Message;
            ErrorText.Visibility = Visibility.Visible;
            StatusText.Text = "";
        }
        finally
        {
            Busy.Visibility = Visibility.Collapsed;
            DetectButton.IsEnabled = true;
        }
    }

    private async void OnEvidenceClick(object sender, RoutedEventArgs e)
    {
        if (!_found || string.IsNullOrEmpty(_traceId))
        {
            return;
        }
        var dialog = new SaveFileDialog
        {
            Title = "保存证据包",
            FileName = $"evidence-{_traceId[..8]}",
            DefaultExt = ".zip",
            Filter = "ZIP 证据包|*.zip",
        };
        if (dialog.ShowDialog() != true)
        {
            return;
        }
        try
        {
            Busy.Visibility = Visibility.Visible;
            HintText.Text = "正在生成证据包…";
            await MainWindow.Host.Backend.EvidenceAsync(_traceId, dialog.FileName);
            HintText.Text = "证据包已保存";
            Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{dialog.FileName}\"") { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            ErrorText.Text = ex.Message;
            ErrorText.Visibility = Visibility.Visible;
            HintText.Text = "";
        }
        finally
        {
            Busy.Visibility = Visibility.Collapsed;
        }
    }

    private void OnCopyClick(object sender, RoutedEventArgs e)
    {
        if (!_found || string.IsNullOrEmpty(_traceId))
        {
            return;
        }
        try
        {
            Clipboard.SetText(_traceId);
            HintText.Text = "trace_id 已复制";
        }
        catch
        {
            HintText.Text = "复制失败，请手动选择文本";
        }
    }
}

