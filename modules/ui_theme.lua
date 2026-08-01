-- Module: modules/ui_theme.lua
-- Dynamic REAPER Theme Color Integration, Input Styling, Card Styling, and Plugin Format Badges.

local UITheme = {}

-- Helper to convert REAPER BGR COLORREF to ImGui RGBA integer
local function reaper_col_to_imgui(r_col, alpha)
  if not r_col or r_col < 0 then return nil end
  local r = r_col & 0xFF
  local g = (r_col >> 8) & 0xFF
  local b = (r_col >> 16) & 0xFF
  local a = alpha or 0xFF
  return (r << 24) | (g << 16) | (b << 8) | a
end

-- Neutral Dark Palette matching REAPER's native UI theme
local COLORS = {
  WindowBg             = 0x242424FF,
  ChildBg              = 0x242424FF,
  PopupBg              = 0x242424FF,
  FrameBg              = 0x333333FF,
  FrameBgHovered       = 0x3E3E3EFF,
  FrameBgActive        = 0x484848FF,
  SliderGrab           = 0x4A5872FF,
  SliderGrabActive     = 0x5C6D8CFF,
  Header               = 0x333333FF,
  HeaderHovered        = 0x424242FF,
  HeaderActive         = 0x4A5872FF,
  Button               = 0x333333FF,
  ButtonHovered        = 0x424242FF,
  ButtonActive         = 0x4A5872FF,
  CardBg               = 0x2E2E2EFF,
  CardBgHovered        = 0x3A3A3AFF,
  CardBgSelected       = 0x4A5872FF,
  CardBorder           = 0x3A3A3AFF,
  ScrollbarBg          = 0x242424FF,
  ScrollbarGrab        = 0x3E3E3EFF,
  ScrollbarGrabHovered = 0x4A4A4AFF,
  ScrollbarGrabActive  = 0x585858FF,
  TextPrimary          = 0xDFE3E8FF,
  TextMuted            = 0x9A9A9AFF,
  StarYellow           = 0xFFD54FFF,
  AccentCyan           = 0x00E5FFFF,

  -- Plugin Type Badges
  VST3_Badge           = 0x00E5FF88,
  VST_Badge            = 0x0288D188,
  AU_Badge             = 0xFFB74D88,
  CLAP_Badge           = 0xAB47BC88,
  JSFX_Badge           = 0x66BB6A88,
}

-- Synchronize theme colors dynamically with REAPER native theme
function UITheme.sync_reaper_theme()
  if reaper.GetThemeColor then
    local dock_bg = reaper_col_to_imgui(reaper.GetThemeColor("col_dock_bg", 0))
    local main_bg = reaper_col_to_imgui(reaper.GetThemeColor("col_main_bg", 0)) or dock_bg
    local main_text = reaper_col_to_imgui(reaper.GetThemeColor("col_main_text", 0))

    local target_bg = dock_bg or main_bg
    if target_bg then
      COLORS.WindowBg = target_bg
      COLORS.ChildBg = target_bg
      COLORS.PopupBg = target_bg
      COLORS.ScrollbarBg = target_bg

      local r = (target_bg >> 24) & 0xFF
      local g = (target_bg >> 16) & 0xFF
      local b = (target_bg >> 8) & 0xFF

      -- FrameBg (input fields, dropdown combos, zoom slider track)
      local frame_r = math.min(255, r + 14)
      local frame_g = math.min(255, g + 14)
      local frame_b = math.min(255, b + 14)
      COLORS.FrameBg = (frame_r << 24) | (frame_g << 16) | (frame_b << 8) | 0xFF

      local fhov_r = math.min(255, r + 26)
      local fhov_g = math.min(255, g + 26)
      local fhov_b = math.min(255, b + 26)
      COLORS.FrameBgHovered = (fhov_r << 24) | (fhov_g << 16) | (fhov_b << 8) | 0xFF
      COLORS.FrameBgActive = (math.min(255, r + 36) << 24) | (math.min(255, g + 36) << 16) | (math.min(255, b + 36) << 8) | 0xFF

      -- Card & Button Backgrounds
      local card_r = math.min(255, r + 8)
      local card_g = math.min(255, g + 8)
      local card_b = math.min(255, b + 8)
      COLORS.CardBg = (card_r << 24) | (card_g << 16) | (card_b << 8) | 0xFF
      COLORS.Button = COLORS.FrameBg

      local hov_r = math.min(255, r + 20)
      local hov_g = math.min(255, g + 20)
      local hov_b = math.min(255, b + 20)
      COLORS.CardBgHovered = (hov_r << 24) | (hov_g << 16) | (hov_b << 8) | 0xFF
      COLORS.ButtonHovered = COLORS.CardBgHovered
    end

    if main_text then
      COLORS.TextPrimary = main_text
    end
  end
end

function UITheme.push_theme(ctx)
  UITheme.sync_reaper_theme()

  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(),             COLORS.WindowBg)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(),              COLORS.ChildBg)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(),              COLORS.PopupBg)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(),              COLORS.FrameBg)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(),       COLORS.FrameBgHovered)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(),        COLORS.FrameBgActive)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrab(),           COLORS.SliderGrab)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrabActive(),     COLORS.SliderGrabActive)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(),               COLORS.Header)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(),        COLORS.HeaderHovered)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(),         COLORS.HeaderActive)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),               COLORS.Button)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),        COLORS.ButtonHovered)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),         COLORS.ButtonActive)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(),          COLORS.ScrollbarBg)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrab(),        COLORS.ScrollbarGrab)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabHovered(), COLORS.ScrollbarGrabHovered)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarGrabActive(),  COLORS.ScrollbarGrabActive)
  reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),                 COLORS.TextPrimary)

  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 2.0, 2.0)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(),0.0)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), 0.0)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 3.0)
  reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(),   4.0, 4.0)
end

function UITheme.pop_theme(ctx)
  reaper.ImGui_PopStyleVar(ctx, 5)
  reaper.ImGui_PopStyleColor(ctx, 19)
end

function UITheme.get_badge_color(p_type)
  if p_type == "VST3" then return COLORS.VST3_Badge end
  if p_type == "VST"  then return COLORS.VST_Badge end
  if p_type == "AU"   then return COLORS.AU_Badge end
  if p_type == "CLAP" then return COLORS.CLAP_Badge end
  if p_type == "JSFX" then return COLORS.JSFX_Badge end
  return COLORS.Header
end

UITheme.COLORS = COLORS

return UITheme
