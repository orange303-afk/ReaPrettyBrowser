import os, sys, platform

def save_clipboard_mac(dest_path):
    try:
        from AppKit import NSPasteboard, NSPasteboardTypePNG, NSPasteboardTypeTIFF, NSBitmapImageRep, NSPNGFileType
        pb = NSPasteboard.generalPasteboard()
        data = pb.dataForType_(NSPasteboardTypePNG) or pb.dataForType_(NSPasteboardTypeTIFF)
        if not data:
            return "NO_IMAGE"
        
        rep = NSBitmapImageRep.imageRepWithData_(data)
        if not rep:
            return "NO_IMAGE"
            
        png_data = rep.representationUsingType_properties_(NSPNGFileType, None)
        if not png_data:
            return "NO_IMAGE"
            
        os.makedirs(os.path.dirname(dest_path), exist_ok=True)
        png_data.writeToFile_atomically_(dest_path, True)
        return "SUCCESS"
    except Exception as e:
        return f"ERROR: {e}"

def save_clipboard_win(dest_path):
    try:
        import subprocess
        dest_path_win = dest_path.replace("/", "\\")
        ps_script = f"""
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $img = [System.Windows.Forms.Clipboard]::GetImage()
        if ($img -ne $null) {{
            [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName('{dest_path_win}'))
            $img.Save('{dest_path_win}', [System.Drawing.Imaging.ImageFormat]::Png)
            $img.Dispose()
            Write-Output "SUCCESS"
        }} else {{
            Write-Output "NO_IMAGE"
        }}
        """
        res = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps_script], capture_output=True, text=True)
        if "SUCCESS" in res.stdout:
            return "SUCCESS"
        return "NO_IMAGE"
    except Exception as e:
        return f"ERROR: {e}"

if __name__ == "__main__":
    if len(sys.argv) > 1:
        out_file = sys.argv[1]
        if platform.system() == "Darwin":
            print(save_clipboard_mac(out_file))
        else:
            print(save_clipboard_win(out_file))
    else:
        print("NO_PATH")
