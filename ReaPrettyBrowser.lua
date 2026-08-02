-- @description ReaPrettyBrowser - Visual Plugin Browser for REAPER (ReaImGui)
-- @version 2.0.0
-- @author Ilya Orange
-- @about
--   Modern Visual Plugin Browser for REAPER powered by ReaImGui. Features responsive
--   thumbnail grids with Cubase snapshot import, lazy image loading, real-time search,
--   category filtering (VST3, VST, AU, CLAP), favorites, docking, and track FX insertion.

local info = debug.getinfo(1, "S")
local script_path = (info and info.source) and info.source:match("^@?(.*[/\\])") or ""
package.path = script_path .. "?.lua;" .. script_path .. "modules/?.lua;" .. package.path

-- Check for ReaImGui extension dependency
if not reaper.APIExists("ImGui_CreateContext") then
  reaper.MB(
    "ReaPrettyBrowser requires the 'ReaImGui' extension to run.\n\n" ..
    "Please install 'ReaImGui' via ReaPack (Extensions -> ReaPack -> Browse packages -> ReaImGui) " ..
    "and restart REAPER.",
    "ReaPrettyBrowser - Missing Dependency",
    0
  )
  return
end

-- Load Modules
local Config = require("modules.config")
local PluginScanner = require("modules.plugin_scanner")
local TextureManager = require("modules.texture_manager")
local UITheme = require("modules.ui_theme")
local UIViews = require("modules.ui_views")

-- Global Application State
local ctx = nil
local saved_filters = Config.get_saved_filters()

local app_state = {
  running = true,
  plugins = {},
  snapshot_dirs = {},
  favorites = Config.get_favorites(),
  search_query = saved_filters.search_query or "",
  active_category = saved_filters.active_category or "All",
  selected_category = saved_filters.selected_category or "All Categories",
  selected_vendor = saved_filters.selected_vendor or "All Vendors",
  sort_mode = "Name (A-Z)",
  card_zoom = Config.get_zoom_size(),
  custom_snapshot_path = Config.get_custom_snapshot_path(),
  selected_plugin = nil,
  selected_plugins = {},
  last_clicked_plugin = nil,
  dock_id = Config.get_dock_id(),
  vendor_list = { "All Vendors" },
}

-- Initial Plugin Database Scan
app_state.plugins, app_state.snapshot_dirs, app_state.vendor_list = PluginScanner.scan_all_plugins(app_state.custom_snapshot_path)

-- Main Event & Render Loop
local function loop()
  UITheme.push_theme(ctx)

  -- Standard window size and docking support
  reaper.ImGui_SetNextWindowSize(ctx, 960, 640, reaper.ImGui_Cond_FirstUseEver())
  
  local window_flags = reaper.ImGui_WindowFlags_NoCollapse()
  local visible, open = reaper.ImGui_Begin(ctx, "Plugins", true, window_flags)

  if visible then
    -- Toolbar
    UIViews.draw_toolbar(ctx, app_state)

    reaper.ImGui_Separator(ctx)

    -- Plugin Cards Grid Area
    UIViews.draw_plugin_grid(ctx, app_state)

    reaper.ImGui_Separator(ctx)

    -- Status Bar
    UIViews.draw_statusbar(ctx, app_state)

    reaper.ImGui_End(ctx)
  end

  UITheme.pop_theme(ctx)

  -- Background texture loader processing queued images smoothly
  TextureManager.update_loader(ctx)

  if open and app_state.running then
    reaper.defer(loop)
  else
    TextureManager.reset()
    Config.save_favorites(app_state.favorites)
    Config.save_zoom_size(app_state.card_zoom)
    Config.save_filters(app_state)
  end
end

-- Create Context with Docking Enabled & Run
ctx = reaper.ImGui_CreateContext('Plugins', reaper.ImGui_ConfigFlags_DockingEnable())
reaper.defer(loop)
