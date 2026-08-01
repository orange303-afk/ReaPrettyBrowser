-- Module: modules/config.lua
-- ExtState persistence for ReaPrettyBrowser preferences, favorites, hidden plugins, custom categories, zoom level, custom thumbnails and snapshot paths.

local Config = {}

local EXT_SECTION = "ReaPrettyBrowser_PluginBrowser"

local function save_ext(key, val)
  reaper.SetExtState(EXT_SECTION, key, tostring(val), true)
end

local function get_ext(key, default)
  if reaper.HasExtState(EXT_SECTION, key) then
    local val = reaper.GetExtState(EXT_SECTION, key)
    if type(default) == "number" then return tonumber(val) or default end
    if type(default) == "boolean" then return val == "true" end
    return val
  end
  return default
end

-- Favorites set
function Config.get_favorites()
  local raw = get_ext("favorites", "")
  local favs = {}
  for item in raw:gmatch("[^;]+") do
    favs[item] = true
  end
  return favs
end

function Config.save_favorites(favs_set)
  local list = {}
  for item, is_fav in pairs(favs_set) do
    if is_fav then
      table.insert(list, item)
    end
  end
  save_ext("favorites", table.concat(list, ";"))
end

-- Hidden plugins set
function Config.get_hidden_plugins()
  local raw = get_ext("hidden_plugins", "")
  local set = {}
  for item in raw:gmatch("[^;]+") do
    set[item] = true
  end
  return set
end

function Config.hide_plugin(ident)
  local set = Config.get_hidden_plugins()
  set[ident] = true
  local list = {}
  for item in pairs(set) do
    table.insert(list, item)
  end
  save_ext("hidden_plugins", table.concat(list, ";"))
end

function Config.unhide_all()
  save_ext("hidden_plugins", "")
end

-- Custom multi-category assignments (ident -> { ["Cat1"] = true, ["Cat2"] = true })
function Config.get_custom_categories()
  local raw = get_ext("custom_categories", "")
  local map = {}
  for pair in raw:gmatch("[^;]+") do
    local k, v = pair:match("^([^=]+)=(.*)$")
    if k and v then
      local set = {}
      for cat in v:gmatch("[^,]+") do
        set[cat] = true
      end
      map[k] = set
    end
  end
  return map
end

function Config.add_category_to_plugin(ident, cat_name)
  if not ident or not cat_name or cat_name == "" then return end
  local map = Config.get_custom_categories()
  if not map[ident] then map[ident] = {} end
  map[ident][cat_name] = true

  Config.unremove_category_from_plugin(ident, cat_name)

  local list = {}
  for k, set in pairs(map) do
    local cat_list = {}
    for c in pairs(set) do table.insert(cat_list, c) end
    if #cat_list > 0 then
      table.insert(list, k .. "=" .. table.concat(cat_list, ","))
    end
  end
  save_ext("custom_categories", table.concat(list, ";"))
end

function Config.save_custom_category(ident, cat_name)
  Config.add_category_to_plugin(ident, cat_name)
end

-- Removed categories set (ident -> { ["RemovedCat"] = true })
function Config.get_removed_categories()
  local raw = get_ext("removed_categories", "")
  local map = {}
  for pair in raw:gmatch("[^;]+") do
    local k, v = pair:match("^([^=]+)=(.*)$")
    if k and v then
      local set = {}
      for cat in v:gmatch("[^,]+") do
        set[cat] = true
      end
      map[k] = set
    end
  end
  return map
end

function Config.remove_category_from_plugin(ident, cat_name)
  if not ident or not cat_name or cat_name == "" then return end

  local map = Config.get_custom_categories()
  if map[ident] then
    map[ident][cat_name] = nil
    local list = {}
    for k, set in pairs(map) do
      local cat_list = {}
      for c in pairs(set) do table.insert(cat_list, c) end
      if #cat_list > 0 then
        table.insert(list, k .. "=" .. table.concat(cat_list, ","))
      end
    end
    save_ext("custom_categories", table.concat(list, ";"))
  end

  local rem_map = Config.get_removed_categories()
  if not rem_map[ident] then rem_map[ident] = {} end
  rem_map[ident][cat_name] = true

  local rem_list = {}
  for k, set in pairs(rem_map) do
    local cat_list = {}
    for c in pairs(set) do table.insert(cat_list, c) end
    if #cat_list > 0 then
      table.insert(rem_list, k .. "=" .. table.concat(cat_list, ","))
    end
  end
  save_ext("removed_categories", table.concat(rem_list, ";"))
end

function Config.unremove_category_from_plugin(ident, cat_name)
  local rem_map = Config.get_removed_categories()
  if rem_map[ident] and rem_map[ident][cat_name] then
    rem_map[ident][cat_name] = nil
    local rem_list = {}
    for k, set in pairs(rem_map) do
      local cat_list = {}
      for c in pairs(set) do table.insert(cat_list, c) end
      if #cat_list > 0 then
        table.insert(rem_list, k .. "=" .. table.concat(cat_list, ","))
      end
    end
    save_ext("removed_categories", table.concat(rem_list, ";"))
  end
end

-- User created custom category names list
function Config.get_user_category_list()
  local raw = get_ext("user_categories", "")
  local list = {}
  for item in raw:gmatch("[^;]+") do
    if item and item ~= "" then
      table.insert(list, item)
    end
  end
  return list
end

function Config.add_user_category(cat_name)
  if not cat_name or cat_name == "" then return end
  local existing = Config.get_user_category_list()
  for _, c in ipairs(existing) do
    if c:lower() == cat_name:lower() then return end
  end
  table.insert(existing, cat_name)
  save_ext("user_categories", table.concat(existing, ";"))
end

-- Custom thumbnail overrides (ident -> image_path)
function Config.get_custom_thumbnails()
  local raw = get_ext("custom_thumbnails", "")
  local map = {}
  for pair in raw:gmatch("[^;]+") do
    local k, v = pair:match("^([^=]+)=(.*)$")
    if k and v then
      map[k] = v
    end
  end
  return map
end

function Config.save_custom_thumbnail(ident, img_path)
  local map = Config.get_custom_thumbnails()
  map[ident] = img_path
  local list = {}
  for k, v in pairs(map) do
    if v and v ~= "" then
      table.insert(list, k .. "=" .. v)
    end
  end
  save_ext("custom_thumbnails", table.concat(list, ";"))
end

function Config.get_zoom_size()
  return get_ext("zoom_size", 140)
end

function Config.save_zoom_size(size)
  save_ext("zoom_size", math.floor(size))
end

function Config.get_custom_snapshot_path()
  return get_ext("custom_snapshot_path", "")
end

function Config.save_custom_snapshot_path(path)
  save_ext("custom_snapshot_path", path or "")
end

function Config.get_dock_id()
  return get_ext("dock_id", 0)
end

function Config.save_dock_id(dock_id)
  save_ext("dock_id", dock_id or 0)
end

function Config.get_saved_filters()
  return {
    active_category = get_ext("filter_active_category", "All"),
    selected_category = get_ext("filter_selected_category", "All Categories"),
    selected_vendor = get_ext("filter_selected_vendor", "All Vendors"),
    search_query = get_ext("filter_search_query", ""),
  }
end

function Config.save_filters(filters)
  if not filters then return end
  save_ext("filter_active_category", filters.active_category or "All")
  save_ext("filter_selected_category", filters.selected_category or "All Categories")
  save_ext("filter_selected_vendor", filters.selected_vendor or "All Vendors")
  save_ext("filter_search_query", filters.search_query or "")
end

-- Export all ExtState settings to a user specified text config file
function Config.export_all_settings(file_path)
  if not file_path or file_path == "" then return false end
  local f = io.open(file_path, "w")
  if not f then return false end

  local keys = {
    "favorites", "hidden_plugins", "custom_categories", "removed_categories",
    "user_categories", "custom_thumbnails", "custom_snapshot_path", "dock_id",
    "filter_active_category", "filter_selected_category", "filter_selected_vendor", "filter_search_query"
  }

  f:write("# ReaPrettyBrowser Configuration Backup\n")
  for _, k in ipairs(keys) do
    local val = get_ext(k, "")
    f:write(k .. "=" .. tostring(val) .. "\n")
  end
  f:close()
  return true
end

-- Import and restore all ExtState settings from a backup config file
function Config.import_all_settings(file_path)
  if not file_path or file_path == "" then return false end
  local f = io.open(file_path, "r")
  if not f then return false end

  for line in f:lines() do
    local l = line:match("^%s*(.-)%s*$") or ""
    if l ~= "" and l:sub(1, 1) ~= "#" and l:find("=") then
      local k, v = l:match("^([^=]+)=(.*)$")
      if k and v then
        save_ext(k, v)
      end
    end
  end
  f:close()
  return true
end

return Config
