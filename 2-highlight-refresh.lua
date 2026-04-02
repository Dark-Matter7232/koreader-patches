local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")

local PATCH_DEBUG = false

local function patch_log(msg)
    if not PATCH_DEBUG then return end
    local f = io.open("/tmp/patch.log", "a")
    if f then f:write(msg .. "\n") f:close() end
end

local function get_render_key(ui)
    if not ui then
        return nil
    end

    if ui._hr_get_render_hash then
        return ui._hr_get_render_hash(ui._hr_document, true)
    end

    if ui._hr_get_current_page then
        return ui._hr_get_current_page(ui._hr_document, true)
    end

    return nil
end

local function refresh_highlights(view)
    local ui = view and view.ui
    if not ui then
        return
    end

    local render_key = get_render_key(ui)
    if render_key ~= nil and ui._last_render_hash ~= render_key then
        ui._last_render_hash = render_key
        ui._hr_epoch = (ui._hr_epoch or 0) + 1
    end

    local epoch = ui._hr_epoch or 0
    if ui._hr_applied_epoch == epoch then
        patch_log("skip_no_change")
        return
    end

    if ui._hr_reset_highlight_cache then
        ui._hr_reset_highlight_cache(view)
        patch_log("refresh_triggered")
    end

    ui._hr_applied_epoch = epoch
end

local function wrap_method(view, method_name)
    local original = view and view[method_name]
    if type(original) ~= "function" then
        return false
    end

    view[method_name] = function(self, ...)
        refresh_highlights(self)
        return original(self, ...)
    end

    return true
end

local function hook_view(ui)
    if not ui or not ui.view or ui._highlight_refresh_hooked then
        return
    end

    local view = ui.view
    local document = ui.document
    local get_render_hash = document and document.getDocumentRenderingHash
    local get_current_page = document and document.getCurrentPage
    local reset_highlight_cache = view.resetHighlightBoxesCache

    if type(reset_highlight_cache) ~= "function" then
        return
    end

    if type(get_render_hash) ~= "function" and type(get_current_page) ~= "function" then
        return
    end

    ui._hr_document = document
    ui._hr_get_render_hash = type(get_render_hash) == "function" and get_render_hash or nil
    ui._hr_get_current_page = type(get_current_page) == "function" and get_current_page or nil
    ui._hr_reset_highlight_cache = reset_highlight_cache
    ui._hr_epoch = ui._hr_epoch or 0
    ui._highlight_refresh_hooked = true
    patch_log("ui_ready")

    local view = ui.view
    wrap_method(view, "drawPageView")
    wrap_method(view, "drawScrollView")
end

local orig_registerModule = ReaderUI.registerModule
ReaderUI.registerModule = function(self, name, ui_module, always_active)
    local result = orig_registerModule(self, name, ui_module, always_active)
    if name == "view" then
        hook_view(self)
    end
    return result
end

patch_log("patch_load")

UIManager:nextTick(function()
    patch_log("inject_hooks")
    pcall(function()
        hook_view(ReaderUI.instance or UIManager:getTopWidget())
    end)
end)