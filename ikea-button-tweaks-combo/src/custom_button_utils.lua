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

Functions for custom button features with no device-specific dependencies.

Generic helper functions to emit button events and build handlers.

Multi-tap emulation up to 6x using timers. Easy to use (function handle_multitap 
does most of the job). Supports buttons with native double-tap. Handles all 
the events, counts the number of taps, manages the waiting window and, finally, 
emits the type of press depending on the number of taps.

Auto-fire with configurable delay and max repetitions. Useful to repeat held events
during a long-press until it is released. Just call autofire_start on held and 
autofire_stop on release. Also useful as base to build a dimmer switch where
brightness is increased periodically while the button is held.

]]

local log = require "log"
local capabilities = require "st.capabilities"

local AUTOFIRE_TIMER = "button.autofire.timer"
local AUTOFIRE_LOOP_COUNT = "button.autofire.loop.count"
local AUTOFIRE_MAX_LOOPS = "button.autofire.loop.max"
local AUTOFIRE_DELAY = "button.autofire.delay"

local AUTOFIRE_DEFAULT_DELAY = 1 -- seconds
local AUTOFIRE_DEFAULT_MAX_LOOPS = 10

local MULTITAP_PUSH_COUNT_PREFIX = "button.multitap.push.count."
local MULTITAP_TIMER_PREFIX = "button.multitap.current.timer."
local MULTITAP_TYPES =
   {capabilities.button.button.pushed, capabilities.button.button.double, 
    capabilities.button.button.pushed_3x, capabilities.button.button.pushed_4x, 
    capabilities.button.button.pushed_5x, capabilities.button.button.pushed_6x}
local MULTITAP_DEFAULT_DELAY_SEC = 0.5
local MULTITAP_DEFAULT_MAX_PRESSES = 2

local EXPOSED_RELEASE_LAST_HELD = "button.exposedrelease.held.last"
local EXPOSED_RELEASE_TYPE = capabilities.button.button.up

local custom_button_utils = {}


-- GENERIC BUTTON EVENT EMITTER

-- Emitting code extracted to a function for reuse in custom
-- button handlers where the button_name is unknown in advance
-- If skip_main is not nil, will not emit the event for main (used for some tweaks)
custom_button_utils.emit_button_event = function(device, button_name, pressed_type, skip_main)
  local event = pressed_type({state_change = true})
  local comp = device.profile.components[button_name]
  if comp then
    device:emit_component_event(comp, event)
    if button_name ~= "main" and not skip_main then
      device:emit_event(event)
    end
  else
    log.warn("Tried to emit button pressed event for unknown component: " .. button_name)
  end
end

-- GENERIC BUTTON HANDLER

custom_button_utils.build_button_handler = function(button_name, pressed_type)
  return function(driver, device, zb_rx)
    custom_button_utils.emit_button_event(device, button_name, pressed_type)
  end
end

-- MULTI-TAP EMULATION

-- Called by the timer
local function multitap_callback(device, button_name)
  return function()
    -- Timeout! No button was pushed during the waiting period, otherwise the timer would be canceled
    local counter_key = MULTITAP_PUSH_COUNT_PREFIX .. button_name
    local timer_key = MULTITAP_TIMER_PREFIX .. button_name
    local push_count = device:get_field(counter_key)
    if push_count then
      custom_button_utils.emit_button_event(device, button_name, MULTITAP_TYPES[push_count])
      -- Clean things up
      device:set_field(counter_key, nil)
      device:set_field(timer_key, nil)
    end
  end
end

--[[
 Handles native single/double presses to emulate a extended multi-tap.
 
 Should be called only if the user enabled multi-tap for button_name.

 Params multitap_max_pressed (longest sequence supported, up to 6x which is SmartThings max) and 
 multitap_window_millis (waiting time for next tap) are meant to directly pass the device.preferences 
 set by the user, except for buttons with native double-tap, where the developer should set a window according
 to the native window of the double-tap feature.
]]
custom_button_utils.handle_multitap = function(device, button_name, pressed_type, multitap_max_presses, multitap_window_millis)
  if not (pressed_type == capabilities.button.button.pushed or pressed_type == capabilities.button.button.double) then
    return false
  end

  local counter_key = MULTITAP_PUSH_COUNT_PREFIX .. button_name
  local timer_key = MULTITAP_TIMER_PREFIX .. button_name

  local delay = multitap_window_millis and multitap_window_millis / 1000 or MULTITAP_DEFAULT_DELAY_SEC
  local max_presses = multitap_max_presses and multitap_max_presses or MULTITAP_DEFAULT_MAX_PRESSES

  local timer = device:get_field(timer_key)

  if timer == nil then
    -- It's the first press, let's start the timer to wait for more!
    local initial_count = pressed_type == capabilities.button.button.pushed and 1 or 2
    device:set_field(counter_key, initial_count)
    timer = device.thread:call_with_delay(delay, multitap_callback(device, button_name))
    device:set_field(timer_key, timer)
    if timer == nil then
      log.error("Multi-tap timer cannot start, triggering single-tap instead")
      custom_button_utils.emit_button_event(device, button_name, pressed_type)
    end
  else
    -- We are in a multi-tap sequence and received another tap during the waiting time
    device.thread:cancel_timer(timer)
    local push_count = device:get_field(counter_key)
    local added_count = pressed_type == capabilities.button.button.pushed and 1 or 2
    local updated_count = push_count + added_count

    -- Check if we reached max multi-tap length to trigger now or keep waiting
    -- Note that with buttons with native double-taps it is possible to exceed it
    -- (e.g. max_presses is 3 but received two double-presses, updated_count would be 4)
    if updated_count >= max_presses then
      -- We're finished here
      custom_button_utils.emit_button_event(device, button_name, MULTITAP_TYPES[max_presses])
      -- Clean things up for the next sequence
      device:set_field(counter_key, nil)
      device:set_field(timer_key, nil)
    else
      -- Wait for more taps
      device:set_field(counter_key, updated_count)
      timer = device.thread:call_with_delay(delay, multitap_callback(device, button_name))
      device:set_field(timer_key, timer)
    end
  end
  return true
end  

-- For buttons with native double-tap that notify the first-press so the algorithm knows 
-- that a press might come next. It resets the window if there is a hint of a potential push (the first press).
-- Allows shorter waiting windows and minimizes delays, not having to wait for a single/double tap that will not arrive.
custom_button_utils.multitap_first_press_hint = function(device, button_name, multitap_window_millis)
  local timer_key = MULTITAP_TIMER_PREFIX .. button_name
  local timer = device:get_field(timer_key)
  if not timer then
    return -- no window to reset
  end
  device.thread:cancel_timer(timer)
  local delay = multitap_window_millis and multitap_window_millis / 1000 or MULTITAP_DEFAULT_DELAY_SEC
  timer = device.thread:call_with_delay(delay, multitap_callback(device, button_name))
  device:set_field(timer_key, timer)
end

-- AUTO-FIRE EMULATION

custom_button_utils.autofire_stop = function(device)
  local timer = device:get_field(AUTOFIRE_TIMER)
  if timer then
    log.debug("[Autofire] Stop")
    device.thread:cancel_timer(timer)
    device:set_field(AUTOFIRE_TIMER, nil)
    device:set_field(AUTOFIRE_LOOP_COUNT, nil)
  end
end

local function autofire_callback(device, button_name, pressed_type)
  return function()
    custom_button_utils.emit_button_event(device, button_name, pressed_type)

    -- Should we retrigger the timer?
    local previous_loop_count = device:get_field(AUTOFIRE_LOOP_COUNT) and device:get_field(AUTOFIRE_LOOP_COUNT) or 0
    local max_loops =  device:get_field(AUTOFIRE_MAX_LOOPS) and device:get_field(AUTOFIRE_MAX_LOOPS) or 1
    local delay =  device:get_field(AUTOFIRE_DELAY) and device:get_field(AUTOFIRE_DELAY) or AUTOFIRE_DEFAULT_DELAY

    local updated_loop_count = previous_loop_count + 1
    device:set_field(AUTOFIRE_LOOP_COUNT, updated_loop_count)
    log.debug("[Autofire] Loop " .. updated_loop_count .. "/" .. max_loops)

    if updated_loop_count < max_loops then
      -- Start next timer
      timer = device.thread:call_with_delay(delay, autofire_callback(device, button_name, pressed_type))
      device:set_field(AUTOFIRE_TIMER, timer)       
    else
      -- Finished
      custom_button_utils.autofire_stop(device)
    end

  end
end

custom_button_utils.autofire_start = function(device, button_name, pressed_type, autofire_delay_millis, autofire_max_loops)
  -- Should there be a running timer, stop it first
  custom_button_utils.autofire_stop(device)

  -- Create the timer, one-shot only, callback will create another one if needed
  local delay = autofire_delay_millis and (autofire_delay_millis / 1000) or AUTOFIRE_DEFAULT_DELAY
  local max_loops = autofire_max_loops and autofire_max_loops or AUTOFIRE_DEFAULT_MAX_LOOPS
  timer = device.thread:call_with_delay(delay, autofire_callback(device, button_name, pressed_type))
  device:set_field(AUTOFIRE_TIMER, timer)   
  device:set_field(AUTOFIRE_LOOP_COUNT, 0)     
  device:set_field(AUTOFIRE_MAX_LOOPS, max_loops)     
  device:set_field(AUTOFIRE_DELAY, delay)     
end

-- EXPOSE RELEASE AFTER HELD TWEAK

-- Keeps track of last known held button
custom_button_utils.expose_release_register_held = function(device, button_name, pressed_type)
  if pressed_type == capabilities.button.button.held then
    device:set_field(EXPOSED_RELEASE_LAST_HELD, button_name)
  end
end

-- Emits a release event for the last known held button
custom_button_utils.expose_release_emit_release = function(device)
  local last_held = device:get_field(EXPOSED_RELEASE_LAST_HELD) and device:get_field(EXPOSED_RELEASE_LAST_HELD) or "main"
  custom_button_utils.emit_button_event(device, last_held, EXPOSED_RELEASE_TYPE)
end

return custom_button_utils
