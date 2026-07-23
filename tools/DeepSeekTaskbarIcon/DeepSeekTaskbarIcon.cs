using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

internal static class DeepSeekTaskbarIcon
{
    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    private const uint WM_GETICON = 0x007F;
    private const uint WM_SETICON = 0x0080;
    private const uint WM_SETTEXT = 0x000C;
    private const uint ICON_SMALL = 0;
    private const uint ICON_BIG = 1;
    private const uint IMAGE_ICON = 1;
    private const uint LR_LOADFROMFILE = 0x0010;
    private const uint SMTO_ABORTIFHUNG = 0x0002;
    private const int SM_CXICON = 11;
    private const int SM_CYICON = 12;
    private const int SM_CXSMICON = 49;
    private const int SM_CYSMICON = 50;
    private const ushort VT_EMPTY = 0;
    private const ushort VT_LPWSTR = 31;
    private const uint GW_OWNER = 4;

    private static readonly Guid PropertyStoreGuid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
    private static readonly PropertyKey RelaunchIconKey = new PropertyKey(
        new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), 3);

    private static readonly Dictionary<IntPtr, TrackedWindow> TrackedWindows =
        new Dictionary<IntPtr, TrackedWindow>();

    private static string _installRoot;
    private static string _iconResource;
    private static string _stopFile;
    private static string _windowTitle;
    private static IntPtr _largeIcon;
    private static IntPtr _smallIcon;
    private static bool _stopRequested;

    private sealed class TrackedWindow
    {
        public IntPtr Handle;
        public uint ProcessId;
        public IntPtr OriginalLargeIcon;
        public IntPtr OriginalSmallIcon;
        public string OriginalWindowTitle;
        public bool PropertyCaptured;
        public bool OriginalPropertyWasEmpty;
        public string OriginalRelaunchIcon;
    }

    private sealed class Options
    {
        public string IconPath;
        public string InstallRoot;
        public string StopFile;
        public string WindowTitle = "DeepSeek";
        public int IntervalMilliseconds = 1200;
        public bool ValidateOnly;
    }

    private delegate bool EnumWindowsCallback(IntPtr window, IntPtr state);

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    private struct PropertyKey
    {
        public Guid FormatId;
        public uint PropertyId;

        public PropertyKey(Guid formatId, uint propertyId)
        {
            FormatId = formatId;
            PropertyId = propertyId;
        }
    }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    private struct PropVariant
    {
        [FieldOffset(0)] public ushort VariantType;
        [FieldOffset(8)] public IntPtr PointerValue;
    }

    [ComImport]
    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPropertyStore
    {
        [PreserveSig] int GetCount(out uint propertyCount);
        [PreserveSig] int GetAt(uint propertyIndex, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
        [PreserveSig] int Commit();
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr state);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(IntPtr window);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr window);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr window, uint command);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextLength(IntPtr window);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr window, StringBuilder text, int maximumCount);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadImage(
        IntPtr instance,
        string name,
        uint type,
        int desiredWidth,
        int desiredHeight,
        uint flags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr icon);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int index);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SendMessageTimeout(
        IntPtr window,
        uint message,
        UIntPtr wParam,
        IntPtr lParam,
        uint flags,
        uint timeoutMilliseconds,
        out IntPtr result);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr SendMessageTimeout(
        IntPtr window,
        uint message,
        UIntPtr wParam,
        string lParam,
        uint flags,
        uint timeoutMilliseconds,
        out IntPtr result);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint access, bool inheritHandle, uint processId);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool QueryFullProcessImageName(
        IntPtr process,
        uint flags,
        StringBuilder executablePath,
        ref uint size);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("shell32.dll", SetLastError = true)]
    private static extern int SHGetPropertyStoreForWindow(
        IntPtr window,
        ref Guid interfaceId,
        [MarshalAs(UnmanagedType.Interface)] out IPropertyStore propertyStore);

    [DllImport("ole32.dll")]
    private static extern int PropVariantClear(ref PropVariant value);

    public static int Main(string[] args)
    {
        Options options;
        try
        {
            options = ParseOptions(args);
            _installRoot = NormalizeDirectory(options.InstallRoot);
            _stopFile = Path.GetFullPath(options.StopFile);
            _windowTitle = options.WindowTitle;
            string iconPath = Path.GetFullPath(options.IconPath);
            _iconResource = iconPath + ",0";

            _largeIcon = LoadImage(
                IntPtr.Zero,
                iconPath,
                IMAGE_ICON,
                GetSystemMetrics(SM_CXICON),
                GetSystemMetrics(SM_CYICON),
                LR_LOADFROMFILE);
            _smallIcon = LoadImage(
                IntPtr.Zero,
                iconPath,
                IMAGE_ICON,
                GetSystemMetrics(SM_CXSMICON),
                GetSystemMetrics(SM_CYSMICON),
                LR_LOADFROMFILE);

            if (_largeIcon == IntPtr.Zero || _smallIcon == IntPtr.Zero)
            {
                throw new InvalidOperationException("Windows could not load the configured .ico file.");
            }

            if (options.ValidateOnly)
            {
                Console.WriteLine("VALID icon={0} title={1} installRoot={2}", iconPath, _windowTitle, _installRoot);
                return 0;
            }

            TryDeleteFile(_stopFile);
            Console.CancelKeyPress += delegate(object sender, ConsoleCancelEventArgs eventArgs)
            {
                eventArgs.Cancel = true;
                _stopRequested = true;
            };

            Console.WriteLine("READY icon={0} title={1} installRoot={2}", iconPath, _windowTitle, _installRoot);
            int previousWindowCount = -1;

            while (!_stopRequested && !File.Exists(_stopFile))
            {
                int windowCount = ApplyToCurrentWindows();
                if (windowCount != previousWindowCount)
                {
                    Console.WriteLine("TARGETS count={0}", windowCount);
                    previousWindowCount = windowCount;
                }
                Thread.Sleep(options.IntervalMilliseconds);
            }

            Console.WriteLine("STOP requested; restoring original window icons.");
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("ERROR {0}", error.Message);
            return 1;
        }
        finally
        {
            RestoreAllWindows();
            TryDeleteFile(_stopFile);
            if (_largeIcon != IntPtr.Zero) DestroyIcon(_largeIcon);
            if (_smallIcon != IntPtr.Zero) DestroyIcon(_smallIcon);
        }
    }

    private static Options ParseOptions(string[] args)
    {
        Options options = new Options();
        for (int index = 0; index < args.Length; index++)
        {
            string value = args[index];
            if (value == "--validate-only") options.ValidateOnly = true;
            else if (value == "--icon") options.IconPath = NextValue(args, ref index, value);
            else if (value == "--install-root") options.InstallRoot = NextValue(args, ref index, value);
            else if (value == "--stop-file") options.StopFile = NextValue(args, ref index, value);
            else if (value == "--window-title") options.WindowTitle = NextValue(args, ref index, value);
            else if (value == "--interval-ms")
            {
                int interval;
                if (!int.TryParse(NextValue(args, ref index, value), out interval) || interval < 250 || interval > 30000)
                    throw new ArgumentException("--interval-ms must be between 250 and 30000.");
                options.IntervalMilliseconds = interval;
            }
            else throw new ArgumentException("Unknown argument: " + value);
        }

        if (String.IsNullOrWhiteSpace(options.IconPath) || !File.Exists(options.IconPath))
            throw new ArgumentException("--icon must point to an existing .ico file.");
        if (!String.Equals(Path.GetExtension(options.IconPath), ".ico", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("--icon must point to an .ico file.");
        if (String.IsNullOrWhiteSpace(options.InstallRoot) || !Directory.Exists(options.InstallRoot))
            throw new ArgumentException("--install-root must point to the installed Codex package directory.");
        if (String.IsNullOrWhiteSpace(options.StopFile))
            throw new ArgumentException("--stop-file is required.");
        if (String.IsNullOrWhiteSpace(options.WindowTitle) || options.WindowTitle.Length > 128)
            throw new ArgumentException("--window-title must contain 1 to 128 characters.");
        return options;
    }

    private static string NextValue(string[] args, ref int index, string option)
    {
        index += 1;
        if (index >= args.Length) throw new ArgumentException(option + " requires a value.");
        return args[index];
    }

    private static string NormalizeDirectory(string path)
    {
        string fullPath = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        return fullPath + Path.DirectorySeparatorChar;
    }

    private static int ApplyToCurrentWindows()
    {
        HashSet<IntPtr> seen = new HashSet<IntPtr>();
        EnumWindows(delegate(IntPtr window, IntPtr state)
        {
            if (!IsTaskbarWindow(window)) return true;

            uint processId;
            GetWindowThreadProcessId(window, out processId);
            if (processId == 0 || !IsTargetProcess(processId)) return true;

            seen.Add(window);
            ApplyToWindow(window, processId);
            return true;
        }, IntPtr.Zero);

        List<IntPtr> stale = new List<IntPtr>();
        foreach (KeyValuePair<IntPtr, TrackedWindow> entry in TrackedWindows)
        {
            if (!seen.Contains(entry.Key) || !IsWindow(entry.Key)) stale.Add(entry.Key);
        }
        foreach (IntPtr window in stale) TrackedWindows.Remove(window);
        return seen.Count;
    }

    private static void ApplyToWindow(IntPtr window, uint processId)
    {
        TrackedWindow tracked;
        if (!TrackedWindows.TryGetValue(window, out tracked) || tracked.ProcessId != processId)
        {
            tracked = new TrackedWindow
            {
                Handle = window,
                ProcessId = processId,
                OriginalLargeIcon = SendIconMessage(window, WM_GETICON, ICON_BIG, IntPtr.Zero),
                OriginalSmallIcon = SendIconMessage(window, WM_GETICON, ICON_SMALL, IntPtr.Zero),
                OriginalWindowTitle = ReadWindowTitle(window)
            };

            string originalRelaunchIcon;
            bool originalWasEmpty;
            tracked.PropertyCaptured = TryReadRelaunchIcon(window, out originalRelaunchIcon, out originalWasEmpty);
            tracked.OriginalRelaunchIcon = originalRelaunchIcon;
            tracked.OriginalPropertyWasEmpty = originalWasEmpty;
            TrackedWindows[window] = tracked;
            Console.WriteLine("APPLY hwnd=0x{0:X} pid={1}", window.ToInt64(), processId);
        }

        SendIconMessage(window, WM_SETICON, ICON_BIG, _largeIcon);
        SendIconMessage(window, WM_SETICON, ICON_SMALL, _smallIcon);
        SendWindowTitle(window, _windowTitle);
        if (tracked.PropertyCaptured) TryWriteRelaunchIcon(window, _iconResource, false);
    }

    private static void RestoreAllWindows()
    {
        foreach (TrackedWindow tracked in TrackedWindows.Values)
        {
            if (!IsWindow(tracked.Handle) || !IsTargetProcess(tracked.ProcessId)) continue;
            SendIconMessage(tracked.Handle, WM_SETICON, ICON_BIG, tracked.OriginalLargeIcon);
            SendIconMessage(tracked.Handle, WM_SETICON, ICON_SMALL, tracked.OriginalSmallIcon);
            SendWindowTitle(tracked.Handle, tracked.OriginalWindowTitle);
            if (tracked.PropertyCaptured)
            {
                TryWriteRelaunchIcon(
                    tracked.Handle,
                    tracked.OriginalRelaunchIcon,
                    tracked.OriginalPropertyWasEmpty);
            }
        }
        TrackedWindows.Clear();
    }

    private static IntPtr SendIconMessage(IntPtr window, uint message, uint iconType, IntPtr icon)
    {
        IntPtr result;
        IntPtr success = SendMessageTimeout(
            window,
            message,
            new UIntPtr(iconType),
            icon,
            SMTO_ABORTIFHUNG,
            500,
            out result);
        return success == IntPtr.Zero ? IntPtr.Zero : result;
    }

    private static bool IsTaskbarWindow(IntPtr window)
    {
        return IsWindowVisible(window)
            && GetWindow(window, GW_OWNER) == IntPtr.Zero
            && GetWindowTextLength(window) > 0;
    }

    private static string ReadWindowTitle(IntPtr window)
    {
        int length = GetWindowTextLength(window);
        if (length <= 0) return String.Empty;
        StringBuilder title = new StringBuilder(length + 1);
        GetWindowText(window, title, title.Capacity);
        return title.ToString();
    }

    private static bool SendWindowTitle(IntPtr window, string title)
    {
        IntPtr result;
        IntPtr success = SendMessageTimeout(
            window,
            WM_SETTEXT,
            UIntPtr.Zero,
            title ?? String.Empty,
            SMTO_ABORTIFHUNG,
            500,
            out result);
        return success != IntPtr.Zero;
    }

    private static bool IsTargetProcess(uint processId)
    {
        IntPtr process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, processId);
        if (process == IntPtr.Zero) return false;
        try
        {
            uint capacity = 32768;
            StringBuilder path = new StringBuilder((int)capacity);
            if (!QueryFullProcessImageName(process, 0, path, ref capacity)) return false;
            return path.ToString().StartsWith(_installRoot, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            CloseHandle(process);
        }
    }

    private static bool TryReadRelaunchIcon(IntPtr window, out string value, out bool wasEmpty)
    {
        value = null;
        wasEmpty = true;
        IPropertyStore propertyStore = null;
        PropVariant variant = new PropVariant();
        try
        {
            Guid interfaceId = PropertyStoreGuid;
            int result = SHGetPropertyStoreForWindow(window, ref interfaceId, out propertyStore);
            if (result < 0 || propertyStore == null) return false;

            PropertyKey key = RelaunchIconKey;
            result = propertyStore.GetValue(ref key, out variant);
            if (result < 0) return false;
            if (variant.VariantType == VT_EMPTY)
            {
                wasEmpty = true;
                return true;
            }
            if (variant.VariantType != VT_LPWSTR) return false;

            wasEmpty = false;
            value = Marshal.PtrToStringUni(variant.PointerValue);
            return true;
        }
        catch
        {
            return false;
        }
        finally
        {
            PropVariantClear(ref variant);
            if (propertyStore != null) Marshal.ReleaseComObject(propertyStore);
        }
    }

    private static bool TryWriteRelaunchIcon(IntPtr window, string value, bool writeEmpty)
    {
        IPropertyStore propertyStore = null;
        PropVariant variant = new PropVariant();
        try
        {
            Guid interfaceId = PropertyStoreGuid;
            int result = SHGetPropertyStoreForWindow(window, ref interfaceId, out propertyStore);
            if (result < 0 || propertyStore == null) return false;

            if (writeEmpty)
            {
                variant.VariantType = VT_EMPTY;
            }
            else
            {
                variant.VariantType = VT_LPWSTR;
                variant.PointerValue = Marshal.StringToCoTaskMemUni(value ?? String.Empty);
            }

            PropertyKey key = RelaunchIconKey;
            result = propertyStore.SetValue(ref key, ref variant);
            if (result < 0) return false;
            result = propertyStore.Commit();
            return result >= 0;
        }
        catch
        {
            return false;
        }
        finally
        {
            PropVariantClear(ref variant);
            if (propertyStore != null) Marshal.ReleaseComObject(propertyStore);
        }
    }

    private static void TryDeleteFile(string path)
    {
        try
        {
            if (!String.IsNullOrEmpty(path) && File.Exists(path)) File.Delete(path);
        }
        catch
        {
            // A stale stop signal is harmless; the next poll will retry cleanup.
        }
    }
}
