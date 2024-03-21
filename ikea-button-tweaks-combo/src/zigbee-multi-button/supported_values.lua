-- Copyright 2022 SmartThings
--
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

-- mocelet 2024
-- tweaks: removed all and added supported ones

local devices = {
  BUTTON_PUSH_HELD_2 = {
    MATCHING_MATRIX = {
      { mfr = "IKEA of Sweden", model = "RODRET Dimmer" },
      { mfr = "IKEA of Sweden", model = "TRADFRI on/off switch" }
      },
    SUPPORTED_BUTTON_VALUES = { "pushed", "held"},
    NUMBER_OF_BUTTONS = 2
  },
  BUTTON_PUSH_HELD_DOUBLE_2 = {
    MATCHING_MATRIX = {
      { mfr = "IKEA of Sweden", model = "SOMRIG shortcut button" }
    },
    SUPPORTED_BUTTON_VALUES = { "pushed", "held", "double" },
    NUMBER_OF_BUTTONS = 2
  },
  BUTTON_PUSH_HELD_5 = {
    MATCHING_MATRIX = {
      { mfr = "IKEA of Sweden", model = "Remote Control N2" },
      { mfr = "IKEA of Sweden", model = "TRADFRI remote control" }
    },
    SUPPORTED_BUTTON_VALUES = { "pushed", "held" },
    NUMBER_OF_BUTTONS = 5 -- five includes the Any Arrow tweak for STYRBAR
  },
  BUTTON_PUSH_HELD_7 = {
    MATCHING_MATRIX = {
      { mfr = "IKEA of Sweden", model = "SYMFONISK sound remote gen2" }
    },
    SUPPORTED_BUTTON_VALUES = { "pushed", "held" }, -- note: custom added_handler needed
    NUMBER_OF_BUTTONS = 7
  }
}

local configs = {}

configs.get_device_parameters = function(zb_device)
  for _, device in pairs(devices) do
    for _, fingerprint in pairs(device.MATCHING_MATRIX) do
      if zb_device:get_manufacturer() == fingerprint.mfr and zb_device:get_model() == fingerprint.model then
        return device
      end
    end
  end
  return nil
end

return configs
