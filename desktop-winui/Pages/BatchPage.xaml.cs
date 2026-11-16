using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage;
using InvisMark.Desktop.Services;

namespace InvisMark.Desktop.Pages;

public sealed partial class BatchPage : Page
{
    private string? _inputDir;
    private string? _outputDir;

    public BatchPage()
    {
        InitializeComponent();
    }

    private async void OnPickInputClick(object sender, RoutedEventArgs e)
    {
        var folder = await Pickers.PickFolderAsync("选择要批量嵌入的图片目录");
        if (folder is null)
        {
            return;
        }
        _inputDir = folder.Path;
        OutputText();
    }

    private void OutputText() => InputText.Text = _inputDir ?? "未选择";

    private async void OnPickOutputClick(object sender, RoutedEventArgs e)
    {
        var folder = await Pickers.PickFolderAsync("选择输出目录");
        if (folder is null)
        {
            return;
        }
        _outputDir = folder.Path;
        OutputText();
        RunButton.IsEnabled = _inputDir is not null;
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
        Busy.IsActive = true;
        ErrorBar.IsOpen = false;
        StatusText.Text = "正在批量处理，图片多时需要几分钟…";
        ResultList.Items.Clear();
        ListCard.Visibility = Visibility.Collapsed;
        try
        {
            var (count, ok, items) = await MainWindow.Host.Backend.BatchAsync(_inputDir, output, ResourceBox.Text.Trim());
            SummaryText.Text = $"处理完成：成功 {ok} / {count}，输出目录 {output}";
            foreach (var item in items)
            {
                ResultList.Items.Add(new TextBlock
                {
                    Text = item.Ok
                        ? $"{item.Src} → {item.Dst}  PSNR {item.Psnr:F1} dB"
                        : $"{item.Src} 失败：{item.Error}",
                    TextWrapping = TextWrapping.Wrap,
                });
            }
            ListCard.Visibility = Visibility.Visible;
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
            RunButton.IsEnabled = true;
        }
    }
}
