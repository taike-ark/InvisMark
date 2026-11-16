using System;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Windows.Storage;
using Windows.Storage.Pickers;

namespace InvisMark.Desktop.Services;

/// <summary>WinUI 3 非打包应用的选文件封装（必须先和窗口 HWND 关联）</summary>
public static class Pickers
{
    private static Window? _window;

    public static void Initialize(Window window) => _window = window;

    private static void Bind(object picker)
    {
        if (_window is null)
        {
            return;
        }
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(_window);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);
    }

    public static async Task<StorageFile?> PickImageAsync()
    {
        var picker = new FileOpenPicker
        {
            SuggestedStartLocation = PickerLocationId.PicturesLibrary,
            ViewMode = PickerViewMode.Thumbnail,
        };
        foreach (var ext in new[] { ".png", ".jpg", ".jpeg", ".bmp", ".webp", ".tif", ".tiff" })
        {
            picker.FileTypeFilter.Add(ext);
        }
        Bind(picker);
        return await picker.PickSingleFileAsync();
    }

    public static async Task<StorageFolder?> PickFolderAsync(string? title = null)
    {
        var picker = new FolderPicker
        {
            SuggestedStartLocation = PickerLocationId.PicturesLibrary,
        };
        picker.FileTypeFilter.Add("*");
        Bind(picker);
        return await picker.PickSingleFolderAsync();
    }

    public static async Task<StorageFile?> SaveFileAsync(string suggestedName, string typeLabel, params string[] extensions)
    {
        var picker = new FileSavePicker
        {
            SuggestedStartLocation = PickerLocationId.PicturesLibrary,
            SuggestedFileName = suggestedName,
        };
        picker.FileTypeChoices.Add(typeLabel, new System.Collections.Generic.List<string>(extensions));
        Bind(picker);
        return await picker.PickSaveFileAsync();
    }
}
