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

Detects 'ghost' events that are not actual taps and have been observed 
after a 0x04 (release event), possibly due to bad debouncing.

]]

local capabilities = require "st.capabilities"
local custom_button_utils = require "custom_button_utils"
local custom_features = require "custom_features"
local log = require "log"

local MULTITAP_SOMRIG_FIRST_PRESS_WINDOW_MILLIS = 900 -- SOMRIG takes ~700-800ms to notify a pushed/double after first_press
local MULTITAP_SOMRIG_WINDOW_MILLIS = 1000 -- time to wait after a pushed/double event for the next first_press

local GHOSTBUSTER_HINT_PREFIX = "ghostbuster.hint."
local GHOSTBUSTER_TIME_PREFIX = "ghostbuster.time."

local BUTTON_1 = "button1"
local BUTTON_2 = "button2"

--[[
  SOMRIG uses a custom cluster where the source endpoint determines the button.
  Pressed types 'down' and 'up' signal initial press and release after held. 
  When a 'down' is received the button is pressed but the final type (pushed/double/held) is not 
  known yet. In that case, the fast tap tweak will emit a pushed without waiting to confirm the 
  type, avoiding the ~1 second wait for a potential double-tap.
]]
local function build_somrig_button_handler(pressed_type)
  return function(driver, device, zb_rx)
    local button_number = zb_rx.address_header.src_endpoint.value
    local button_name = button_number == 1 and BUTTON_1 or BUTTON_2
    local first_press = pressed_type == capabilities.button.button.down

    -- AUTO-FIRE TWEAK (STOP on release)
    --'up' means a hold release, always stop the autofire
    if pressed_type == capabilities.button.button.up then
      custom_button_utils.autofire_stop(device)
    end

    local has_multitap = custom_features.multitap_enabled(device, button_name)
    if has_multitap and first_press then
      custom_button_utils.multitap_first_press_hint(device, button_name, MULTITAP_SOMRIG_FIRST_PRESS_WINDOW_MILLIS)
    end

    -- GHOSTBUSTER tweak
    -- Somrig might send ghost tap events after a long press following the release
    -- due to a bad debouncing mechanism. Actual taps follow a first-press, which the firmware skips too.
    -- The strategy: store the last hint received (the release or first-press event) and its timestamp. 
    -- When a tap is received, check it was not a recent release.

    local hint_key = GHOSTBUSTER_HINT_PREFIX .. button_name
    local time_key = GHOSTBUSTER_TIME_PREFIX .. button_name
    local hint = pressed_type == capabilities.button.button.up or pressed_type == capabilities.button.button.down
    local tap = pressed_type == capabilities.button.button.pushed or pressed_type == capabilities.button.button.double

    if hint then
      device:set_field(hint_key, pressed_type)
      device:set_field(time_key, os.time())
    end

    if tap then 
      local last_hint = device:get_field(hint_key)
      local last_time = device:get_field(time_key)
      
      local elapsed = last_time and os.difftime(os.time(), last_time) or -1

      if last_hint == capabilities.button.button.up and elapsed >= 0 and elapsed <= 1 then
        log.debug("Ghost event suppressed")
        return -- ignore ghost
      end
    end


    -- EXPOSE RELEASE TWEAK
    if pressed_type == capabilities.button.button.up and not device.preferences.exposeReleaseActions then
      return -- ignore the event, not exposed
    end

    -- FAST TAP TWEAK
    -- When not enabled for a button, the initial press event is ignored (default behaviour)
    -- When enabled, the button triggers on the initial event and further (non initial) events are ignored
    local fast_tap = custom_features.fast_tap_enabled(device, button_name)
    if first_press and fast_tap then
      custom_button_utils.emit_button_event(device, button_name, capabilities.button.button.pushed)
      return -- Trigger on first press
    elseif first_press and not fast_tap then
      return -- Ignore first press because fast tap is disabled
    elseif not first_press and fast_tap then
      return -- Ignore, already triggered on first press
    end

    -- MULTI-TAP TWEAK
    if has_multitap and (pressed_type == capabilities.button.button.pushed or pressed_type == capabilities.button.button.double) then
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
  or (args.old_st_store.preferences.fastTapButton1 ~= device.preferences.fastTapButton1)
  or (args.old_st_store.preferences.fastTapButton2 ~= device.preferences.fastTapButton2)

  if needs_press_type_change then
    custom_features.update_pressed_types(device)
  end 
end

local shortcut_button = {
  NAME = "SOMRIG shortcut button",
  zigbee_handlers = {
    cluster = {
      [0xFC80] = { 
        [0x01] = build_somrig_button_handler(capabilities.button.button.down), -- first-press
        [0x03] = build_somrig_button_handler(capabilities.button.button.pushed),
        [0x02] = build_somrig_button_handler(capabilities.button.button.held),
        [0x06] = build_somrig_button_handler(capabilities.button.button.double),
        [0x04] = build_somrig_button_handler(capabilities.button.button.up) -- released after held
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
