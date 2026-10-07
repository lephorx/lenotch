using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Lenotch.Core;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;

namespace Lenotch.Services;

/// Files dropped on the notch. Holds references to the originals, not copies.
public sealed class ShelfStore
{
    private readonly AppSettings settings;
    private readonly Dictionary<string, ImageSource> icons = new(StringComparer.OrdinalIgnoreCase);

    public event Action? Changed;
    public List<string> Items { get; } = new();

    public ShelfStore(AppSettings settings)
    {
        this.settings = settings;
        if (settings.KeepShelfItems)
            Items.AddRange(settings.ShelfItems.Where(p => File.Exists(p) || Directory.Exists(p)));
        settings.Changed += name =>
        {
            if (name == nameof(AppSettings.KeepShelfItems)) Persist();
        };
    }

    public void Add(IEnumerable<string> paths)
    {
        var added = false;
        foreach (var path in paths)
        {
            if (Items.Contains(path, StringComparer.OrdinalIgnoreCase)) continue;
            Items.Add(path);
            added = true;
        }
        if (!added) return;
        Persist();
        Changed?.Invoke();
    }

    public void Remove(string path)
    {
        Items.RemoveAll(p => string.Equals(p, path, StringComparison.OrdinalIgnoreCase));
        icons.Remove(path);
        Persist();
        Changed?.Invoke();
    }

    public void RemoveAll()
    {
        Items.Clear();
        icons.Clear();
        Persist();
        Changed?.Invoke();
    }

    private void Persist()
    {
        settings.ShelfItems = settings.KeepShelfItems ? new List<string>(Items) : new List<string>();
    }

    public ImageSource Icon(string path)
    {
        if (icons.TryGetValue(path, out var icon)) return icon;
        icon = FileIcons.Get(path, 96);
        icons[path] = icon;
        return icon;
    }

    public static void Open(string path)
    {
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
        catch (Exception) { }
    }

    public static void ShowInExplorer(string path)
    {
        try { Process.Start("explorer.exe", $"/select,\"{path}\""); }
        catch (Exception) { }
    }
}

/// Shell thumbnails and icons (what Explorer shows), with transparency kept.
public static class FileIcons
{
    [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItemImageFactory
    {
        [PreserveSig]
        int GetImage(SIZE size, int flags, out IntPtr bitmap);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SIZE { public int cx, cy; }

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAP
    {
        public int bmType, bmWidth, bmHeight, bmWidthBytes;
        public ushort bmPlanes, bmBitsPixel;
        public IntPtr bmBits;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SHCreateItemFromParsingName(string path, IntPtr bindContext, ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory factory);

    [DllImport("gdi32.dll")]
    private static extern int GetObject(IntPtr handle, int size, out BITMAP bitmap);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr handle);

    public static ImageSource Get(string path, int pixels)
    {
        try
        {
            var iid = typeof(IShellItemImageFactory).GUID;
            SHCreateItemFromParsingName(path, IntPtr.Zero, ref iid, out var factory);
            // SIIGBF_RESIZETOFIT (0) | SIIGBF_BIGGERSIZEOK (1)
            if (factory.GetImage(new SIZE { cx = pixels, cy = pixels }, 0x1, out var handle) == 0 && handle != IntPtr.Zero)
            {
                try { return FromHBitmap(handle); }
                finally { DeleteObject(handle); }
            }
        }
        catch (Exception) { }
        try
        {
            using var icon = System.Drawing.Icon.ExtractAssociatedIcon(path);
            if (icon != null)
            {
                var source = Imaging.CreateBitmapSourceFromHIcon(icon.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                source.Freeze();
                return source;
            }
        }
        catch (Exception) { }
        return new DrawingImage();
    }

    /// Copies the 32-bit DIB's premultiplied pixels (CreateBitmapSourceFromHBitmap drops the alpha).
    private static BitmapSource FromHBitmap(IntPtr handle)
    {
        GetObject(handle, Marshal.SizeOf<BITMAP>(), out var info);
        if (info.bmBits == IntPtr.Zero || info.bmBitsPixel != 32)
        {
            var fallback = Imaging.CreateBitmapSourceFromHBitmap(handle, IntPtr.Zero, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            fallback.Freeze();
            return fallback;
        }
        var stride = info.bmWidthBytes;
        var bytes = new byte[stride * info.bmHeight];
        Marshal.Copy(info.bmBits, bytes, 0, bytes.Length);
        var bitmap = BitmapSource.Create(info.bmWidth, info.bmHeight, 96, 96, PixelFormats.Pbgra32, null, bytes, stride);
        // DIBs are stored bottom-up.
        var flipped = new TransformedBitmap(bitmap, new ScaleTransform(1, -1));
        var frozen = new WriteableBitmap(flipped);
        frozen.Freeze();
        return frozen;
    }
}

/// Windows' Share sheet (Nearby Sharing, Mail, Teams, …), the Windows stand-in for AirDrop.
public static class ShareSheet
{
    [ComImport, Guid("3A3DCD6C-3EAB-43DC-BCDE-45671CE800C8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDataTransferManagerInterop
    {
        IntPtr GetForWindow([In] IntPtr appWindow, [In] ref Guid riid);
        void ShowShareUIForWindow(IntPtr appWindow);
    }

    private static readonly Guid DataTransferManagerIid = new(0xa5caee9b, 0x8708, 0x49d1, 0x8d, 0x36, 0x67, 0xd2, 0x5a, 0x8d, 0xa0, 0x0c);
    private static readonly HashSet<IntPtr> Hooked = new();
    private static List<string> pending = new();

    public static void Share(IntPtr hwnd, IReadOnlyCollection<string> paths)
    {
        if (paths.Count == 0) return;
        pending = paths.ToList();
        try
        {
            var interop = DataTransferManager.As<IDataTransferManagerInterop>();
            if (Hooked.Add(hwnd))
            {
                var iid = DataTransferManagerIid;
                var pointer = interop.GetForWindow(hwnd, ref iid);
                var manager = WinRT.MarshalInterface<DataTransferManager>.FromAbi(pointer);
                manager.DataRequested += OnDataRequested;
            }
            interop.ShowShareUIForWindow(hwnd);
        }
        catch (Exception)
        {
            // Without the share sheet, at least show the files.
            ShelfStore.ShowInExplorer(paths.First());
        }
    }

    private static async void OnDataRequested(DataTransferManager sender, DataRequestedEventArgs args)
    {
        var deferral = args.Request.GetDeferral();
        try
        {
            var items = new List<IStorageItem>();
            foreach (var path in pending)
            {
                if (Directory.Exists(path)) items.Add(await StorageFolder.GetFolderFromPathAsync(path));
                else if (File.Exists(path)) items.Add(await StorageFile.GetFileFromPathAsync(path));
            }
            args.Request.Data.Properties.Title = items.Count == 1 ? items[0].Name : $"{items.Count} items";
            args.Request.Data.SetStorageItems(items);
        }
        catch (Exception)
        {
            args.Request.FailWithDisplayText("These files can't be shared.");
        }
        finally
        {
            deferral.Complete();
        }
    }

    /// Lets the user pick files, then opens the share sheet for them.
    public static void ChooseAndShare(IntPtr hwnd)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog { Multiselect = true, Title = "Share" };
        if (dialog.ShowDialog() == true) Share(hwnd, dialog.FileNames);
    }
}
