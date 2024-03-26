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

Adapted from other subdrivers to support the old 5 buttons TRADFRI remote 
and add all the features like Toggled-Up, multi-tap and auto-fire.

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

-- Button IDs are the same of the stock driver on purpose so people can switch
-- to this driver preserving automations.

local ButtonNames = {
  TOGGLE = "button5",
  TOP = "button1",
  BOTTOM = "button3",
  NEXT = "button2",
  PREV = "button4"
}


-- Handles Scenes 0x07 (push) and 0x08 (held) commands (prev/next)
local function tradfri_scenes_button_handler(pressed_type)
  return function(driver, device, zb_rx)
    local payload_id = zb_rx.body.zcl_body.body_bytes:byte(1)
    local button_name
    if payload_id == 0x00 then
      button_name = ButtonNames.NEXT
    elseif payload_id == 0x01 then
      button_name = ButtonNames.PREV
    else
      return -- ignore it, not an actual press
    end
  
    if pressed_type == capabilities.button.button.pushed and custom_features.multitap_enabled(device, button_name) then
      custom_button_utils.handle_multitap(device, button_name, pressed_type, device.preferences.multiTapMaxPresses, device.preferences.multiTapDelayMillis)  
    else
      custom_button_utils.emit_button_event(device, button_name, pressed_type)
    end
  end
end

-- Handles button release, I'm not confident about the events so will only update main like in RODRET
local function released_button_handler(pressed_type)
  return function(driver, device, zb_rx)
    -- Always stop autofire on release
    custom_button_utils.autofire_stop(device)

    -- Expose release tweak
    if custom_features.expose_release_enabled(device) then
      custom_button_utils.expose_release_emit_release(device)
    end
  end
end

local function info_changed(driver, device, event, args)
  local needs_press_type_change = 
    (args.old_st_store.preferences.exposeReleaseActions ~= device.preferences.exposeReleaseActions)
    or (args.old_st_store.preferences.multiTapEnabledToggle ~= device.preferences.multiTapEnabledToggle)
    or (args.old_st_store.preferences.multiTapEnabledPlusMinus ~= device.preferences.multiTapEnabledPlusMinus)
    or (args.old_st_store.preferences.multiTapEnabledPrevNext ~= device.preferences.multiTapEnabledPrevNext)

  if needs_press_type_change then
    custom_features.update_pressed_types(device)
  end 
end


local function held_button_handler(button_name, pressed_type)
  return function(driver, device, zb_rx)
    -- Store it for the toggled-up tweak
    custom_button_utils.expose_release_register_held(device, button_name, pressed_type)

    -- Held event is always sent, with autofire or not
    custom_button_utils.emit_button_event(device, button_name, pressed_type)

    -- If autofire custom tweak is enabled it will repeat the event automatically
    if custom_features.autofire_enabled(device, button_name) then
      custom_button_utils.autofire_start(device, button_name, pressed_type, device.preferences.autofireDelay, device.preferences.autofireMaxLoops)
    end
  end
end

-- MULTITAP TWEAK
-- Note the Styrbar also needs some multitap code in the styrbar_button_handler_with_ghost_suppression for top
-- Also in styrbar_scenes_button_handler for left/right
-- It's not as easy as in other buttons where you just replace a common handler

local function multitap_button_handler(button_name, pressed_type)
  return function(driver, device, zb_rx)
    if custom_features.multitap_enabled(device, button_name) then
      custom_button_utils.handle_multitap(device, button_name, pressed_type, device.preferences.multiTapMaxPresses, device.preferences.multiTapDelayMillis)
    else
      custom_button_utils.emit_button_event(device, button_name, pressed_type)
    end
  end
end

local tradfri_remote = {
  NAME = "Remote Control N2",
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Toggle.ID] = multitap_button_handler(ButtonNames.TOGGLE, capabilities.button.button.pushed)
      },
      [Level.ID] = {
        [Level.server.commands.StepWithOnOff.ID] = multitap_button_handler(ButtonNames.TOP, capabilities.button.button.pushed),
        [Level.server.commands.Step.ID] = multitap_button_handler(ButtonNames.BOTTOM, capabilities.button.button.pushed),
        [Level.server.commands.MoveWithOnOff.ID] = held_button_handler(ButtonNames.TOP, capabilities.button.button.held),
        [Level.server.commands.Move.ID] = held_button_handler(ButtonNames.BOTTOM, capabilities.button.button.held),        
        [Level.server.commands.Stop.ID] = released_button_handler(capabilities.button.button.up),
        [Level.server.commands.StopWithOnOff.ID] = released_button_handler(capabilities.button.button.up)
      },
      [Scenes.ID] = {
        [0x07] = tradfri_scenes_button_handler(capabilities.button.button.pushed), -- prev/next
        [0x08] = tradfri_scenes_button_handler(capabilities.button.button.held), -- prev/next
      }
    },
  },
  lifecycle_handlers = {
    infoChanged = info_changed
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "TRADFRI remote control"
  end
}

return tradfri_remote
