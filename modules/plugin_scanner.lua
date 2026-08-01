-- Module: modules/plugin_scanner.lua
-- Dynamic live scanner for REAPER plugin database files (VST3, VST2, AU, CLAP, JSFX).
-- Uses REAPER's official reaper-fxtags.ini category database + keyword heuristics.

local PluginScanner = {}

-- Detect OS
local is_windows = reaper.GetOS():sub(1, 3) == "Win"

local function file_exists(path)
  if not path or path == "" then return false end
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

-- Clean string for fuzzy matching
local function clean_name(str)
  if not str then return "" end
  return str:lower():gsub("[%s%p%_]", "")
end

-- Load REAPER's official category & developer tags from reaper-fxtags.ini
local function load_reaper_fx_tags(res_path)
  local tag_file = res_path .. "/reaper-fxtags.ini"
  local f = io.open(tag_file, "r")
  if not f then return {}, {} end

  local cat_map = {}
  local vendor_map = {}

  local current_section = ""
  for line in f:lines() do
    local l = line:match("^%s*(.-)%s*$") or ""
    if l:sub(1, 1) == "[" and l:sub(-1) == "]" then
      current_section = l:sub(2, -2):lower()
    elseif l:find("=") then
      local key, tag = l:match("^([^=]+)=(.*)$")
      if key and tag then
        key = key:match("^%s*(.-)%s*$")
        tag = tag:match("^%s*(.-)%s*$")
        local k_low = key:lower()

        if current_section == "category" or current_section == "tag" or current_section == "user" then
          cat_map[k_low] = tag
          cat_map[clean_name(key)] = tag
        elseif current_section == "developer" or current_section == "vendor" then
          vendor_map[k_low] = tag
          vendor_map[clean_name(key)] = tag
        end
      end
    end
  end
  f:close()

  return cat_map, vendor_map
end

-- Auto-classify plugin category based on REAPER fxtags + keywords/flags
local function detect_category(name, val, raw_line, fxtag)
  local tag = fxtag or ""
  local t_low = tag:lower()
  local s = (name .. " " .. (val or "") .. " " .. (raw_line or "")):lower()

  -- 1. Instruments
  if s:find("!!!vsti") or s:find("<!inst>") or t_low:find("synth") or t_low:find("instrument") or t_low:find("sampler") or
     s:find("synth") or s:find("sampler") or s:find("piano") or s:find("organ") or s:find("drum") or s:find("keyboard") or
     s:find("instrument") or s:find("clavinet") or s:find("farfisa") or s:find("mellotron") or s:find("bass") or s:find("strings") or s:find("brass") then
    return "Instruments"
  end

  -- 2. Compressors
  if t_low:find("dynamic") or t_low:find("compressor") or t_low:find("limiter") or t_low:find("gate") or
     s:find("comp") or s:find("limiter") or s:find("gate") or s:find("deess") or 
     s:find("clipper") or s:find("dynamic") or s:find("stress") or s:find("transient") or s:find("maximizer") then
    return "Compressors"
  end

  -- 3. EQ & Filters
  if t_low:find("eq") or t_low:find("filter") or t_low:find("equaliz") or
     s:find("eq") or s:find("filter") or s:find("equaliz") or s:find("spectrogram") or s:find("analyzer") or s:find("curve") then
    return "EQ & Filters"
  end

  -- 4. Reverbs
  if t_low:find("reverb") or t_low:find("room") or t_low:find("space") or
     s:find("reverb") or s:find("room") or s:find("space") or s:find("chamber") or s:find("ambience") or s:find("plate") or s:find("hall") or s:find("verb") then
    return "Reverbs"
  end

  -- 5. Delays
  if t_low:find("delay") or t_low:find("echo") or
     s:find("delay") or s:find("echo") or s:find("tape stop") or s:find("repeat") or s:find("dub") then
    return "Delays"
  end

  -- 6. Modulation
  if t_low:find("modulation") or
     s:find("chorus") or s:find("flanger") or s:find("phaser") or s:find("modulat") or 
     s:find("dimension") or s:find("tremolo") or s:find("vibrato") or s:find("rotary") or s:find("ensemble") then
    return "Modulation"
  end

  -- 7. Distortion
  if t_low:find("distortion") or t_low:find("saturation") or t_low:find("amp") or
     s:find("distort") or s:find("saturat") or s:find("overdrive") or s:find("drive") or 
     s:find("fuzz") or s:find("bitcrush") or s:find("tape") or s:find("tube") or s:find("amp") or s:find("preamp") then
    return "Distortion"
  end

  -- 8. Pitch & Vocal
  if t_low:find("pitch") or t_low:find("vocal") or t_low:find("voice") or
     s:find("pitch") or s:find("vocoder") or s:find("voice") or s:find("vocal") or s:find("harmoniz") or s:find("tune") or s:find("autotune") or s:find("restoration") then
    return "Pitch & Vocal"
  end

  return "Utilities"
end

-- Strip common suffixes (Mono, Stereo, _v4, etc.) for snapshot matching
local function strip_suffixes(str)
  if not str then return "" end
  local s = str:gsub("%s+[Mm]ono%s*$", "")
               :gsub("%s+[Ss]tereo%s*$", "")
               :gsub("%s+5%.1%s*$", "")
               :gsub("%s+5%.0%s*$", "")
               :gsub("%s*%(m%)%s*$", "")
               :gsub("%s*%(s%)%s*$", "")
               :gsub("%_v%d+%s*$", "")
               :gsub("%s+v%d+%s*$", "")
  return s
end

-- Get potential Cubase & REAPER Snapshot directory paths
function PluginScanner.get_cubase_snapshot_paths(custom_path)
  local paths = {}

  if custom_path and custom_path ~= "" and file_exists(custom_path) then
    table.insert(paths, custom_path)
  end

  local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
  local res_path = reaper.GetResourcePath()

  -- Primary user REAPER Thumbnails & Yandex.Disk Snapshots paths
  table.insert(paths, home .. "/Documents/Reaper/Thumbnails")
  table.insert(paths, home .. "/Yandex.Disk.localized/StudioPro/Snapshots")
  table.insert(paths, home .. "/Documents/Steinberg/VST Thumbnails")

  if is_windows then
    local appdata = os.getenv("APPDATA") or (home .. "\\AppData\\Roaming")
    local docs = home .. "\\Documents"
    table.insert(paths, docs .. "\\Steinberg\\VST Thumbnails")
    table.insert(paths, appdata .. "\\Steinberg\\VST Audio Plugins Snapshots")
    table.insert(paths, appdata .. "\\Steinberg\\VST Thumbnails")
    table.insert(paths, res_path .. "\\snapshots")
  else
    -- macOS paths
    table.insert(paths, home .. "/Library/Application Support/Steinberg/VST Audio Plugins Snapshots")
    table.insert(paths, home .. "/Library/Preferences/Cubase 13/VST Audio Plugins Snapshots")
    table.insert(paths, home .. "/Library/Preferences/Cubase 12/VST Audio Plugins Snapshots")
    table.insert(paths, home .. "/Library/Preferences/Cubase 11/VST Audio Plugins Snapshots")
    table.insert(paths, res_path .. "/snapshots")
  end

  return paths
end

-- Scan directory recursively for snapshot image files (.png, .jpg)
local function scan_dir_recursive(dir, map)
  if not dir or dir == "" then return end

  local idx = 0
  repeat
    local file = reaper.EnumerateFiles(dir, idx)
    if file then
      local ext = file:match("^.+(%..+)$")
      if ext then
        ext = ext:lower()
        if ext == ".png" or ext == ".jpg" or ext == ".jpeg" then
          local full_path = dir .. "/" .. file
          local name_without_ext = file:match("^(.+)%..+$") or file
          
          map[name_without_ext:upper()] = full_path
          map[name_without_ext:lower()] = full_path
          
          local cleaned = clean_name(name_without_ext)
          if not map[cleaned] then
            map[cleaned] = full_path
          end
        end
      end
    end
    idx = idx + 1
  until not file

  idx = 0
  repeat
    local subdir = reaper.EnumerateSubdirectories(dir, idx)
    if subdir then
      scan_dir_recursive(dir .. "/" .. subdir, map)
    end
    idx = idx + 1
  until not subdir
end

function PluginScanner.scan_snapshots(snapshot_dirs)
  local map = {}
  for _, dir in ipairs(snapshot_dirs) do
    scan_dir_recursive(dir, map)
  end
  return map
end

-- Snapshot matching algorithm
local function find_snapshot(snapshot_map, name, clean_display, vendor, guid)
  if not snapshot_map then return nil end

  if guid and guid ~= "" then
    local g_up = guid:upper()
    if snapshot_map[g_up] then return snapshot_map[g_up] end
    local g_low = guid:lower()
    if snapshot_map[g_low] then return snapshot_map[g_low] end
    local c_guid = clean_name(guid)
    if snapshot_map[c_guid] then return snapshot_map[c_guid] end
  end

  local c_name = clean_name(name)
  if snapshot_map[c_name] then return snapshot_map[c_name] end

  local c_disp = clean_name(clean_display)
  if snapshot_map[c_disp] then return snapshot_map[c_disp] end

  local stripped = strip_suffixes(clean_display)
  local c_strip = clean_name(stripped)
  if snapshot_map[c_strip] then return snapshot_map[c_strip] end

  for map_key, img_path in pairs(snapshot_map) do
    if #map_key >= 3 then
      if c_disp:find(map_key, 1, true) or map_key:find(c_disp, 1, true) or
         c_strip:find(map_key, 1, true) or map_key:find(c_strip, 1, true) then
        return img_path
      end
    end
  end

  return nil
end

-- Helper to find all INI files matching a pattern in REAPER resource path
local function get_matching_ini_files(res_path, prefix)
  local files = {}
  local idx = 0
  repeat
    local fn = reaper.EnumerateFiles(res_path, idx)
    if fn then
      if fn:sub(1, #prefix) == prefix and fn:sub(-4) == ".ini" then
        table.insert(files, res_path .. "/" .. fn)
      end
    end
    idx = idx + 1
  until not fn
  return files
end

-- Parse all REAPER VST INI files (reaper-vstplugins*.ini)
local function parse_all_vst_ini(res_path, plugins, snapshot_map, fxtag_cats, fxtag_vendors)
  local ini_files = get_matching_ini_files(res_path, "reaper-vstplugins")
  for _, ini_path in ipairs(ini_files) do
    local f = io.open(ini_path, "r")
    if f then
      for line in f:lines() do
        local key, val = line:match("^([^=]+)=(.*)$")
        if key and val and not key:lower():find("%.dll$") then
          local is_vst3 = key:lower():find("%.vst3") ~= nil
          local p_type = is_vst3 and "VST3" or "VST"
          local guid = val:match("%{([%w]+),")
          local raw_name = val:match("([^,]+)$") or key
          local name = raw_name:gsub("%s*!%s*!%s*!.*$", "")
          name = name:gsub("^VST3:%s*", ""):gsub("^VST:%s*", "")
          
          local vendor = fxtag_vendors[name:lower()] or name:match("%((.-)%)") or "Unknown Vendor"
          local clean_display = name:gsub("%s*%b()", "")

          if clean_display ~= "<SHELL>" and name ~= "<SHELL>" then
            local ident = p_type .. ": " .. name
            local snapshot_file = find_snapshot(snapshot_map, name, clean_display, vendor, guid)
            local fxtag = fxtag_cats[name:lower()] or fxtag_cats[clean_display:lower()]
            local category = detect_category(name, val, line, fxtag)

            table.insert(plugins, {
              name = clean_display,
              full_name = name,
              raw_key = key,
              file_path = key,
              vendor = vendor,
              type = p_type,
              category = category,
              ident = ident,
              snapshot_path = snapshot_file,
              guid = guid,
            })
          end
        end
      end
      f:close()
    end
  end
end

-- Parse all REAPER AU INI files (reaper-auplugins*.ini)
local function parse_all_au_ini(res_path, plugins, snapshot_map, fxtag_cats, fxtag_vendors)
  local ini_files = get_matching_ini_files(res_path, "reaper-auplugins")
  for _, ini_path in ipairs(ini_files) do
    local f = io.open(ini_path, "r")
    if f then
      for line in f:lines() do
        local key, val = line:match("^([^=]+)=(.*)$")
        if key then
          local name = key
          if name:sub(1, 3) == "AU:" then name = name:sub(4) end
          
          local clean_display = name:gsub("%s*%b()", "")
          local vendor = fxtag_vendors[name:lower()] or name:match("^(.-):") or name:match("%((.-)%)") or "AudioUnit"
          if vendor:find(":") then vendor = vendor:match("^(.-):") end

          if clean_display ~= "<SHELL>" and name ~= "" then
            local ident = "AU: " .. name
            local snapshot_file = find_snapshot(snapshot_map, name, clean_display, vendor, nil)
            local fxtag = fxtag_cats[name:lower()] or fxtag_cats[clean_display:lower()]
            local category = detect_category(name, val or "", line, fxtag)

            table.insert(plugins, {
              name = clean_display,
              full_name = name,
              raw_key = key,
              file_path = key,
              vendor = vendor,
              type = "AU",
              category = category,
              ident = ident,
              snapshot_path = snapshot_file,
            })
          end
        end
      end
      f:close()
    end
  end
end

-- Parse all REAPER CLAP INI files (reaper-clap*.ini)
local function parse_all_clap_ini(res_path, plugins, snapshot_map, fxtag_cats, fxtag_vendors)
  local ini_files = get_matching_ini_files(res_path, "reaper-clap")
  for _, ini_path in ipairs(ini_files) do
    local f = io.open(ini_path, "r")
    if f then
      for line in f:lines() do
        if line:find("| ") then
          local clap_file = line:match("^(.-)%|") or line
          local name = line:match("|%s*(.-)$") or line
          local raw_name = name:gsub("%s*!%s*!%s*!.*$", "")
          local vendor = fxtag_vendors[raw_name:lower()] or raw_name:match("%((.-)%)") or "CLAP"
          local clean_display = raw_name:gsub("%s*%b()", "")

          if clean_display ~= "<SHELL>" and raw_name ~= "" then
            local ident = "CLAP: " .. raw_name
            local snapshot_file = find_snapshot(snapshot_map, raw_name, clean_display, vendor, nil)
            local fxtag = fxtag_cats[raw_name:lower()] or fxtag_cats[clean_display:lower()]
            local category = detect_category(raw_name, line, line, fxtag)

            table.insert(plugins, {
              name = clean_display,
              full_name = raw_name,
              raw_key = line,
              file_path = clap_file,
              vendor = vendor,
              type = "CLAP",
              category = category,
              ident = ident,
              snapshot_path = snapshot_file,
            })
          end
        end
      end
      f:close()
    end
  end
end

-- Main Scan Function: Scans REAPER live plugin INI databases on every run
function PluginScanner.scan_all_plugins(custom_snapshot_path)
  local Config = require("modules.config")
  local custom_thumbs = Config.get_custom_thumbnails()

  local res_path = reaper.GetResourcePath()
  local snapshot_dirs = PluginScanner.get_cubase_snapshot_paths(custom_snapshot_path)
  local snapshot_map = PluginScanner.scan_snapshots(snapshot_dirs)

  -- Load REAPER's official fxtags database
  local fxtag_cats, fxtag_vendors = load_reaper_fx_tags(res_path)

  local plugins = {}

  parse_all_vst_ini(res_path, plugins, snapshot_map, fxtag_cats, fxtag_vendors)
  parse_all_au_ini(res_path, plugins, snapshot_map, fxtag_cats, fxtag_vendors)
  parse_all_clap_ini(res_path, plugins, snapshot_map, fxtag_cats, fxtag_vendors)

  -- Deduplicate plugins by (type + full_name) so format versions remain distinct while preventing INI line duplicates
  local unique_plugins = {}
  local seen_keys = {}

  for _, p in ipairs(plugins) do
    local key = (p.type or "") .. "::" .. (p.full_name or p.name or "")
    p.uid = key

    if not seen_keys[key] then
      seen_keys[key] = p
      table.insert(unique_plugins, p)
    else
      local existing = seen_keys[key]
      if not existing.snapshot_path and p.snapshot_path then
        existing.snapshot_path = p.snapshot_path
      end
    end
  end

  plugins = unique_plugins

  local custom_categories = Config.get_custom_categories()
  local removed_categories = Config.get_removed_categories()
  local hidden_plugins = Config.get_hidden_plugins()

  -- Apply user custom categories, removed categories, hidden states, and collect unique vendors
  local vendor_map = {}
  for _, p in ipairs(plugins) do
    if not p.categories then
      p.categories = { [p.category or "Utilities"] = true }
    end

    -- Check custom category additions
    local c_cats = custom_categories[p.ident] or (p.uid and custom_categories[p.uid]) or custom_categories[p.full_name]
    if c_cats then
      for cat in pairs(c_cats) do
        p.categories[cat] = true
      end
    end

    -- Check category removals
    local r_cats = removed_categories[p.ident] or (p.uid and removed_categories[p.uid]) or removed_categories[p.full_name]
    if r_cats then
      for cat in pairs(r_cats) do
        p.categories[cat] = nil
      end
    end

    -- Set primary category for display
    local cat_keys = {}
    for c in pairs(p.categories) do table.insert(cat_keys, c) end
    if #cat_keys > 0 then
      p.category = cat_keys[1]
    else
      p.category = "Utilities"
      p.categories["Utilities"] = true
    end

    local c_thumb = custom_thumbs[p.ident] or (p.uid and custom_thumbs[p.uid]) or custom_thumbs[p.full_name]
    if c_thumb and c_thumb ~= "" then
      p.snapshot_path = c_thumb
    end

    if hidden_plugins[p.ident] or (p.uid and hidden_plugins[p.uid]) or hidden_plugins[p.full_name] then
      p.is_hidden = true
    end

    if p.vendor and p.vendor ~= "" then
      vendor_map[p.vendor] = true
    end
  end

  local vendor_list = { "All Vendors" }
  for v in pairs(vendor_map) do
    table.insert(vendor_list, v)
  end
  table.sort(vendor_list, function(a, b)
    if a == "All Vendors" then return true end
    if b == "All Vendors" then return false end
    return a:lower() < b:lower()
  end)

  return plugins, snapshot_dirs, vendor_list
end

return PluginScanner
