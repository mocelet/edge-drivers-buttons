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

Custom handling of long-pressed arrows and ghost "ON pushed" suppression, see
https://community.smartthings.com/t/edge-ikea-styrbar-button-edge-driver-fw-2-4-5-compatible-full-arrow-support/279296

Setting to fix battery reporting in old versions where full battery was not the standard 200 but 100.

AnyArrow component for fast held arrows when you don't mind which one.

Toggled-Up support to expose a release after long-press.

Multitap support for up to 6x.

Auto-fire on hold.

]]


local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local custom_button_utils = require "custom_button_utils"
local custom_features = require "custom_features"
local utils = require 'st.utils'
local log = require "log"

local Level = clusters.Level
local OnOff = clusters.OnOff
local Scenes = clusters.Scenes
local PowerConfiguration = clusters.PowerConfiguration

ButtonNames = {
  ON = "Top",
  OFF = "Bottom",
  PREV = "Left",
  NEXT = "Right",
  ANY_ARROW = "AnyArrow" -- special component for the tweak
}



-- MULTITAP TWEAK
-- Note the Styrbar also needs some multitap code in the styrbar_button_handler_with_ghost_suppression for top
-- Also in styrbar_scenes_button_handler for left/right
-- It's not as easy as in other buttons where you just replace the handler

local function multitap_button_handler(button_name, pressed_type)
  return function(driver, device, zb_rx)
    if not custom_features.multitap_enabled(device, button_name) then
      custom_button_utils.emit_button_event(device, button_name, pressed_type)
      return
    end
    custom_button_utils.handle_multitap(device, button_name, pressed_type, device.preferences.multiTapMaxPresses, device.preferences.multiTapDelayMillis)
  end
end

--[[
  The STYRBAR prev/next held is weird since it also sends a ON event -the ghost- but we do not want to
  trigger ON pressed when long pressing arrow buttons so a suppression mechanism is in place.

  From https://github.com/Koenkk/zigbee-herdsman-converters/blob/master/src/devices/ikea.ts#L221C4-L222C58
  The STYRBAR sends an on +- 500ms after the arrow release. We don't want to send the ON action in this case.
  https://github.com/Koenkk/zigbee2mqtt/issues/13335
  
  This is also explained here: https://github.com/dan-danache/hubitat/blob/main/ikea-zigbee-drivers/E2002.groovy,
  search for "Holding the PREV and NEXT buttons works in a weird way"

  The strategy is storing the timestamp of the event that precedes the ghost and then check the elapsed time
  before triggering ON pushed should it be a ghost.
--]]

local PRE_GHOST_EVENT_TIME = "styrbar.time.preghost"
local IGNORE_GHOST_THRESHOLD = 0.7 -- 700ms (taken from Herdsman converter)
local lua_socket = require "socket" -- Just to use gettime() which is more accurate

-- Handles Scenes 0x09 command (comes before the ghost)
local function styrbar_begin_held_handler(pressed_type)
  return function(driver, device, zb_rx)
    -- I believe analyzing traces that the preghost always has all zeros body.
    -- There are other 0x09 commands with non zero bodies to signal the end of the long press
    
    local payload = zb_rx.body.zcl_body.body_bytes
    for i = 1, #payload do
      if payload:byte(i) ~= 0 then
        --log.debug("Ignoring not zeros")
        return -- ignore, not all zeros
      end
    end
        
    --log.debug("All zeros!!")

    device:set_field(PRE_GHOST_EVENT_TIME, lua_socket.gettime())        
    -- Here we know an arrow was held, but not which one, it takes 2 seconds to know!
    -- The AnyArrow tweak will trigger the held action right now to save time
    custom_button_utils.emit_button_event(device, ButtonNames.ANY_ARROW, pressed_type)
  end
end

-- Handles OnOff On command
local function styrbar_button_handler_with_ghost_suppression(button_name, pressed_type)
  return function(driver, device, zb_rx)
    local pre_ghost_time = device:get_field(PRE_GHOST_EVENT_TIME)
    if pre_ghost_time then
      local elapsed = lua_socket.gettime() - pre_ghost_time
      if elapsed > 0 and elapsed < IGNORE_GHOST_THRESHOLD then
        return -- it's the ghost, ignore!
      end
    end
    -- Not a ghost, proceed normally
    if custom_features.multitap_enabled(device, button_name) then
      custom_button_utils.handle_multitap(device, button_name, pressed_type, device.preferences.multiTapMaxPresses, device.preferences.multiTapDelayMillis)  
      return -- processed
    end

    -- Not multitap
    custom_button_utils.emit_button_event(device, button_name, pressed_type)
  end
end

-- Handles Scenes 0x07 (push) and 0x08 (held) commands (prev/next)
local function styrbar_scenes_button_handler(pressed_type)
  return function(driver, device, zb_rx)
    -- Like the TRADFRI remote, the arrow events carry the button pressed in the payload
    local payload_id = zb_rx.body.zcl_body.body_bytes:byte(1)
    
    -- It is only an actual press if the payload is 0x00 or 0x01
    -- as learned at https://community.smartthings.com/t/ikea-styrbar-remote/235036/84
    -- Looks like a very long press will trigger a 0x02
    local button_name
    if payload_id == 0x00 then
      button_name = ButtonNames.NEXT
    elseif payload_id == 0x01 then
      button_name = ButtonNames.PREV
    else
      return -- ignore it, not an actual press
    end
    -- A known arrow was pressed or held

    if pressed_type == capabilities.button.button.pushed and custom_features.multitap_enabled(device, button_name) then
      custom_button_utils.handle_multitap(device, button_name, pressed_type, device.preferences.multiTapMaxPresses, device.preferences.multiTapDelayMillis)  
      -- TODO And what do we do with the AnyArrow OMG, just tell that it will not receive events other than held. Guess that is fine
      -- We could just remove the action if multitap is enabled
      return -- processed
    end

    custom_button_utils.emit_button_event(device, button_name, pressed_type)

    -- The any arrow held event was triggered back when we didn't know which arrow
    if pressed_type ~= capabilities.button.button.held then
      custom_button_utils.emit_button_event(device, ButtonNames.ANY_ARROW, pressed_type)
    end
  end
end

local battery_perc_attr_handler = function(driver, device, value, zb_rx)
  -- New STYRBAR firmwares report double the percentage as per standard (200 means full).
  -- Old versions do not, users can set a preference to account for it

  local is_old_firmware = device.preferences.isOldFirmware
  local corrected_value
  if is_old_firmware then
    corrected_value = value.value
  else
    corrected_value = utils.round(value.value / 2)
  end
  -- Note that percentage can be 255 when unknown and that value is reported by styrbar too
  local percentage = utils.clamp_value(corrected_value, 0, 100)
  device:emit_event(capabilities.battery.battery(percentage))
end

-- Handles button release, I'm not confident about the events so will only update main like in RODRET
local function released_button_handler(pressed_type)
  return function(driver, device, zb_rx)
    -- Always stop autofire on release
    custom_button_utils.autofire_stop(device)

    if device.preferences.exposeReleaseActions then
      custom_button_utils.emit_button_event(device, "main", pressed_type)
    end
  end
end

local function info_changed(driver, device, event, args)
  local needs_press_type_change = 
    (args.old_st_store.preferences.exposeReleaseActions ~= device.preferences.exposeReleaseActions)
    or (args.old_st_store.preferences.multiTapEnabledOn ~= device.preferences.multiTapEnabledOn)
    or (args.old_st_store.preferences.multiTapEnabledOff ~= device.preferences.multiTapEnabledOff)
    or (args.old_st_store.preferences.multiTapEnabledPrev ~= device.preferences.multiTapEnabledPrev)
    or (args.old_st_store.preferences.multiTapEnabledNext ~= device.preferences.multiTapEnabledNext)
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
  NAME = "Remote Control N2",
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = multitap_button_handler(ButtonNames.OFF, capabilities.button.button.pushed),
        [OnOff.server.commands.On.ID] = styrbar_button_handler_with_ghost_suppression(ButtonNames.ON, capabilities.button.button.pushed)
      },
      [Level.ID] = {
        [Level.server.commands.Move.ID] = autofire_button_handler(ButtonNames.OFF, capabilities.button.button.held),
        [Level.server.commands.MoveWithOnOff.ID] = autofire_button_handler(ButtonNames.ON, capabilities.button.button.held),
        [Level.server.commands.Stop.ID] = released_button_handler(capabilities.button.button.up),
        [Level.server.commands.StopWithOnOff.ID] = released_button_handler(capabilities.button.button.up)
      },
      [Scenes.ID] = {
        [0x07] = styrbar_scenes_button_handler(capabilities.button.button.pushed), -- prev/next
        [0x08] = styrbar_scenes_button_handler(capabilities.button.button.held), -- prev/next
        [0x09] = styrbar_begin_held_handler(capabilities.button.button.held) -- button unknown
      }
    },
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_perc_attr_handler
      }
    }
  },
  lifecycle_handlers = {
    infoChanged = info_changed
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "Remote Control N2"
  end
}

return on_off_switch
