using System;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using InvisMark.Desktop.Services;
using Microsoft.Win32;

namespace InvisMark.Desktop.Pages;

public partial class EmbedPage : UserControl
{
    private string? _inputPath;
    private string? _outputPath;
    private string? _traceId;

    public EmbedPage()
    {
        InitializeComponent();
    }

    private void OnPickClick(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "选择要嵌入水印的图片",
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
        EmbedButton.IsEnabled = true;
        ErrorText.Visibility = Visibility.Collapsed;
        ResultCard.Visibility = Visibility.Collapsed;
        BeforeImage.Source = LoadBitmap(path);
    }

    private static BitmapImage LoadBitmap(string path)
    {
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.UriSource = new Uri(path);
        image.EndInit();
        image.Freeze();
        return image;
    }

    private async void OnEmbedClick(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_inputPath))
        {
            return;
        }
        EmbedButton.IsEnabled = false;
        Busy.Visibility = Visibility.Visible;
        ErrorText.Visibility = Visibility.Collapsed;
        StatusText.Text = "正在嵌入，请稍候…";
        try
        {
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "InvisMark");
            Directory.CreateDirectory(dir);
            _outputPath = Path.Combine(dir, $"{Path.GetFileNameWithoutExtension(_inputPath)}.wm.png");

            var info = await MainWindow.Host.Backend.EmbedAsync(_inputPath, _outputPath, ResourceBox.Text.Trim());
            _traceId = info.TraceId;

            PsnrText.Text = $"{info.Psnr:F2} dB";
            SsimText.Text = $"{info.Ssim:F4}";
            TraceText.Text = info.TraceId;
            AfterImage.Source = LoadBitmap(_outputPath);
            ResultCard.Visibility = Visibility.Visible;
            SavedText.Text = $"已保存：{_outputPath}";
            StatusText.Text = $"完成，用时 {info.ElapsedMs:F0} ms";
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
            EmbedButton.IsEnabled = true;
        }
    }

    private void OnCopyClick(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_traceId))
        {
            return;
        }
        try
        {
            Clipboard.SetText(_traceId);
            SavedText.Text = "trace_id 已复制";
        }
        catch
        {
            SavedText.Text = "复制失败，请手动选择文本";
        }
    }

    private void OnOpenFolderClick(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_outputPath))
        {
            return;
        }
        Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{_outputPath}\"") { UseShellExecute = true });
    }
}

