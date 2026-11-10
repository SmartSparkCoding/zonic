using System.Runtime.InteropServices;

namespace Zonic;

/// <summary>Play/pause, next and previous from the keyboard, wherever the focus is.
///
/// WebView2 does not register with the Windows media flyout the way a native player
/// would, so the keys are caught with a low level hook instead. That also means the app
/// owns them while it runs, which is the behaviour you want from a music player.</summary>
public sealed class MediaKeys : IDisposable
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;

    private const int VK_MEDIA_NEXT_TRACK = 0xB0;
    private const int VK_MEDIA_PREV_TRACK = 0xB1;
    private const int VK_MEDIA_STOP = 0xB2;
    private const int VK_MEDIA_PLAY_PAUSE = 0xB3;

    private delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, HookProc callback, IntPtr module, uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? name);

    [StructLayout(LayoutKind.Sequential)]
    private struct KbdLlHookStruct
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr extraInfo;
    }

    private readonly HookProc _callback;
    private IntPtr _hook = IntPtr.Zero;

    /// <summary>Raised on the hook thread, so handlers must marshal to the UI thread.</summary>
    public event Action<string>? Pressed;

    public MediaKeys()
    {
        // Held in a field so the delegate is not collected while Windows still calls it.
        _callback = Handle;
    }

    public void Start()
    {
        if (_hook != IntPtr.Zero) { return; }
        _hook = SetWindowsHookEx(WH_KEYBOARD_LL, _callback, GetModuleHandle(null), 0);
    }

    private IntPtr Handle(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0 && (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN))
        {
            var info = Marshal.PtrToStructure<KbdLlHookStruct>(lParam);
            var action = info.vkCode switch
            {
                VK_MEDIA_PLAY_PAUSE => "toggle",
                VK_MEDIA_NEXT_TRACK => "next",
                VK_MEDIA_PREV_TRACK => "previous",
                VK_MEDIA_STOP => "pause",
                _ => null
            };
            if (action is not null)
            {
                Pressed?.Invoke(action);
                return (IntPtr)1;
            }
        }
        return CallNextHookEx(_hook, code, wParam, lParam);
    }

    public void Dispose()
    {
        if (_hook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_hook);
            _hook = IntPtr.Zero;
        }
    }
}
