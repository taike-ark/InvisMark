using System;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;

namespace InvisMark.Desktop.Pages;

public partial class HomePage : UserControl
{
    private static string DataDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "InvisMark");

    public HomePage()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
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
            // 目录不可写时保留界面提示即可
        }
    }

    private void OnEmbedClick(object sender, RoutedEventArgs e)
    {
        if (Application.Current.MainWindow is MainWindow window)
        {
            window.NavEmbed.IsChecked = true;
        }
    }

    private void OnDetectClick(object sender, RoutedEventArgs e)
    {
        if (Application.Current.MainWindow is MainWindow window)
        {
            window.NavDetect.IsChecked = true;
        }
    }

    private async void OnVerifyClick(object sender, RoutedEventArgs e)
    {
        VerifyText.Text = "正在校验…";
        var (ok, raw) = await MainWindow.Host.Backend.VerifyChainAsync();
        VerifyText.Text = ok ? "审计链完好 ✅" : "校验失败 ❌";
        if (!ok && !string.IsNullOrWhiteSpace(raw))
        {
            MessageBox.Show(raw, "审计链校验失败", MessageBoxButton.OK, MessageBoxImage.Warning);
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
            // 忽略资源管理器启动失败
        }
    }
}
