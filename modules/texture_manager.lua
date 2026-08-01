-- Module: modules/texture_manager.lua
-- Asynchronous Rate-Limited Texture Loader & Cache for ReaImGui.

local TextureManager = {}

local cache = {}         -- filepath -> ImGui_Image or false
local pending_queue = {} -- list of filepaths queued for loading
local queued_set = {}    -- set of filepaths currently in queue

local function file_exists(path)
  if not path or path == "" then return false end
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

local function create_image_from_file(ctx, filepath)
  if reaper.APIExists("ImGui_CreateImage") then
    local ok, img = pcall(reaper.ImGui_CreateImage, filepath)
    if ok and img then return img end
  end

  if reaper.APIExists("ImGui_CreateImageFromFile") then
    local ok, img = pcall(reaper.ImGui_CreateImageFromFile, filepath)
    if ok and img then return img end
  end

  return nil
end

-- Get cached texture or queue for background loading
function TextureManager.get_texture(ctx, filepath)
  if not filepath or not file_exists(filepath) then return nil end

  -- Return cached handle if available and valid
  if cache[filepath] ~= nil then
    if cache[filepath] == false then return nil end
    if reaper.APIExists("ImGui_ValidatePtr") then
      if not reaper.ImGui_ValidatePtr(cache[filepath], "ImGui_Image*") then
        cache[filepath] = nil -- Handle expired/invalidated, clear to reload
      else
        return cache[filepath]
      end
    else
      return cache[filepath]
    end
  end

  -- Add to queue if not already queued
  if not queued_set[filepath] then
    queued_set[filepath] = true
    table.insert(pending_queue, filepath)
  end

  return nil
end

-- Process up to 2 new textures per frame to prevent GPU/ReaImGui overload
function TextureManager.update_loader(ctx)
  local loaded_this_frame = 0
  while #pending_queue > 0 and loaded_this_frame < 2 do
    local filepath = table.remove(pending_queue, 1)
    queued_set[filepath] = nil

    if file_exists(filepath) then
      local img = create_image_from_file(ctx, filepath)
      if img then
        cache[filepath] = img
      else
        cache[filepath] = false
      end
    else
      cache[filepath] = false
    end
    loaded_this_frame = loaded_this_frame + 1
  end
end

function TextureManager.clear_unused(ctx)
  -- No-op to keep handles valid throughout window lifecycle
end

function TextureManager.reset()
  cache = {}
  pending_queue = {}
  queued_set = {}
end

return TextureManager
