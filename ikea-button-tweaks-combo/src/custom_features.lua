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
 
  Configuration file for the original custom tweaks like exposed release after hold,
  multi-tap emulation or events auto-fire. Should be edited when adding custom tweaks to new 
  devices.

  Includes helper functions to populate the supported pressed types depending on
  the enabled features (may_insert_xxx).

]]

local MULTITAP_ALL_TYPES_ID = {"pushed", "double", "pushed_3x", "pushed_4x", "pushed_5x", "pushed_6x"}    
local EXPOSED_RELEASE_TYPE_ID = "up"

local RODRET = "RODRET Dimmer"
local SOMRIG = "SOMRIG shortcut button"
local STYRBAR = "Remote Control N2"
local SYMFONISK_GEN2 = "SYMFONISK sound remote gen2"

local custom_features = {}

-- DEVICE-SPECIFIC CONFIGURATION

function custom_features.multitap_enabled(device, button_name)
  local model = device:get_model()
    
  if model == RODRET or model == SOMRIG then
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
  -- For STYRBAR Toggled-Up is only exposed to main, Top and Bottom components
  if model == STYRBAR then
    return device.preferences.exposeReleaseActions and (button_name == nil or button_name == "main" or button_name == "Top" or button_name == "Bottom")
  end
  -- For RODRET and SOMRIG it's exposed to all buttons
  if model == RODRET or model == SOMRIG then
    return device.preferences.exposeReleaseActions
  end

  return false -- not supported
end
   
function custom_features.multitap_max_presses(device)
  return device.preferences.multiTapMaxPresses and device.preferences.multiTapMaxPresses or 2
end


function custom_features.autofire_enabled(device, button_name)
  local model = device:get_model()
    
  if model == RODRET or model == SOMRIG then
    return button_name == "button1" and device.preferences.autofireEnabledB1 or button_name == "button2" and device.preferences.autofireEnabledB2
  end
  
  if model == STYRBAR then
    return button_name == "Top" and device.preferences.autofireEnabledOn or button_name == "Bottom" and device.preferences.autofireEnabledOff
  end

  return false -- not supported
end


-- HELPER FUNCTIONS --

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

return custom_features
