import os
import sys
import re
import json
import urllib.request
import urllib.parse
import subprocess
import platform

def trim_solid_borders(dest_path):
    if not os.path.exists(dest_path):
        return
    if platform.system() == "Darwin":
        try:
            from AppKit import NSImage, NSBitmapImageRep, NSPNGFileType, NSGraphicsContext, NSMakeRect
            image = NSImage.alloc().initWithContentsOfFile_(dest_path)
            if not image:
                return
            rep = NSBitmapImageRep.imageRepWithData_(image.TIFFRepresentation())
            if not rep:
                return

            width = rep.pixelsWide()
            height = rep.pixelsHigh()
            if width < 100 or height < 100:
                return

            corner = rep.colorAtX_y_(0, 0)
            if not corner:
                return
            cr, cg, cb, ca = corner.redComponent(), corner.greenComponent(), corner.blueComponent(), corner.alphaComponent()

            is_bg = (ca < 0.1) or (cr > 0.95 and cg > 0.95 and cb > 0.95) or (cr < 0.05 and cg < 0.05 and cb < 0.05)
            if not is_bg:
                return

            def is_same_bg(x, y):
                c = rep.colorAtX_y_(x, y)
                if not c:
                    return True
                if ca < 0.1:
                    return c.alphaComponent() < 0.1
                r, g, b = c.redComponent(), c.greenComponent(), c.blueComponent()
                return abs(r - cr) < 0.04 and abs(g - cg) < 0.04 and abs(b - cb) < 0.04

            top, bottom, left, right = 0, height - 1, 0, width - 1

            step_x = max(1, width // 80)
            step_y = max(1, height // 80)

            while top < height - 1 and all(is_same_bg(x, top) for x in range(0, width, step_x)):
                top += 1
            while bottom > top and all(is_same_bg(x, bottom) for x in range(0, width, step_x)):
                bottom -= 1
            while left < width - 1 and all(is_same_bg(left, y) for y in range(top, bottom, step_y)):
                left += 1
            while right > left and all(is_same_bg(right, y) for y in range(top, bottom, step_y)):
                right -= 1

            crop_w = right - left + 1
            crop_h = bottom - top + 1

            if crop_w > width * 0.5 and crop_h > height * 0.5 and (left > 4 or top > 4 or right < width - 5 or bottom < height - 5):
                cropped_rep = NSBitmapImageRep.alloc().initWithBitmapDataPlanes_pixelsWide_pixelsHigh_bitsPerSample_samplesPerPixel_hasAlpha_isPlanar_colorSpaceName_bytesPerRow_bitsPerPixel_(
                    None, crop_w, crop_h, 8, 4, True, False, "NSCalibratedRGBColorSpace", 0, 0
                )
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.setCurrentContext_(NSGraphicsContext.graphicsContextWithBitmapImageRep_(cropped_rep))
                rep.drawInRect_fromRect_operation_fraction_respectFlipped_hints_(
                    NSMakeRect(0, 0, crop_w, crop_h),
                    NSMakeRect(left, height - bottom - 1, crop_w, crop_h),
                    1, 1.0, True, None
                )
                NSGraphicsContext.restoreGraphicsState()

                png_data = cropped_rep.representationUsingType_properties_(NSPNGFileType, None)
                if png_data:
                    png_data.writeToFile_atomically_(dest_path, True)
        except Exception:
            pass

def search_candidate_urls(plugin_name, vendor):
    query_terms = []
    clean_vendor = vendor if (vendor and vendor != "Unknown") else ""
    clean_name = plugin_name or ""

    if clean_vendor:
        query_terms.append(clean_vendor)
        if clean_vendor.lower() in clean_name.lower():
            query_terms = [clean_name]
        else:
            query_terms.append(clean_name)
    else:
        query_terms.append(clean_name)

    query_terms.append("VST plugin full GUI screenshot interface clean -youtube -banner -promo -boxshot")
    query = " ".join(query_terms)

    headers = {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://duckduckgo.com/"
    }

    raw_candidates = []

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
                    title = item.get("title", "")
                    w = item.get("width", 0)
                    h = item.get("height", 0)
                    if img_url and w > 0 and h > 0:
                        aspect = w / h
                        if 0.75 <= aspect <= 2.45 and w >= 300 and h >= 220:
                            raw_candidates.append((img_url, title, w, h))
    except Exception:
        pass

    if not raw_candidates:
        try:
            gurl = "https://www.google.com/search?q=" + urllib.parse.quote(query) + "&tbm=isch"
            greq = urllib.request.Request(gurl, headers=headers)
            with urllib.request.urlopen(greq, timeout=5) as gresp:
                ghtml = gresp.read().decode("utf-8", errors="ignore")
            
            found_urls = re.findall(r'["\'](https?://[^"\']+\.(?:png|jpg|jpeg|webp))["\']', ghtml, re.IGNORECASE)
            for furl in found_urls:
                if "gstatic" not in furl and "google" not in furl:
                    raw_candidates.append((furl, "", 800, 500))
        except Exception:
            pass

    if not raw_candidates:
        return []

    bad_keywords = [
        "youtube", "ytimg", "banner", "header", "boxshot", "bundle", "promo", "thumb",
        "logo", "cover", "sale", "discount", "reverb.com", "ebay", "sweetwater.com/store",
        "thomann", "used-gear", "hardware-rack", "rackunit", "photo-rack", "gear-photo",
        "maxresdefault", "hqdefault", "sddefault"
    ]
    good_keywords = ["plugin", "vst", "gui", "screenshot", "software", "interface", "full", "clean", "uad", "audio"]

    filtered_candidates = []

    for img_url, title, w, h in raw_candidates:
        combined = (img_url + " " + title).lower()
        if any(bad in combined for bad in bad_keywords):
            continue
        score = sum(2 for good in good_keywords if good in combined)
        if ".png" in img_url.lower():
            score += 3
        filtered_candidates.append((score, img_url))

    filtered_candidates.sort(key=lambda x: x[0], reverse=True)
    candidates = [url for _, url in filtered_candidates]
    if not candidates:
        candidates = [url for url, _, _, _ in raw_candidates]

    return candidates

def download_and_convert(img_url, dest_path):
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    tmp_file = dest_path + ".tmp"
    try:
        down_req = urllib.request.Request(img_url, headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        })
        with urllib.request.urlopen(down_req, timeout=6) as dresp:
            raw_bytes = dresp.read()
            if len(raw_bytes) < 3000:
                return False
            with open(tmp_file, "wb") as f:
                f.write(raw_bytes)

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
            trim_solid_borders(dest_path)
            return True
    except Exception:
        if os.path.exists(tmp_file):
            try: os.remove(tmp_file)
            except Exception: pass
        return False

    return False

def search_all_candidates_json(plugin_name, vendor, out_dir):
    candidates = search_candidate_urls(plugin_name, vendor)
    os.makedirs(out_dir, exist_ok=True)

    results = []
    idx = 1
    for img_url in candidates:
        dest_path = os.path.join(out_dir, f"cand_{idx}.png")
        if download_and_convert(img_url, dest_path):
            results.append({"id": idx, "path": dest_path, "url": img_url})
            idx += 1
            if idx > 6: # limit to top 6 preview candidates
                break

    print(json.dumps(results))

def search_and_download_image(plugin_name, vendor, dest_path):
    candidates = search_candidate_urls(plugin_name, vendor)
    for img_url in candidates[:8]:
        if download_and_convert(img_url, dest_path):
            return "SUCCESS"
    return "NO_IMAGE"

if __name__ == "__main__":
    if len(sys.argv) > 3 and sys.argv[3] == "--search-all":
        p_name = sys.argv[1]
        p_vendor = sys.argv[2]
        out_dir = sys.argv[4] if len(sys.argv) > 4 else "/tmp/reapretty_candidates"
        search_all_candidates_json(p_name, p_vendor, out_dir)
    elif len(sys.argv) > 3:
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
