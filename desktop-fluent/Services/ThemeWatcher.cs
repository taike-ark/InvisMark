using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace InvisMark.Desktop.Services;

/// <summary>跟随系统深浅色 + Win11 圆角，让窗口看起来像系统原生应用。</summary>
public static class ThemeWatcher
{
    private const int DwmwaWindowCornerPreference = 33;
    private const int DwmwaUseImmersiveDarkMode = 20;

    public static bool IsDark { get; private set; }

    public static void Apply(Window window)
    {
        IsDark = ReadSystemUsesDarkTheme();
        if (IsDark)
        {
            SetBrush("AppBackgroundBrush", "#202020");
            SetBrush("CardBackgroundBrush", "#2B2B2B");
            SetBrush("CardStrokeBrush", "#3A3A3A");
            SetBrush("TextPrimaryBrush", "#FFFFFF");
            SetBrush("TextSecondaryBrush", "#C5C5C5");
            SetBrush("SubtleFillBrush", "#2F2F2F");
            SetBrush("SubtleHoverBrush", "#3A3A3A");
            SetBrush("NavSelectedBrush", "#3D3D3D");
            SetBrush("DividerBrush", "#3A3A3A");
            SetBrush("AccentBrush", "#4CC2FF");
            SetBrush("AccentHoverBrush", "#6AD0FF");
            SetBrush("AccentPressedBrush", "#3AA9E0");
        }
        ApplyRoundedCorners(window, IsDark);
    }

    private static void SetBrush(string key, string hex)
    {
        if (Application.Current.Resources[key] is SolidColorBrush)
        {
            Application.Current.Resources[key] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
        }
    }

    private static bool ReadSystemUsesDarkTheme()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            var value = key?.GetValue("AppsUseLightTheme");
            return value is int i && i == 0;
        }
        catch
        {
            return false;
        }
    }

    private static void ApplyRoundedCorners(Window window, bool dark)
    {
        try
        {
            var hwnd = new System.Windows.Interop.WindowInteropHelper(window).Handle;
            if (hwnd == IntPtr.Zero)
            {
                return;
            }
            var corner = 2; // DWMWCP_ROUND
            DwmSetWindowAttribute(hwnd, DwmwaWindowCornerPreference, ref corner, sizeof(int));
            var mode = dark ? 1 : 0;
            DwmSetWindowAttribute(hwnd, DwmwaUseImmersiveDarkMode, ref mode, sizeof(int));
        }
        catch
        {
            // 老系统不支持 DWM 属性时保持直角
        }
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
}
