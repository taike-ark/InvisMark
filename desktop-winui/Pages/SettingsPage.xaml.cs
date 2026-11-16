using System;
using System.Diagnostics;
using System.IO;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace InvisMark.Desktop.Pages;

public sealed partial class SettingsPage : Page
{
    private static string DataDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "InvisMark");

    public SettingsPage()
    {
        InitializeComponent();
        DataText.Text = DataDir;
        var backend = MainWindow.Host.Backend;
        BackendText.Text = backend.Available
            ? $"后端：{backend.CliPath}"
            : "后端：未找到 InvisMarkCLI.exe";
        try
        {
            Directory.CreateDirectory(DataDir);
        }
        catch
        {
            // 目录不可写时界面仍可查看
        }
    }

    private void OnOpenClick(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo("explorer.exe", DataDir) { UseShellExecute = true });
        }
        catch
        {
            // 忽略资源管理器启动失败
        }
    }

    private async void OnVerifyClick(object sender, RoutedEventArgs e)
    {
        VerifyText.Text = "正在校验…";
        var (ok, raw) = await MainWindow.Host.Backend.VerifyChainAsync();
        VerifyText.Text = ok ? "审计链完好 ✅" : "校验失败 ❌";
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
}
