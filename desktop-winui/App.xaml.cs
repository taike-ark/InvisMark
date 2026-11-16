using System;
using System.IO;
using Microsoft.UI.Xaml;

namespace InvisMark.Desktop;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        InitializeComponent();
        UnhandledException += (_, e) => Log("UnhandledException: " + e.Exception);
    }

    private static void Log(string text)
    {
        try
        {
            File.WriteAllText(Path.Combine(AppContext.BaseDirectory, "crash.log"), text);
        }
        catch
        {
            // 写不进日志也不阻塞启动
        }
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            _window = new MainWindow();
            _window.Activate();
        }
        catch (Exception ex)
        {
            Log("OnLaunched: " + ex);
            throw;
        }
    }
}
