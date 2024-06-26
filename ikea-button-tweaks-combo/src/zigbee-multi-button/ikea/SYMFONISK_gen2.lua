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

SYMFONISK gen 2

There are at least two different firmwares with different behaviour
when it comes to dots buttons (using different clusters).
The driver implements both (let's call them v1 and v2 handlers). The new
one (v2) is like the SOMRIG dot buttons. The old one (v1) uses FC7F cluster.

Helpful sources:
- Discussion about the two firmware versions (factory and new one):
  https://github.com/zigpy/zha-device-handlers/issues/2223
- Hubitat driver by Dan Danache
  https://github.com/dan-danache/hubitat/blob/main/ikea-zigbee-drivers/E2123.groovy

]]

local capabilities = require "st.capabilities"
local custom_button_utils = require "custom_button_utils"
local custom_features = require "custom_features"
local log = require "log"
local clusters = require "st.zigbee.zcl.clusters"
local Level = clusters.Level
local OnOff = clusters.OnOff
local PowerConfiguration = clusters.PowerConfiguration
local lua_socket = require "socket" -- Just to use gettime() which is more accurate

local LAST_HELD_EMIT_TIME_PREFIX = "symfonisk.held.emit.time."
local LAST_VOLUME_HELD_TIME_PREFIX = "symfonisk.volume.held.time."
local IGNORE_HELD_THRESHOLD = 1 -- Usually held events are spaced 400ms but I've seen 700ms and 800ms so 1 second

local ButtonNames = {
  PLAY = "play",
  PREV = "prev",
  NEXT = "next",
  PLUS = "plus",
  MINUS = "minus",
  ONE_DOT = "dot1",
  TWO_DOTS = "dot2"
}

-- For multitap tweak compatible buttons (all but dots), instead of sending the event checks if it's a single-tap and multitap is enabled
local function emit_button_event_multitap_hook(device, button_name, pressed_type)
  if pressed_type == capabilities.button.button.pushed and custom_features.multitap_enabled(device, button_name) then
    custom_button_utils.handle_multitap(device, button_name, pressed_type, device.preferences.multiTapMaxPresses, device.preferences.multiTapDelayMillis)
  else
    custom_button_utils.emit_button_event(device, button_name, pressed_type)
  end
end


local function symfonisk_plus_minus_handler(pressed_type)
  return function(driver, device, zb_rx)
    local move_mode = zb_rx.body.zcl_body.move_mode.value
    if move_mode == Level.types.MoveStepMode.UP then
      button_name = ButtonNames.PLUS
    elseif move_mode == Level.types.MoveStepMode.DOWN then
      button_name = ButtonNames.MINUS
    else
      return
    end
     -- Plus/Minus was pushed or held

     -- SUPPRESS REPETITION CUSTOM TWEAK
     -- It's interesting, looks like holding + or - generate a continuous
     -- stream of Held events every 400ms. Makes sense being a volume control.
     -- Adding a tweak to suppress the repetitions, they clutter the history
     -- and sometimes you want to toggle stuff with the held action, not possible
     -- if the action is repeating multiple times.

    if pressed_type == capabilities.button.button.held and device.preferences.suppressHeldRepeat then
      local time_key = LAST_VOLUME_HELD_TIME_PREFIX .. button_name
      local last_held_time = device:get_field(time_key)
      local current_held_time = lua_socket.gettime()
      device:set_field(time_key, current_held_time)        
      if last_held_time then
        local elapsed = current_held_time - last_held_time
        if elapsed > 0 and elapsed < IGNORE_HELD_THRESHOLD then
          return -- it's a repetition of the same Held event, ignore!
        end
      end
    end
  
    -- HELD EMIT RATE LIMITER TWEAK
    if pressed_type == capabilities.button.button.held then
      local now = lua_socket.gettime()
      local min_interval = device.preferences.heldMinInterval and device.preferences.heldMinInterval / 1000 or 0
      local emit_time_key = LAST_HELD_EMIT_TIME_PREFIX .. button_name
      local last_emit_time = device:get_field(emit_time_key)
      if last_emit_time then
        local elapsed = now - last_emit_time
        if elapsed > 0 and elapsed < min_interval then
          return -- ignore event to limit emit rate
        end
      end
      device:set_field(emit_time_key, now)
    end

    emit_button_event_multitap_hook(device, button_name, pressed_type)
  end
end

local function symfonisk_prev_next_handler(pressed_type)
  return function(driver, device, zb_rx)
    local step_mode = zb_rx.body.zcl_body.step_mode.value

    if step_mode == Level.types.MoveStepMode.UP  then
      button_name = ButtonNames.NEXT      
    elseif step_mode == Level.types.MoveStepMode.DOWN then
      button_name = ButtonNames.PREV
    else
      return
    end

    -- Next/Prev was pushed
    emit_button_event_multitap_hook(device, button_name, pressed_type)
  end
end


local function symfonisk_dots_v1_handler()
  return function(driver, device, zb_rx)
    local payload_b1 = zb_rx.body.zcl_body.body_bytes:byte(1)
    local payload_b2 = zb_rx.body.zcl_body.body_bytes:byte(2)
  
    local button_name = payload_b1 == 0x01 and ButtonNames.ONE_DOT or ButtonNames.TWO_DOTS
    local pressed_type = nil

    if payload_b2 == 0x01 then
      pressed_type = capabilities.button.button.pushed
    elseif payload_b2 == 0x02 then
      pressed_type = capabilities.button.button.double
    elseif payload_b2 == 0x03 then
      pressed_type = capabilities.button.button.held
    end

    if button_name and pressed_type then
      custom_button_utils.emit_button_event(device, button_name, pressed_type)
    end
  end
end


-- Handles play pushed messages, it does not support held or double
local function symfonisk_play_handler(pressed_type)
  return function(driver, device, zb_rx)
    emit_button_event_multitap_hook(device, ButtonNames.PLAY, pressed_type)
  end
end


local function symfonisk_dots_v2_handler(pressed_type)
  return function(driver, device, zb_rx)
    local ep = zb_rx.address_header.src_endpoint.value
    local button_name = ep == 2 and ButtonNames.ONE_DOT or ButtonNames.TWO_DOTS

    -- FAST-TAP TWEAK for dots, like in SOMRIG
    local first_press = pressed_type == capabilities.button.button.down
    local fast_tap = custom_features.fast_tap_enabled(device, button_name)
    if first_press and fast_tap then
      custom_button_utils.emit_button_event(device, button_name, capabilities.button.button.pushed)
      return -- Trigger on first press
    elseif first_press and not fast_tap then
      return -- Ignore first press because fast tap is disabled
    elseif not first_press and fast_tap then
      return -- Ignore, already triggered on first press
    end

    -- EXPOSE RELEASE TWEAK
    if pressed_type == capabilities.button.button.up and not device.preferences.exposeReleaseActions then
      return -- ignore release event, not exposed
    end

    custom_button_utils.emit_button_event(device, button_name, pressed_type)
  end
end

local function info_changed(driver, device, event, args)
  local needs_press_type_change = 
    (args.old_st_store.preferences.multiTapEnabledPlay ~= device.preferences.multiTapEnabledPlay)
    or (args.old_st_store.preferences.multiTapEnabledPlusMinus ~= device.preferences.multiTapEnabledPlusMinus)
    or (args.old_st_store.preferences.multiTapEnabledPrevNext ~= device.preferences.multiTapEnabledPrevNext)
    or (args.old_st_store.preferences.multiTapMaxPresses ~= device.preferences.multiTapMaxPresses)
    or (args.old_st_store.preferences.exposeReleaseActions ~= device.preferences.exposeReleaseActions)
    or (args.old_st_store.preferences.fastTapDots ~= device.preferences.fastTapDots)

  if needs_press_type_change then
    custom_features.update_pressed_types(device)
  end 
end


local symfonisk_gen2 = {
  NAME = "SYMFONISK sound remote gen2",
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Toggle.ID] = symfonisk_play_handler(capabilities.button.button.pushed)
      },
      [Level.ID] = {
        [Level.server.commands.Step.ID] = symfonisk_prev_next_handler(capabilities.button.button.pushed),
        [Level.server.commands.Move.ID] = symfonisk_plus_minus_handler(capabilities.button.button.held),
        [Level.server.commands.MoveWithOnOff.ID] = symfonisk_plus_minus_handler(capabilities.button.button.pushed)
      },
      [0xFC7F] = {
        [0x01] = symfonisk_dots_v1_handler()
      },
      [0xFC80] = { 
        [0x03] = symfonisk_dots_v2_handler(capabilities.button.button.pushed),
        [0x02] = symfonisk_dots_v2_handler(capabilities.button.button.held),
        [0x06] = symfonisk_dots_v2_handler(capabilities.button.button.double),
        [0x01] = symfonisk_dots_v2_handler(capabilities.button.button.down),
        [0x04] = symfonisk_dots_v2_handler(capabilities.button.button.up)
      }
    }
  },
  lifecycle_handlers = {
    infoChanged = info_changed
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "SYMFONISK sound remote gen2"
  end
}

return symfonisk_gen2
