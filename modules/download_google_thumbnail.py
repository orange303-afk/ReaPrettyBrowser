import os
import sys
import re
import json
import urllib.request
import urllib.parse
import subprocess
import platform

def search_and_download_image(plugin_name, vendor, dest_path):
    query_terms = []
    if plugin_name:
        query_terms.append(plugin_name)
    if vendor and vendor != "Unknown" and vendor.lower() not in plugin_name.lower():
        query_terms.append(vendor)
    query_terms.append("VST plugin")

    query = " ".join(query_terms)

    headers = {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://duckduckgo.com/"
    }

    candidates = []

    # 1. Primary search: DuckDuckGo Images
    try:
        url = "https://duckduckgo.com/?q=" + urllib.parse.quote(query)
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=5) as resp:
            html = resp.read().decode("utf-8", errors="ignore")
        
        vqd_match = re.search(r"vqd=([\d-]+)", html) or re.search(r"vqd=([a-zA-Z0-9_-]+)", html)
        if vqd_match:
            vqd = vqd_match.group(1)
            iurl = f"https://duckduckgo.com/i.js?q={urllib.parse.quote(query)}&vqd={vqd}&o=json"
            ireq = urllib.request.Request(iurl, headers=headers)
            with urllib.request.urlopen(ireq, timeout=5) as iresp:
                data = json.loads(iresp.read().decode("utf-8", errors="ignore"))
                for item in data.get("results", []):
                    img_url = item.get("image")
                    w = item.get("width", 0)
                    h = item.get("height", 0)
                    if img_url and (w == 0 or w >= 250) and (h == 0 or h >= 180):
                        candidates.append(img_url)
    except Exception as e:
        pass

    # 2. Fallback search: Google Images HTML
    if not candidates:
        try:
            gurl = "https://www.google.com/search?q=" + urllib.parse.quote(query) + "&tbm=isch"
            greq = urllib.request.Request(gurl, headers=headers)
            with urllib.request.urlopen(greq, timeout=5) as gresp:
                ghtml = gresp.read().decode("utf-8", errors="ignore")
            
            found_urls = re.findall(r'["\'](https?://[^"\']+\.(?:png|jpg|jpeg|webp))["\']', ghtml, re.IGNORECASE)
            for furl in found_urls:
                if "gstatic" not in furl and "google" not in furl and furl not in candidates:
                    candidates.append(furl)
        except Exception as e:
            pass

    if not candidates:
        return "NO_IMAGE"

    # Try downloading top candidates until one succeeds
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    tmp_file = dest_path + ".tmp"

    for img_url in candidates[:6]:
        try:
            down_req = urllib.request.Request(img_url, headers={
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            })
            with urllib.request.urlopen(down_req, timeout=7) as dresp:
                raw_bytes = dresp.read()
                if len(raw_bytes) < 3000: # ignore tiny files / broken downloads
                    continue
                with open(tmp_file, "wb") as f:
                    f.write(raw_bytes)

            # Convert downloaded image to PNG format
            converted = False
            try:
                from PIL import Image
                import io
                img = Image.open(tmp_file)
                img.save(dest_path, "PNG")
                converted = True
            except Exception:
                pass

            if not converted:
                if platform.system() == "Darwin":
                    res = subprocess.run(["sips", "-s", "format", "png", tmp_file, "--out", dest_path], capture_output=True)
                    if os.path.exists(dest_path) and os.path.getsize(dest_path) > 1000:
                        converted = True
                else:
                    dest_win = dest_path.replace("/", "\\")
                    tmp_win = tmp_file.replace("/", "\\")
                    ps_cmd = f"""
                    Add-Type -AssemblyName System.Drawing
                    $img = [System.Drawing.Image]::FromFile('{tmp_win}')
                    $img.Save('{dest_win}', [System.Drawing.Imaging.ImageFormat]::Png)
                    $img.Dispose()
                    """
                    res = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps_cmd], capture_output=True)
                    if os.path.exists(dest_path) and os.path.getsize(dest_path) > 1000:
                        converted = True

            if os.path.exists(tmp_file):
                try: os.remove(tmp_file)
                except Exception: pass

            if converted and os.path.exists(dest_path) and os.path.getsize(dest_path) > 1000:
                return "SUCCESS"
        except Exception:
            if os.path.exists(tmp_file):
                try: os.remove(tmp_file)
                except Exception: pass
            continue

    return "NO_IMAGE"

if __name__ == "__main__":
    if len(sys.argv) > 3:
        p_name = sys.argv[1]
        p_vendor = sys.argv[2]
        out_file = sys.argv[3]
        print(search_and_download_image(p_name, p_vendor, out_file))
    elif len(sys.argv) > 1:
        p_name = sys.argv[1]
        out_file = sys.argv[2] if len(sys.argv) > 2 else "/tmp/thumb.png"
        print(search_and_download_image(p_name, "Unknown", out_file))
    else:
        print("NO_PATH")
