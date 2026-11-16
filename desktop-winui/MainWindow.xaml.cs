using System;
using Microsoft.UI;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using InvisMark.Desktop.Pages;
using Windows.Graphics;

namespace InvisMark.Desktop;

public sealed partial class MainWindow : Window
{
    public static BackendHost Host { get; } = new();

    public MainWindow()
    {
        InitializeComponent();
        Title = "隐迹 InvisMark";
        Services.Pickers.Initialize(this);
        TrySetBackdrop();
        SetWindowSize(1180, 780);
        Nav.SelectedItem = NavHome;
        ContentFrame.Navigate(typeof(HomePage));
    }

    private void TrySetBackdrop()
    {
        try
        {
            if (MicaController.IsSupported())
            {
                SystemBackdrop = new MicaBackdrop { Kind = MicaKind.BaseAlt };
            }
            else if (DesktopAcrylicController.IsSupported())
            {
                SystemBackdrop = new DesktopAcrylicBackdrop();
            }
        }
        catch
        {
            // 老系统/远程桌面下直接退化成普通背景，不影响功能
        }
    }

    private void SetWindowSize(int width, int height)
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var id = Win32Interop.GetWindowIdFromWindow(hwnd);
        var appWindow = AppWindow.GetFromWindowId(id);
        // AppWindow.Resize 用的是物理像素，高 DPI 下要按比例放大，否则窗口会被压小
        var dpi = GetDpiForWindow(hwnd);
        var scale = dpi <= 0 ? 1.0 : dpi / 96.0;
        appWindow.Resize(new SizeInt32((int)(width * scale), (int)(height * scale)));
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hwnd);

    private void Nav_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        var tag = (args.SelectedItemContainer as NavigationViewItem)?.Tag as string;
        Type? page = tag switch
        {
            "embed" => typeof(EmbedPage),
            "detect" => typeof(DetectPage),
            "batch" => typeof(BatchPage),
            _ => typeof(HomePage),
        };
        if (tag == "settings")
        {
            page = typeof(SettingsPage);
        }
        if (page is not null && ContentFrame.CurrentSourcePageType != page)
        {
            ContentFrame.Navigate(page);
        }
    }
}

/// <summary>全局共享的后端实例（CLI 进程调用）</summary>
public sealed class BackendHost
{
    public Services.Backend Backend { get; } = new();
}

