using System;
using System.Diagnostics;
using System.IO;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace InvisMark.Desktop.Pages;

public sealed partial class HomePage : Page
{
    public HomePage()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private static string DataDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "InvisMark");

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        var backend = MainWindow.Host.Backend;
        BackendState.Text = backend.Available ? $"就绪（{Path.GetFileName(backend.CliPath)}）" : "未找到 InvisMarkCLI.exe";
        DataPath.Text = DataDir;
        try
        {
            Directory.CreateDirectory(DataDir);
        }
        catch
        {
            // 目录建不出来时留在界面上提示即可
        }
    }

    private void OnEmbedClick(object sender, RoutedEventArgs e) => Frame.Navigate(typeof(EmbedPage));

    private void OnDetectClick(object sender, RoutedEventArgs e) => Frame.Navigate(typeof(DetectPage));

    private async void OnVerifyClick(object sender, RoutedEventArgs e)
    {
        VerifyText.Text = "正在校验…";
        var (ok, raw) = await MainWindow.Host.Backend.VerifyChainAsync();
        VerifyText.Text = ok ? "审计链完好 ✅" : "审计链校验失败 ❌";
        if (!ok && !string.IsNullOrWhiteSpace(raw))
        {
            var dialog = new ContentDialog
            {
                Title = "审计链校验失败",
                Content = raw,
                CloseButtonText = "关闭",
                XamlRoot = XamlRoot,
            };
            await dialog.ShowAsync();
        }
    }

    private void OnOpenDataClick(object sender, RoutedEventArgs e)
    {
        try
        {
            Directory.CreateDirectory(DataDir);
            Process.Start(new ProcessStartInfo("explorer.exe", DataDir) { UseShellExecute = true });
        }
        catch
        {
            // 打开资源管理器失败不阻塞主流程
        }
    }
}
