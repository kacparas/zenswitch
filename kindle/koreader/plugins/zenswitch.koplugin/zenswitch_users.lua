--[[
ZenSwitch user management: add, rename and remove profiles from inside KOReader.

New users share the running KOReader install and get:
  - a data folder   <zenswitch>/profiles/<Name>/   (settings, progress, highlights; KO_HOME)
  - a home folder   /mnt/us/<Name>/  with Books/
  - a line in profiles.conf and a launcher /mnt/us/documents/<Name>.sh
Removing a user never deletes anything: the data folder and launcher are moved to
<zenswitch>/removed/, and the home folder (their books) is left in place.
]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local M = {}

local DOCS = "/mnt/us/documents"
local STORAGE = "/mnt/us"

local function conf_path() return os.getenv("ZENSWITCH_CONF") end
local function zs_home() local c = conf_path(); return c and c:match("^(.*)/[^/]+$") end
local function install_dir() return os.getenv("KOREADER_DIR") end
local function data_dir() return os.getenv("KO_HOME") or install_dir() end

local function exists(p) return lfs.attributes(p, "mode") ~= nil end

local function read_lines()
    local f = io.open(conf_path(), "r")
    if not f then return {} end
    local lines = {}
    for l in f:lines() do lines[#lines + 1] = l:gsub("\r$", "") end
    f:close()
    return lines
end

local function write_lines(lines)
    local tmp = conf_path() .. ".new"
    local f = assert(io.open(tmp, "w"))
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
    os.rename(tmp, conf_path())
end

local function profile_names()
    local names = {}
    for _i, l in ipairs(read_lines()) do
        local n = l:match("^([^#|][^|]*)|")
        if n then names[#names + 1] = n end
    end
    return names
end

local function valid_name(name)
    if not name or not name:match("^[%w][%w _%-]*$") or #name > 30 then
        return false, _("Use letters, digits, spaces, - or _ (max 30).")
    end
    for _i, n in ipairs(profile_names()) do
        if n:lower() == name:lower() then return false, T(_("There is already a user called %1."), n) end
    end
    return true
end

local function write_launcher(name)
    local path = DOCS .. "/" .. name .. ".sh"
    local f = assert(io.open(path, "w"))
    f:write(string.format([[#!/bin/sh
# Name: %s
# Author: ZenSwitch
# DontUseFBInk
exec /bin/sh "%s/zenswitch.sh" --asap "%s"
]], name, zs_home(), name))
    f:close()
    return path
end

local function copy_file(src, dst)
    local i = io.open(src, "rb"); if not i then return false end
    local o = io.open(dst, "wb"); if not o then i:close(); return false end
    o:write(i:read("*a")); i:close(); o:close()
    return true
end

-- Per-user settings to carry over when copying ("look and feel", not reading data).
local SKIP_SETTINGS = {
    lastfile = true, lastdir = true, home_dir = true, extra_plugin_paths = true,
    LocalSend_device_name = true, LocalSend_save_dir = true, LocalSend_last_update_check = true,
}
local SKIP_ZENOS = { ["library_item_cache.lua"] = true, ["quote_state.lua"] = true, ["stats.lua"] = true,
                     ["home.lua"] = true, ["battery.lua"] = true }

local function seed_settings(new_data, home, name, copy_current)
    local s = LuaSettings:open(new_data .. "/settings.reader.lua")
    if copy_current then
        local cur = LuaSettings:open(data_dir() .. "/settings.reader.lua")
        for k, v in pairs(cur.data) do
            if not SKIP_SETTINGS[k] then s.data[k] = v end
        end
        local src = data_dir() .. "/settings/ZenOS"
        if exists(src) then
            util.makePath(new_data .. "/settings/ZenOS")
            for f in lfs.dir(src) do
                if f:match("%.lua$") and not SKIP_ZENOS[f] then
                    copy_file(src .. "/" .. f, new_data .. "/settings/ZenOS/" .. f)
                end
            end
        end
    end
    s.data.home_dir = home
    s.data.lastdir = home
    s.data.LocalSend_device_name = "Kindle - " .. name
    s.data.LocalSend_save_dir = home .. "/Books"
    s:flush()
end

function M.add(on_done)
    local dlg
    dlg = InputDialog:new{
        title = _("New user"),
        input_hint = _("Name"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
            { text = _("Next"), is_enter_default = true, callback = function()
                local name = util.trim(dlg:getInputText() or "")
                local ok, err = valid_name(name)
                if not ok then
                    UIManager:show(InfoMessage:new{ text = err })
                    return
                end
                UIManager:close(dlg)
                local choice
                choice = ButtonDialog:new{
                    title = T(_("Settings for %1"), name),
                    buttons = {
                        {{ text = _("Start fresh"), callback = function() UIManager:close(choice); M.create(name, false, on_done) end }},
                        {{ text = _("Copy my current settings"), callback = function() UIManager:close(choice); M.create(name, true, on_done) end }},
                    },
                }
                UIManager:show(choice)
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function M.create(name, copy_current, on_done)
    local new_data = zs_home() .. "/profiles/" .. name
    local home = STORAGE .. "/" .. name
    if exists(new_data) then
        UIManager:show(InfoMessage:new{ text = T(_("%1 already exists. Remove or rename it first."), new_data) })
        return
    end
    util.makePath(new_data .. "/plugins")  -- empty on purpose: plugins come from the install
    util.makePath(home .. "/Books")
    seed_settings(new_data, home, name, copy_current)
    local lines = read_lines()
    lines[#lines + 1] = string.format("%s|%s|%s", name, install_dir(), new_data)
    write_lines(lines)
    write_launcher(name)
    UIManager:show(ConfirmBox:new{
        text = T(_("User %1 added.\nLibrary folder: %2\nLauncher: %3.sh in the Kindle library.\n\nSwitch to %1 now?"), name, home, name),
        ok_text = _("Switch"),
        ok_callback = function() if on_done then on_done(name) end end,
    })
end

local function pick_user(title, exclude_current, cb)
    local current = os.getenv("ZENSWITCH_PROFILE")
    local buttons = {}
    local dlg
    for _i, n in ipairs(profile_names()) do
        if not (exclude_current and n == current) then
            buttons[#buttons + 1] = {{ text = n, callback = function() UIManager:close(dlg); cb(n) end }}
        end
    end
    if #buttons == 0 then
        UIManager:show(InfoMessage:new{ text = _("No other users.") })
        return
    end
    dlg = ButtonDialog:new{ title = title, buttons = buttons }
    UIManager:show(dlg)
end

function M.remove()
    pick_user(_("Remove which user?"), true, function(name)
        UIManager:show(ConfirmBox:new{
            text = T(_("Remove %1?\n\nTheir settings and reading data are moved to zenswitch/removed/ (not deleted). Their library folder stays where it is."), name),
            ok_text = _("Remove"),
            ok_callback = function()
                local lines, kept, data = read_lines(), {}, nil
                for _i, l in ipairs(lines) do
                    local n, rest = l:match("^([^#|][^|]*)|(.*)$")
                    if n == name then data = rest:match("|(.+)$") else kept[#kept + 1] = l end
                end
                write_lines(kept)
                local dest = zs_home() .. "/removed/" .. name .. "-" .. os.date("%Y%m%d-%H%M%S")
                util.makePath(dest)
                if data and exists(data) then os.rename(data, dest .. "/data") end
                local launcher = DOCS .. "/" .. name .. ".sh"
                if exists(launcher) then os.rename(launcher, dest .. "/" .. name .. ".sh") end
                UIManager:show(InfoMessage:new{ text = T(_("%1 removed. Kept in %2"), name, dest) })
            end,
        })
    end)
end

function M.rename(on_done)
    local old = os.getenv("ZENSWITCH_PROFILE")
    local dlg
    dlg = InputDialog:new{
        title = T(_("Rename %1"), old),
        input = old,
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
            { text = _("Rename"), is_enter_default = true, callback = function()
                local name = util.trim(dlg:getInputText() or "")
                if name == old then UIManager:close(dlg); return end
                local ok, err = valid_name(name)
                if not ok then UIManager:show(InfoMessage:new{ text = err }); return end
                UIManager:close(dlg)
                local lines = read_lines()
                for i, l in ipairs(lines) do
                    local n, rest = l:match("^([^#|][^|]*)|(.*)$")
                    if n == old then lines[i] = name .. "|" .. rest end
                end
                write_lines(lines)
                os.remove(DOCS .. "/" .. old .. ".sh")
                write_launcher(name)
                -- restart into the renamed profile so the new name is active everywhere
                if on_done then on_done(name) end
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

return M
