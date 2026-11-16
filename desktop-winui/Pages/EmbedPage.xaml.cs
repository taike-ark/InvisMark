using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using InvisMark.Desktop.Services;

namespace InvisMark.Desktop.Pages;

public sealed partial class EmbedPage : Page
{
    private string? _inputPath;
    private string? _outputPath;
    private string? _traceId;

    public EmbedPage()
    {
        InitializeComponent();
    }

    private async void OnPickClick(object sender, RoutedEventArgs e)
    {
        var file = await Pickers.PickImageAsync();
        if (file is not null)
        {
            await LoadInputAsync(file.Path);
        }
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
        if (items.Count > 0 && items[0] is StorageFile file)
        {
            await LoadInputAsync(file.Path);
        }
    }

    private async Task LoadInputAsync(string path)
    {
        _inputPath = path;
        FileText.Text = path;
        EmbedButton.IsEnabled = true;
        ErrorBar.IsOpen = false;
        BeforeImage.Source = new BitmapImage(new Uri(path));
        ResultCard.Visibility = Visibility.Collapsed;
    }

    private async void OnEmbedClick(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_inputPath))
        {
            return;
        }
        EmbedButton.IsEnabled = false;
        PickButton.IsEnabled = false;
        Busy.IsActive = true;
        ErrorBar.IsOpen = false;
        StatusText.Text = "正在嵌入，请稍候…";
        try
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "InvisMark");
            Directory.CreateDirectory(dir);
            var stem = Path.GetFileNameWithoutExtension(_inputPath);
            _outputPath = Path.Combine(dir, $"{stem}.wm.png");

            var info = await MainWindow.Host.Backend.EmbedAsync(_inputPath, _outputPath, ResourceBox.Text.Trim(), CustomTextBox.Text.Trim());
            _traceId = info.TraceId;

            PsnrText.Text = $"{info.Psnr:F2} dB";
            SsimText.Text = $"{info.Ssim:F4}";
            TraceText.Text = info.TraceId;
            AfterImage.Source = new BitmapImage(new Uri(_outputPath));
            ResultCard.Visibility = Visibility.Visible;
            SavedText.Text = info.CustomText is { Length: > 0 } ct ? $"自定义内容：{ct} ｜ 已保存：{_outputPath}" : $"已保存：{_outputPath}";
            StatusText.Text = $"完成，用时 {info.ElapsedMs:F0} ms";
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
            EmbedButton.IsEnabled = true;
            PickButton.IsEnabled = true;
        }
    }

    private void OnCopyClick(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_traceId))
        {
            return;
        }
        var package = new DataPackage();
        package.SetText(_traceId);
        Clipboard.SetContent(package);
        SavedText.Text = "trace_id 已复制";
    }

    private void OnOpenFolderClick(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_outputPath))
        {
            return;
        }
        var folder = Path.GetDirectoryName(_outputPath);
        if (folder is null)
        {
            return;
        }
        Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{_outputPath}\"") { UseShellExecute = true });
    }
}

