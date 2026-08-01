import os, sys, subprocess, platform

def capture_window_mac(dest_path):
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    
    # 1. Try to find floating window bounds of REAPER FX
    applescript = """
    tell application "System Events"
        tell process "REAPER"
            set winList to every window
            repeat with w in winList
                try
                    set winTitle to name of w
                    if winTitle contains "FX:" or winTitle contains "VST" or winTitle contains "AU:" or winTitle contains "CLAP:" or winTitle contains "JS:" then
                        set winPos to position of w
                        set winSize to size of w
                        return (item 1 of winPos) & "," & (item 2 of winPos) & "," & (item 1 of winSize) & "," & (item 2 of winSize)
                    end if
                end try
            end repeat
        end tell
    end tell
    return "NOT_FOUND"
    """
    try:
        proc = subprocess.run(["/usr/bin/osascript", "-e", applescript], capture_output=True, text=True)
        out = proc.stdout.strip()
        if out and out != "NOT_FOUND" and "," in out:
            parts = out.split(",")
            if len(parts) == 4:
                x, y, w, h = parts[0], parts[1], parts[2], parts[3]
                res = subprocess.run(["/usr/sbin/screencapture", "-x", f"-R{x},{y},{w},{h}", dest_path], capture_output=True, text=True)
                if os.path.exists(dest_path) and os.path.getsize(dest_path) > 0:
                    return "SUCCESS"
    except Exception:
        pass

    # 2. Fallback to interactive camera selection mode (Click the plugin window)
    res = subprocess.run(["/usr/sbin/screencapture", "-i", "-W", "-x", dest_path], capture_output=True, text=True)
    if os.path.exists(dest_path) and os.path.getsize(dest_path) > 0:
        return "SUCCESS"
        
    return "CANCELLED"

def capture_window_win(dest_path):
    try:
        dest_path_win = dest_path.replace("/", "\\")
        ps_script = f"""
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        
        $code = @'
        using System;
        using System.Runtime.InteropServices;
        public class Win32 {{
            [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
            [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
            [StructLayout(LayoutKind.Sequential)] public struct RECT {{ public int Left; public int Top; public int Right; public int Bottom; }}
        }}
'@
        Add-Type -TypeDefinition $code
        
        $hwnd = [Win32]::GetForegroundWindow()
        $rect = New-Object Win32+RECT
        [Win32]::GetWindowRect($hwnd, [ref]$rect)
        
        $w = $rect.Right - $rect.Left
        $h = $rect.Bottom - $rect.Top
        
        if ($w -gt 50 -and $h -gt 50) {{
            $bmp = New-Object System.Drawing.Bitmap($w, $h)
            $gfx = [System.Drawing.Graphics]::FromImage($bmp)
            $gfx.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
            
            [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName('{dest_path_win}'))
            $bmp.Save('{dest_path_win}', [System.Drawing.Imaging.ImageFormat]::Png)
            $gfx.Dispose()
            $bmp.Dispose()
            Write-Output "SUCCESS"
        }} else {{
            Write-Output "NO_IMAGE"
        }}
        """
        res = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps_script], capture_output=True, text=True)
        if "SUCCESS" in res.stdout and os.path.exists(dest_path) and os.path.getsize(dest_path) > 0:
            return "SUCCESS"
        return "NO_IMAGE"
    except Exception as e:
        return f"ERROR: {e}"

if __name__ == "__main__":
    if len(sys.argv) > 1:
        out_file = sys.argv[1]
        if platform.system() == "Darwin":
            print(capture_window_mac(out_file))
        else:
            print(capture_window_win(out_file))
    else:
        print("NO_PATH")
