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

--[[ mocelet 2024

Mostly the stock init.lua with custom modifications to support the new buttons

- do_configure includes specific bindings for each model.
- Fixed battery PowerConfiguration binding and reporting.
- Fixed handler for battery level battery_perc_attr_handler.
- Hooks for new expose release and multi-tap custom features in added_handler.

]]


local capabilities = require "st.capabilities"
local constants = require "st.zigbee.constants"
local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local messages = require "st.zigbee.messages"
local mgmt_bind_resp = require "st.zigbee.zdo.mgmt_bind_response"
local mgmt_bind_req = require "st.zigbee.zdo.mgmt_bind_request"
local utils = require 'st.utils'
local zdo_messages = require "st.zigbee.zdo"
local supported_values = require "zigbee-multi-button.supported_values"
local Groups = clusters.Groups
local PowerConfiguration = clusters.PowerConfiguration
local OnOff = clusters.OnOff
local Level = clusters.Level
local ENTRIES_READ = "ENTRIES_READ"
local log = require "log"

local custom_features = require "custom_features"

local RODRET = "RODRET Dimmer"
local SOMRIG = "SOMRIG shortcut button"
local STYRBAR = "Remote Control N2"
local SYMFONISK_GEN2 = "SYMFONISK sound remote gen2"

local do_configure = function(self, device)
  local model = device:get_model()
  
  -- tweaks: each model has specific bindings, did not want subdrivers to handle doConfigure lifecycle
  if model == RODRET then 
    device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
    device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))  
  elseif model == SOMRIG then
    -- Somrig has same custom cluster but different endpoints for each button
    device:send(device_management.build_bind_request(device, 0xFC80, self.environment_info.hub_zigbee_eui, 1))
    device:send(device_management.build_bind_request(device, 0xFC80, self.environment_info.hub_zigbee_eui, 2))
  elseif model == STYRBAR then
    -- Styrbar needs three bindings since firmware 2.4.5 (December 2022), should work with older versions
    device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
    device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))  
    device:send(device_management.build_bind_request(device, clusters.Scenes.ID, self.environment_info.hub_zigbee_eui))  
  elseif model == SYMFONISK_GEN2 then
    -- Looks like a mix of all the other buttons
    -- Thanks to https://github.com/dan-danache/hubitat/blob/main/ikea-zigbee-drivers/E2123.groovy
    device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
    device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui))  
    device:send(device_management.build_bind_request(device, 0xFC7F, self.environment_info.hub_zigbee_eui)) -- FW 1.0.012
    device:send(device_management.build_bind_request(device, 0xFC80, self.environment_info.hub_zigbee_eui, 2)) -- ep 2, FW 1.0.35
    device:send(device_management.build_bind_request(device, 0xFC80, self.environment_info.hub_zigbee_eui, 3)) -- ep 3 FW 1.0.35
  end
 
  -- tweaks: battery fix in RODRET inspired by Vallhorn drivers by the great Mariano (Mc)
  if model == RODRET or model == SOMRIG or model == SYMFONISK_GEN2 then
    device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui, 1):to_endpoint(1))
    device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 30, 21600, 1):to_endpoint(1))
  elseif model == STYRBAR then
    device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui, 1))
    device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(device, 30, 21600, 1))
  end

  -- Read binding table
  local addr_header = messages.AddressHeader(
    constants.HUB.ADDR,
    constants.HUB.ENDPOINT,
    device:get_short_address(),
    device.fingerprinted_endpoint_id,
    constants.ZDO_PROFILE_ID,
    mgmt_bind_req.BINDING_TABLE_REQUEST_CLUSTER_ID
  )
  local binding_table_req = mgmt_bind_req.MgmtBindRequest(0) -- Single argument of the start index to query the table
  local message_body = zdo_messages.ZdoMessageBody({
                                                   zdo_body = binding_table_req
                                                 })
  local binding_table_cmd = messages.ZigbeeMessageTx({
                                                     address_header = addr_header,
                                                     body = message_body
                                                   })
  device:send(binding_table_cmd)
end

local function added_handler(self, device)
  local config = supported_values.get_device_parameters(device)
  for _, component in pairs(device.profile.components) do
    local number_of_buttons = component.id == "main" and config.NUMBER_OF_BUTTONS or 1
    if config ~= nil then
      local supported_pressed_types = config.SUPPORTED_BUTTON_VALUES
      custom_features.may_insert_multitap_types(supported_pressed_types, device, component.id)
      custom_features.may_insert_exposed_release_type(supported_pressed_types, device, component.id)
      device:emit_component_event(component, capabilities.button.supportedButtonValues(supported_pressed_types), {visibility = { displayed = false }})   
    else
      device:emit_component_event(component, capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = { displayed = false }}))
    end
    device:emit_component_event(component, capabilities.button.numberOfButtons({value = number_of_buttons}))
  end
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  device:emit_event(capabilities.button.button.pushed({state_change = false}))
end

local function zdo_binding_table_handler(driver, device, zb_rx)
  for _, binding_table in pairs(zb_rx.body.zdo_body.binding_table_entries) do
    if binding_table.dest_addr_mode.value == binding_table.DEST_ADDR_MODE_SHORT then
      -- send add hub to zigbee group command
      driver:add_hub_to_zigbee_group(binding_table.dest_addr.value)
      return
    end
  end

  local entries_read = device:get_field(ENTRIES_READ) or 0
  entries_read = entries_read + zb_rx.body.zdo_body.binding_table_list_count.value

  -- if the device still has binding table entries we haven't read, we need
  -- to go ask for them until we've read them all
  if entries_read < zb_rx.body.zdo_body.total_binding_table_entry_count.value then
    device:set_field(ENTRIES_READ, entries_read)

    -- Read binding table
    local addr_header = messages.AddressHeader(
      constants.HUB.ADDR,
      constants.HUB.ENDPOINT,
      device:get_short_address(),
      device.fingerprinted_endpoint_id,
      constants.ZDO_PROFILE_ID,
      mgmt_bind_req.BINDING_TABLE_REQUEST_CLUSTER_ID
    )
    local binding_table_req = mgmt_bind_req.MgmtBindRequest(entries_read) -- Single argument of the start index to query the table
    local message_body = zdo_messages.ZdoMessageBody({ zdo_body = binding_table_req })
    local binding_table_cmd = messages.ZigbeeMessageTx({ address_header = addr_header, body = message_body })
    device:send(binding_table_cmd)
  else
    driver:add_hub_to_zigbee_group(0x0000) -- fallback if no binding table entries found
    device:send(Groups.commands.AddGroup(device, 0x0000))
  end
end

local battery_perc_attr_handler = function(driver, device, value, zb_rx)
  -- tweaks: rodret and somrig send double the value like the vallhorn, again Mc to the rescue
  -- styrbar uses its own handler in the subdriver
  local percentage = utils.clamp_value(utils.round(value.value / 2), 0, 100)
  device:emit_event(capabilities.battery.battery(percentage))
end

local ikea_of_sweden = {
  NAME = "IKEA Sweden",
  lifecycle_handlers = {
    doConfigure = do_configure,
    added = added_handler
  },
  zigbee_handlers = {
    zdo = {
      [mgmt_bind_resp.MGMT_BIND_RESPONSE] = zdo_binding_table_handler
    },
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_perc_attr_handler
      }
    }
  },
  sub_drivers = {
    require("zigbee-multi-button.ikea.RODRET_dimmer"),  -- tweaks: removed all, added the new handlers
    require("zigbee-multi-button.ikea.SOMRIG_shortcut"),
    require("zigbee-multi-button.ikea.STYRBAR_remote"),
    require("zigbee-multi-button.ikea.SYMFONISK_gen2")
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "IKEA of Sweden" or device:get_manufacturer() == "KE"
  end
}

return ikea_of_sweden
