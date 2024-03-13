-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

--[[ mocelet 2024
 
Events in RODRET are quite standard, like the TRADFRI on/off switch, remember
to bind to OnOff and Level cluster in init.lua or will not send events.

Toggled-Up support to expose a release after long-press.

Multi-tap custom tweak with configurable timer and max presses.

Auto-fire custom tweak with configurable max loops and delay.

]]

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local custom_button_utils = require "custom_button_utils"
local custom_features = require "custom_features"
local log = require "log"

local Level = clusters.Level
local OnOff = clusters.OnOff

local BUTTON_1 = "button1"
local BUTTON_2 = "button2"

local function multitap_button_handler(button_name, pressed_type)
  return function(driver, device, zb_rx)
    if not custom_features.multitap_enabled(device, button_name) then
      custom_button_utils.emit_button_event(device, button_name, pressed_type)
      return
    end
    custom_button_utils.handle_multitap(device, button_name, pressed_type, device.preferences.multiTapMaxPresses, device.preferences.multiTapDelayMillis)
  end
end

local function released_button_handler(pressed_type)
  return function(driver, device, zb_rx)
    -- Always stop the autofire
    custom_button_utils.autofire_stop(device)

    if device.preferences.exposeReleaseActions then
      custom_button_utils.emit_button_event(device, "main", pressed_type)
    end
  end
end

local function info_changed(driver, device, event, args)
  local needs_press_type_change = 
    (args.old_st_store.preferences.exposeReleaseActions ~= device.preferences.exposeReleaseActions)
    or (args.old_st_store.preferences.multiTapEnabledB1 ~= device.preferences.multiTapEnabledB1)
    or (args.old_st_store.preferences.multiTapEnabledB2 ~= device.preferences.multiTapEnabledB2)
    or (args.old_st_store.preferences.multiTapMaxPresses ~= device.preferences.multiTapMaxPresses)

  if needs_press_type_change then
    for _, component in pairs(device.profile.components) do
        local supported_pressed_types = {"pushed", "held"} -- default
        custom_features.may_insert_multitap_types(supported_pressed_types, device, component.id)
        custom_features.may_insert_exposed_release_type(supported_pressed_types, device, component.id)
        device:emit_component_event(component, capabilities.button.supportedButtonValues(supported_pressed_types), {visibility = { displayed = false }})
    end
  end 
end

local function autofire_button_handler(button_name, pressed_type)
  return function(driver, device, zb_rx)
    -- Held event is always sent, with autofire or not
    custom_button_utils.emit_button_event(device, button_name, pressed_type)

    -- If autofire custom tweak is enabled it will repeat the event automatically
    if custom_features.autofire_enabled(device, button_name) then
      custom_button_utils.autofire_start(device, button_name, pressed_type, device.preferences.autofireDelay, device.preferences.autofireMaxLoops)
    end
  end
end

local on_off_switch = {
  NAME = "RODRET Dimmer",
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = multitap_button_handler(BUTTON_1, capabilities.button.button.pushed),
        [OnOff.server.commands.On.ID] = multitap_button_handler(BUTTON_2, capabilities.button.button.pushed)
      },
      [Level.ID] = {
        [Level.server.commands.Move.ID] = autofire_button_handler(BUTTON_1, capabilities.button.button.held),
        [Level.server.commands.MoveWithOnOff.ID] = autofire_button_handler(BUTTON_2, capabilities.button.button.held),
        [Level.server.commands.StopWithOnOff.ID] = released_button_handler(capabilities.button.button.up),
        [Level.server.commands.Stop.ID] = released_button_handler(capabilities.button.button.up) -- they don't seem to send this, but just in case (others do)
      }
    }
  },
  lifecycle_handlers = {
    infoChanged = info_changed
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "RODRET Dimmer"
  end
}

return on_off_switch
