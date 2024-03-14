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

]]

local capabilities = require "st.capabilities"
local custom_button_utils = require "custom_button_utils"
local custom_features = require "custom_features"
local log = require "log"

ButtonNames = {
  PLAY = "play",
  PREV = "prev",
  NEXT = "next",
  PLUS = "plus",
  MINUS = "minus"
  ONE_DOT = "dot1",
  TWO_DOTS = "dot2"
}

local function symfonisk_plus_minus_handler(pressed_type)
  return function(driver, device, zb_rx)
    -- Like the TRADFRI remote, the arrow events carry the button pressed in the payload
    local payload_id = zb_rx.body.zcl_body.body_bytes:byte(1)
    
    -- It is only an actual press if the payload is 0x00 or 0x01
    -- Ignoring others just in case happens like in STYRBAR
    local button_name
    if payload_id == 0x00 then
      button_name = ButtonNames.PLUS
    elseif payload_id == 0x01 then
      button_name = ButtonNames.MINUS
    else
      return -- ignore it, not an actual press
    end

     -- Plus/Minus was pushed or held
    custom_button_utils.emit_button_event(device, button_name, pressed_type)
  end
end

local function symfonisk_prev_next_handler(pressed_type)
  return function(driver, device, zb_rx)
    local payload_id = zb_rx.body.zcl_body.body_bytes:byte(1)
   
    -- It is only an actual press if the payload is 0x00 or 0x01
    -- Ignoring others just in case happens like in STYRBAR
    local button_name
    if payload_id == 0x00 then
      button_name = ButtonNames.NEXT
    elseif payload_id == 0x01 then
      button_name = ButtonNames.PREV
    else
      return -- ignore it, not an actual press
    end

     -- Next/Prev was pushed or held
    custom_button_utils.emit_button_event(device, button_name, pressed_type)
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


local function symfonisk_dots_v2_handler(pressed_type)
  return function(driver, device, zb_rx)
    local ep = zb_rx.address_header.src_endpoint.value
    local button_name = ep == 2 and ButtonNames.ONE_DOT or ButtonNames.TWO_DOTS

    if pressed_type == capabilities.button.button.down
        or pressed_type == capabilities.button.button.up then
      -- ignoring them for now
     return
    end

    custom_button_utils.emit_button_event(device, button_name, pressed_type)
  end
end


local symfonisk_gen2 = {
  NAME = "SYMFONISK sound remote gen2",
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [0x02] = custom_button_utils.build_button_handler(ButtonNames.PLAY, capabilities.button.button.pushed),
      },
      [Level.ID] = {
        [0x01] = symfonisk_plus_minus_handler(capabilities.button.button.held),
        [0x02] = symfonisk_prev_next_handler(capabilities.button.button.pushed),
        [0x05] = symfonisk_plus_minus_handler(capabilities.button.button.pushed)
      },
      [0xFC7F] = {
        [0x01] = symfonisk_dots_v1_handler()
      },
      [0xFC80] = { 
        [0x01] = symfonisk_dots_v2_handler(capabilities.button.button.down),
        [0x03] = symfonisk_dots_v2_handler(capabilities.button.button.pushed),
        [0x02] = symfonisk_dots_v2_handler(capabilities.button.button.held),
        [0x06] = symfonisk_dots_v2_handler(capabilities.button.button.double),
        [0x04] = symfonisk_dots_v2_handler(capabilities.button.button.up)
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "SYMFONISK sound remote gen2"
  end
}

return symfonisk_gen2
