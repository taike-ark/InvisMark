using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using InvisMark.Desktop.Pages;
using InvisMark.Desktop.Services;

namespace InvisMark.Desktop;

public partial class MainWindow : Window
{
    public static BackendHost Host { get; } = new();

    private HomePage? _home;
    private EmbedPage? _embed;
    private DetectPage? _detect;
    private BatchPage? _batch;
    private SettingsPage? _settings;

    private bool _ready;

    public MainWindow()
    {
        InitializeComponent();
        ThemeWatcher.Apply(this);
        _ready = true;
        NavHome.IsChecked = true;
        ShowPage(NavHome);
    }

    private void Nav_Checked(object sender, RoutedEventArgs e)
    {
        if (!_ready || PageHost is null)
        {
            return;
        }
        if (sender is RadioButton button)
        {
            ShowPage(button);
        }
    }

    private void ShowPage(RadioButton button)
    {
        UserControl? page = button.Name switch
        {
            "NavEmbed" => _embed ??= new EmbedPage(),
            "NavDetect" => _detect ??= new DetectPage(),
            "NavBatch" => _batch ??= new BatchPage(),
            "NavSettings" => _settings ??= new SettingsPage(),
            _ => _home ??= new HomePage(),
        };
        PageHost.Content = page;
    }

    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2)
        {
            ToggleMaximize();
            return;
        }
        DragMove();
    }

    private void Minimize_Click(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    private void Maximize_Click(object sender, RoutedEventArgs e) => ToggleMaximize();

    private void ToggleMaximize() =>
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}

/// <summary>全局共享的后端实例（调用随包的 InvisMarkCLI.exe）</summary>
public sealed class BackendHost
{
    public Backend Backend { get; } = new();
}


