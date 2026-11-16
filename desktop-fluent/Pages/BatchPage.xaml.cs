using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;

namespace InvisMark.Desktop.Pages;

public partial class BatchPage : UserControl
{
    private string? _inputDir;
    private string? _outputDir;

    public BatchPage()
    {
        InitializeComponent();
    }

    private void OnPickInputClick(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "选择要批量嵌入的图片目录" };
        if (dialog.ShowDialog() != true)
        {
            return;
        }
        _inputDir = dialog.FolderName;
        InputText.Text = _inputDir;
        RunButton.IsEnabled = true;
    }

    private void OnPickOutputClick(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "选择输出目录" };
        if (dialog.ShowDialog() != true)
        {
            return;
        }
        _outputDir = dialog.FolderName;
        OutputText.Text = _outputDir;
    }

    private async void OnRunClick(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_inputDir))
        {
            return;
        }
        var output = _outputDir ?? Path.Combine(Path.GetDirectoryName(_inputDir)!, "invisMark-out");
        Directory.CreateDirectory(output);

        RunButton.IsEnabled = false;
        Busy.Visibility = Visibility.Visible;
        ErrorText.Visibility = Visibility.Collapsed;
        StatusText.Text = "正在批量处理，图片多时需要几分钟…";
        ResultList.Items.Clear();
        ListCard.Visibility = Visibility.Collapsed;
        try
        {
            var (count, ok, items) = await MainWindow.Host.Backend.BatchAsync(_inputDir, output, ResourceBox.Text.Trim());
            SummaryText.Text = $"处理完成：成功 {ok} / {count}，输出目录 {output}";
            foreach (var item in items)
            {
                ResultList.Items.Add(item.Ok
                    ? $"{item.Src} → {item.Dst}  PSNR {item.Psnr:F1} dB"
                    : $"{item.Src} 失败：{item.Error}");
            }
            ListCard.Visibility = Visibility.Visible;
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
            RunButton.IsEnabled = true;
        }
    }
}
