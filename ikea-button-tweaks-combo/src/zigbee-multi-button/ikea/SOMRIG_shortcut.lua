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

SOMRIG uses 0xFC80 cluster (no OnOff or Level like TRADFRI/RODRET) and
commands (0x03 pushed, 0x02 held and 0x06 double tap). 
Has two buttons and you need to check the source endpoint (0x01 or 0x02).
Remember to bind to 0xFC80 (instead of OnOff or Level) in endpoints 1 and 2.

Fast Tap custom tweak to minimize latency in buttons ignoring pushed/held/double tap
and triggering on first-press.

Toggled-Up support to expose a release after long-press.

Multi-tap custom tweak with specific windows for after first-press and after pushed/double
to account for the native double-tap mechanism.

]]

local capabilities = require "st.capabilities"
local custom_button_utils = require "custom_button_utils"
local custom_features = require "custom_features"
local log = require "log"

local MULTITAP_SOMRIG_FIRST_PRESS_WINDOW_MILLIS = 900 -- SOMRIG takes ~700-800ms to notify a pushed/double after first_press
local MULTITAP_SOMRIG_WINDOW_MILLIS = 1000 -- time to wait after a pushed/double event for the next first_press

local BUTTON_1 = "button1"
local BUTTON_2 = "button2"

-- A modified custom_button_utils.build_button_handler to check the source endpoint to get the button name.
-- is_initial is true when the button is pressed but the type (single/double/held) is not known yet. In that case,
-- the fast tap tweak will emit the given pressed_type (usually a pushed) without waiting to confirm the type.
local function build_somrig_button_handler(pressed_type, is_initial)
  return function(driver, device, zb_rx)
    local button_number = zb_rx.address_header.src_endpoint.value
    local button_name = button_number == 1 and BUTTON_1 or BUTTON_2

    -- AUTO-FIRE TWEAK (STOP on release)
    --'up' means a hold release, always stop the autofire
    if pressed_type == capabilities.button.button.up then
      custom_button_utils.autofire_stop(device)
    end

    local has_multitap = custom_features.multitap_enabled(device, button_name)
    if has_multitap and is_initial then
      custom_button_utils.multitap_first_press_hint(device, button_name, MULTITAP_SOMRIG_FIRST_PRESS_WINDOW_MILLIS)
    end
    
    -- EXPOSE RELEASE TWEAK
    if pressed_type == capabilities.button.button.up and not device.preferences.exposeReleaseActions then
      return -- ignore the event, not exposed
    end

    -- FAST TAP TWEAK
    -- When not enabled for a button, the initial press event is ignored (default behaviour)
    -- When enabled, the button triggers on the initial event, so further (non initial) events are ignored

    local fast_tap_enabled = {device.preferences.fastTapButton1, device.preferences.fastTapButton2}
    if ((is_initial and not fast_tap_enabled[button_number]) or (fast_tap_enabled[button_number] and not is_initial)) then
      return -- ignore the event
    end

    -- MULTI-TAP TWEAK
    if has_multitap and not is_initial and (pressed_type == capabilities.button.button.pushed or pressed_type == capabilities.button.button.double) then
      custom_button_utils.handle_multitap(device, button_name, pressed_type, device.preferences.multiTapMaxPresses, MULTITAP_SOMRIG_WINDOW_MILLIS)
      return -- processed
    end

    -- AUTO FIRE TWEAK (START on held)
    if pressed_type == capabilities.button.button.held and custom_features.autofire_enabled(device, button_name) then
      custom_button_utils.autofire_start(device, button_name, pressed_type, device.preferences.autofireDelay, device.preferences.autofireMaxLoops)
    end

    custom_button_utils.emit_button_event(device, button_name, pressed_type)
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
        local supported_pressed_types = {"pushed", "held", "double"} -- default
        custom_features.may_insert_multitap_types(supported_pressed_types, device, component.id)
        custom_features.may_insert_exposed_release_type(supported_pressed_types, device, component.id)
        device:emit_component_event(component, capabilities.button.supportedButtonValues(supported_pressed_types), {visibility = { displayed = false }})
    end
  end 
end

local shortcut_button = {
  NAME = "SOMRIG shortcut button",
  zigbee_handlers = {
    cluster = {
      [0xFC80] = { 
        [0x01] = build_somrig_button_handler(capabilities.button.button.pushed, true),
        [0x03] = build_somrig_button_handler(capabilities.button.button.pushed, false),
        [0x02] = build_somrig_button_handler(capabilities.button.button.held, false),
        [0x06] = build_somrig_button_handler(capabilities.button.button.double, false),
        [0x04] = build_somrig_button_handler(capabilities.button.button.up, false)
      }
    }
  },
  lifecycle_handlers = {
    infoChanged = info_changed
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "SOMRIG shortcut button"
  end
}

return shortcut_button
