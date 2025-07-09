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
 
  Configuration file for all the device features and custom tweaks like Toggled Up on release,
  multi-tap emulation, events auto-fire or fast-tap. Should be edited when adding new 
  devices.

  The stock supported_values file is no longer needed, it was not generic enough to cover buttons 
  where each button has different features and led to having to create individual lifecycle handlers.

  Includes helper functions to populate and update the supported pressed types, simplifying the
  handlers for added and infoChanged events.

]]

local capabilities = require "st.capabilities"

local MULTITAP_ALL_TYPES_ID = {"pushed", "double", "pushed_3x", "pushed_4x", "pushed_5x", "pushed_6x"}    
local EXPOSED_RELEASE_TYPE_ID = "up"

local RODRET = "RODRET Dimmer"
local RODRET_2 = "RODRET wireless dimmer" -- New fingerprint in retail boxes
local SOMRIG = "SOMRIG shortcut button"
local STYRBAR = "Remote Control N2"
local SYMFONISK_GEN2 = "SYMFONISK sound remote gen2"
local TRADFRI_ON_OFF = "TRADFRI on/off switch"
local TRADFRI_REMOTE = "TRADFRI remote control"

local custom_features = {}

-- DEVICE-SPECIFIC CONFIGURATION

-- The number of buttons of the device
function custom_features.default_button_count(device)
  local model = device:get_model()
  if model == TRADFRI_REMOTE or model == STYRBAR then
    return 5 -- Styrbar has 4 + AnyArrow custom component
  elseif model == SYMFONISK_GEN2 then
    return 7
  else
    return 2 -- default, rodret, somrig, on/off
  end
end

-- The default supported pressed types for each button of the device, not including tweaks
function custom_features.default_button_pressed_types(device, button_name)
  local model = device:get_model()
  if model == SOMRIG then
    return {"pushed", "held", "double"}
  end

  if model == SYMFONISK_GEN2 then
    if button_name == "play" or button_name == "prev" or button_name == "next" then
      return {"pushed"} -- no held
    elseif button_name == "main" or button_name == "dot1" or button_name == "dot2" then
      return {"pushed", "held", "double"} -- native double-tap in dots and so in main
    end
  end

  if model == STYRBAR and button_name == "AnyArrow" then
    return {"held"} -- Any Arrow is a tweak that only makes sense with Held
  end

  if model == TRADFRI_REMOTE and button_name == "button5" then
    return {"pushed"} -- no held in Power button
  end

  return {"pushed", "held"} -- default
end


function custom_features.multitap_enabled(device, button_name)
  local model = device:get_model()
    
  if model == RODRET or model == RODRET_2 or model == SOMRIG or model == TRADFRI_ON_OFF then
      if button_name == "main" then
        return device.preferences.multiTapEnabledB1 or device.preferences.multiTapEnabledB2
      else
        return button_name == "button1" and device.preferences.multiTapEnabledB1 or button_name == "button2" and device.preferences.multiTapEnabledB2
      end
  end
  
  if model == STYRBAR then
    if button_name == "main" then
      return device.preferences.multiTapEnabledOn 
        or device.preferences.multiTapEnabledOff 
        or device.preferences.multiTapEnabledPrev 
        or device.preferences.multiTapEnabledNext
    else
      return button_name == "Top" and device.preferences.multiTapEnabledOn 
        or button_name == "Bottom" and device.preferences.multiTapEnabledOff 
        or button_name == "Left" and device.preferences.multiTapEnabledPrev 
        or button_name == "Right" and device.preferences.multiTapEnabledNext
    end
  end
  
  if model == SYMFONISK_GEN2 then
    if button_name == "main" then
      return device.preferences.multiTapEnabledPlay
            or device.preferences.multiTapEnabledPrevNext 
            or device.preferences.multiTapEnabledPlusMinus
    else
      return button_name == "play" and device.preferences.multiTapEnabledPlay 
            or button_name == "prev" and device.preferences.multiTapEnabledPrevNext
            or button_name == "next" and device.preferences.multiTapEnabledPrevNext
            or button_name == "plus" and device.preferences.multiTapEnabledPlusMinus
            or button_name == "minus" and device.preferences.multiTapEnabledPlusMinus
    end
  end

  if model == TRADFRI_REMOTE then
    -- Arrows in TRADFRI have strong debounce, not implementing multi-tap
    if button_name == "main" then
      return device.preferences.multiTapEnabledToggle
            or device.preferences.multiTapEnabledPlusMinus
    else
      return button_name == "button5" and device.preferences.multiTapEnabledToggle 
            or button_name == "button1" and device.preferences.multiTapEnabledPlusMinus
            or button_name == "button3" and device.preferences.multiTapEnabledPlusMinus
    end
  end

  return false -- not supported
end
    
function custom_features.multitap_native_count(device, button_name)
    if device:get_model() == SYMFONISK_GEN2 then
      -- Dots have native double taps, so Main always has at least double-tap too!
      return (button_name == "main" or button_name == "dot1" or button_name == "dot2") and 2 or 1
    end
    return device:get_model() == SOMRIG and 2 or 1 -- SOMRIG has native double-tap
end

function custom_features.expose_release_enabled(device, button_name)
  local model = device:get_model()
  if model == STYRBAR then
    -- For STYRBAR Toggled-Up is only exposed to main, Top and Bottom components
    return device.preferences.exposeReleaseActions and (button_name == nil or button_name == "main" or button_name == "Top" or button_name == "Bottom")
  elseif model == TRADFRI_REMOTE then
    -- For TRADFRI Toggled-Up is only exposed to main, Top and Bottom components
    return device.preferences.exposeReleaseActions and (button_name == nil or button_name == "main" or button_name == "button1" or button_name == "button3")
  elseif model == SYMFONISK_GEN2 then
    -- For SYMFONISK Gen 2 only to the dots, but mind only new firmwares have a release event
    return device.preferences.exposeReleaseActions and (button_name == nil or button_name == "main" or button_name == "dot1" or button_name == "dot2")
  elseif model == RODRET or model == RODRET_2 or model == SOMRIG or model == TRADFRI_ON_OFF then
    -- For RODRET and SOMRIG it's exposed to all buttons
    return device.preferences.exposeReleaseActions
  end

  return false -- not supported
end
   
function custom_features.multitap_max_presses(device)
  return device.preferences.multiTapMaxPresses or 2
end


function custom_features.autofire_enabled(device, button_name)
  local model = device:get_model()
    
  if model == RODRET or model == RODRET_2 or model == SOMRIG or model == TRADFRI_ON_OFF then
    return button_name == "button1" and device.preferences.autofireEnabledB1 or button_name == "button2" and device.preferences.autofireEnabledB2
  end
  
  if model == STYRBAR then
    return button_name == "Top" and device.preferences.autofireEnabledOn or button_name == "Bottom" and device.preferences.autofireEnabledOff
  end

  if model == TRADFRI_REMOTE then
    return device.preferences.autofireEnabled and (button_name == "button1" or button_name == "button3")
  end

  return false -- not supported
end

function custom_features.fast_tap_enabled(device, button_name)
  local model = device:get_model()
  
  if model == SOMRIG then
    if button_name == "main" then
      return device.preferences.fastTapButton1 and device.preferences.fastTapButton2
    else 
      return button_name == "button1" and device.preferences.fastTapButton1 or button_name == "button2" and device.preferences.fastTapButton2
    end
  end

  if model == SYMFONISK_GEN2 then
    return device.preferences.fastTapDots and (button_name == "dot1" or button_name == "dot2")
  end

  return false
end

-- HELPER FUNCTIONS --

function custom_features.supported_pressed_types(device, button_name)
   -- Fast-Tap enabled buttons fire on first-press so they cannot have more actions than pressed
  if custom_features.fast_tap_enabled(device, button_name) then
    return {"pushed"}
  end

  local supported_pressed_types = custom_features.default_button_pressed_types(device, button_name)
  custom_features.may_insert_multitap_types(supported_pressed_types, device, button_name)
  custom_features.may_insert_exposed_release_type(supported_pressed_types, device, button_name)
  return supported_pressed_types
end

function custom_features.may_insert_multitap_types(supported_pressed_types, device, component_id)
  if custom_features.multitap_enabled(device, component_id) then
    local native_count = custom_features.multitap_native_count(device, component_id)
    local max_presses = custom_features.multitap_max_presses(device)
    for i = native_count + 1, max_presses do
      table.insert(supported_pressed_types, MULTITAP_ALL_TYPES_ID[i])
    end 
  end
end

function custom_features.may_insert_exposed_release_type(supported_pressed_types, device, component_id)
  if custom_features.expose_release_enabled(device, component_id) then
    table.insert(supported_pressed_types, EXPOSED_RELEASE_TYPE_ID)
  end
end

function custom_features.update_pressed_types(device)
  for _, component in pairs(device.profile.components) do
    local supported_pressed_types = custom_features.supported_pressed_types(device, component.id)
    device:emit_component_event(component, capabilities.button.supportedButtonValues(supported_pressed_types), {visibility = { displayed = false }})
  end
end


return custom_features
