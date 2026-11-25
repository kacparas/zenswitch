--[[
ZenSwitch plugin: asks the zenswitch.sh launcher to start another profile.

It writes the target profile's name to $ZENSWITCH_NEXT_FILE and then does a normal
"Restart KOReader" (exit code 85), so the current book and settings are saved the
usual way. The launcher sees the file and starts KOReader again for that profile
(the same or a different KOReader with that profile's data folder), without waking the Kindle UI.
]]

local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
local Users = require("zenswitch_users")  -- must load now: plugin dir is only on package.path during init

local ZenSwitch = WidgetContainer:extend{
    name = "zenswitch",
    is_doc_only = false,
}

local function readProfiles()
    local list = {}
    local conf = os.getenv("ZENSWITCH_CONF")
    if not conf then return list end
    local f = io.open(conf, "r")
    if not f then return list end
    for raw in f:lines() do
        local line = raw:gsub("\r$", "")
        if not line:match("^%s*#") then
            local name, dir = line:match("^([^|]+)|(.+)$")
            if name and dir then
                table.insert(list, { name = name, dir = dir })
            end
        end
    end
    f:close()
    return list
end

local function launchedByZenSwitch()
    return os.getenv("ZENSWITCH_NEXT_FILE") ~= nil and os.getenv("ZENSWITCH_PROFILE") ~= nil
end

-- Profiles other than the one running now, in profiles.conf order.
local function otherProfiles()
    local current = os.getenv("ZENSWITCH_PROFILE")
    local others = {}
    for _i, p in ipairs(readProfiles()) do
        if p.name ~= current then table.insert(others, p) end
    end
    return others
end

function ZenSwitch:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function ZenSwitch:onDispatcherRegisterActions()
    Dispatcher:registerAction("zenswitch_next", {
        category = "none",
        event = "ZenSwitchNext",
        title = _("Switch to next profile"),
        general = true,
    })
    Dispatcher:registerAction("zenswitch_users", {
        category = "none",
        event = "ZenSwitchUsers",
        title = _("ZenSwitch users"),
        general = true,
    })
    Dispatcher:registerAction("zenswitch_usb", {
        category = "none",
        event = "ZenSwitchUSB",
        title = _("USB drive mode"),
        general = true,
    })
end

function ZenSwitch:notAvailable()
    UIManager:show(InfoMessage:new{
        text = _("Quick switching only works when this profile was started from its ZenSwitch scriptlet in the library."),
    })
end

function ZenSwitch:switchTo(name)
    if not launchedByZenSwitch() then
        return self:notAvailable()
    end
    local f, err = io.open(os.getenv("ZENSWITCH_NEXT_FILE"), "w")
    if not f then
        logger.warn("ZenSwitch: cannot write next-profile file:", err)
        UIManager:show(InfoMessage:new{ text = _("ZenSwitch: could not request the switch.") })
        return
    end
    f:write(name, "\n")
    f:close()
    logger.info("ZenSwitch: switching to", name)
    UIManager:show(InfoMessage:new{ text = T(_("Switching to %1 …"), name), timeout = 2 })
    UIManager:forceRePaint()
    -- Same path as Exit > Restart KOReader: closes the book cleanly, then exits with 85.
    UIManager:broadcastEvent(Event:new("Restart"))
end

-- Exit KOReader and share the Kindle drive over USB; zenswitch.sh restarts this
-- profile once the computer ejects it.
function ZenSwitch:onZenSwitchUSB()
    if not launchedByZenSwitch() then
        self:notAvailable()
        return true
    end
    local f, err = io.open(os.getenv("ZENSWITCH_NEXT_FILE"), "w")
    if not f then
        logger.warn("ZenSwitch: cannot write next-profile file:", err)
        UIManager:show(InfoMessage:new{ text = _("ZenSwitch: could not start USB mode.") })
        return true
    end
    f:write("@usb\n")
    f:close()
    logger.info("ZenSwitch: entering USB drive mode")
    UIManager:show(InfoMessage:new{ text = _("Starting USB drive mode …"), timeout = 2 })
    UIManager:forceRePaint()
    UIManager:broadcastEvent(Event:new("Restart"))
    return true
end

function ZenSwitch:onZenSwitchNext()
    local others = otherProfiles()
    if not launchedByZenSwitch() then
        return self:notAvailable()
    end
    if #others == 0 then
        UIManager:show(InfoMessage:new{ text = _("ZenSwitch: no other profile in profiles.conf.") })
        return true
    end
    self:switchTo(others[1].name)
    return true
end

-- Users dialog (also reachable as a dispatcher action: gestures, or launcher tiles in zenOS and similar)
function ZenSwitch:onZenSwitchUsers()
    if not launchedByZenSwitch() then
        self:notAvailable()
        return true
    end
    local ButtonDialog = require("ui/widget/buttondialog")
    local dlg
    dlg = ButtonDialog:new{
        title = T(_("ZenSwitch users (now: %1)"), os.getenv("ZENSWITCH_PROFILE") or "?"),
        buttons = {
            {{ text = _("Add user…"), callback = function()
                UIManager:close(dlg); Users.add(function(name) self:switchTo(name) end) end }},
            {{ text = T(_("Rename %1…"), os.getenv("ZENSWITCH_PROFILE") or ""), callback = function()
                UIManager:close(dlg); Users.rename(function(name) self:switchTo(name) end) end }},
            {{ text = _("Remove a user…"), callback = function()
                UIManager:close(dlg); Users.remove() end }},
        },
    }
    UIManager:show(dlg)
    return true
end

local function zenosPresent(ui)
    return ui and (ui.zenos ~= nil or ui.ZenOS ~= nil) or package.loaded["common/plugin_root"] ~= nil
end

function ZenSwitch:showZenOSHelp()
    UIManager:show(InfoMessage:new{
        text = _("zenOS tiles for ZenSwitch:\n\nIn zenOS, add a launcher tile of type Action and pick one of:\n• Switch to next profile\n• ZenSwitch users\n• USB drive mode\n\nZenSwitch works the same without zenOS: everything is also in Tools → Profiles and can be bound to gestures."),
    })
end

-- Lean mode is a flag file read by zenswitch.sh at start.
function ZenSwitch:toggleLean()
    local f = os.getenv("ZENSWITCH_LEAN_FILE")
    if not f then return self:notAvailable() end
    local lfs = require("libs/libkoreader-lfs")
    local on = lfs.attributes(f, "mode") == "file"
    if on then
        os.remove(f)
    else
        local h = io.open(f, "w"); if h then h:write("on\n"); h:close() end
    end
    local now_running = os.getenv("STOP_FRAMEWORK") == "yes"
    UIManager:show(InfoMessage:new{
        text = (not on) and _("Lean mode on.\nIt applies the next time you open a profile from the Kindle library: the Amazon UI is then stopped while you read (more free memory). Going back to the Kindle home screen takes about a minute.")
            or _("Lean mode off.\nFrom the next start the Amazon UI is only paused again (instant return to the Kindle home screen)."),
    })
    logger.info("ZenSwitch: lean mode", on and "off" or "on", "(running lean now:", now_running, ")")
end

function ZenSwitch:addToMainMenu(menu_items)
    -- Everything in one place under Tools; works with or without zenOS.
    menu_items.zenswitch_tools = {
        sorting_hint = "tools",
        text = _("Profiles (ZenSwitch)"),
        sub_item_table_func = function()
            local items = {
                { text_func = function()
                      local others = otherProfiles()
                      return #others == 1 and T(_("Switch to %1"), others[1].name) or _("Switch profile…")
                  end,
                  enabled_func = launchedByZenSwitch,
                  callback = function() menu_items.zenswitch.callback() end },
                { text = _("Add user…"), enabled_func = launchedByZenSwitch,
                  callback = function() Users.add(function(name) self:switchTo(name) end) end },
                { text_func = function() return T(_("Rename %1…"), os.getenv("ZENSWITCH_PROFILE") or "") end,
                  enabled_func = launchedByZenSwitch,
                  callback = function() Users.rename(function(name) self:switchTo(name) end) end },
                { text = _("Remove a user…"), enabled_func = launchedByZenSwitch,
                  callback = function() Users.remove() end },
                { text = _("USB drive mode"), enabled_func = launchedByZenSwitch,
                  callback = function() self:onZenSwitchUSB() end },
                { text = _("Lean mode (stop the Amazon UI while in KOReader)"),
                  enabled_func = launchedByZenSwitch,
                  checked_func = function()
                      local f = os.getenv("ZENSWITCH_LEAN_FILE")
                      return f and require("libs/libkoreader-lfs").attributes(f, "mode") == "file"
                  end,
                  callback = function() self:toggleLean() end, separator = true },
            }
            if zenosPresent(self.ui) then
                table.insert(items, { text = _("Using zenOS? Set up tiles…"), callback = function() self:showZenOSHelp() end })
            end
            return items
        end,
    }
    -- Kept for quick access and for existing launcher tiles that call it by this key.
    menu_items.zenswitch = {
        sorting_hint = "main",
        text_func = function()
            local others = otherProfiles()
            if launchedByZenSwitch() and #others == 1 then
                return T(_("Switch to %1"), others[1].name)
            end
            return _("Switch profile")
        end,
        callback = function()
            local others = otherProfiles()
            if not launchedByZenSwitch() then
                return self:notAvailable()
            end
            if #others == 1 then
                return self:switchTo(others[1].name)
            end
            -- More than two profiles: let the user pick.
            local ButtonDialog = require("ui/widget/buttondialog")
            local dialog
            local buttons = {}
            for _i, p in ipairs(others) do
                table.insert(buttons, {{
                    text = p.name,
                    callback = function()
                        UIManager:close(dialog)
                        self:switchTo(p.name)
                    end,
                }})
            end
            dialog = ButtonDialog:new{ title = _("Switch to profile"), buttons = buttons }
            UIManager:show(dialog)
        end,
    }
end

return ZenSwitch
