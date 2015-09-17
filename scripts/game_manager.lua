-- Script that creates a game ready to be played.

-- Usage:
-- local game_manager = require("scripts/game_manager")
-- local game = game_manager:create("savegame_file_name")
-- game:start()

local game_manager = {}

-- Sets initial values for a new savegame of this quest.
local function initialize_new_savegame(game)
  game:set_starting_location("cutscenes/intro") --("root_prairie/house_old_men/house") --"levels/left") --("root_prairie/house_old_men/house") 
  -- STARTING LOCATION: "levels/" + "left", "level0", "test_level", "house_begining_outside", "cottage", "root_prairie/house_old_men/house",...
  game:set_max_money(99)
  game:set_max_life(12)
  game:set_life(game:get_max_life())
  game:get_item("rupee_bag"):set_variant(1)
  game:set_ability("swim",1)
end

-- Creates a game ready to be played.
function game_manager:create(file)
  -- Create the game (but do not start it).
  local exists = sol.game.exists(file)
  local game = sol.game.load(file)
  if not exists then
    -- This is a new savegame file.
    initialize_new_savegame(game)
  end
  
  sol.main.load_file("scripts/dialog_box.lua")(game)
  sol.main.load_file("scripts/game_over.lua")(game)
  sol.main.load_file("scripts/hero_manager/custom_interactions.lua")(game)
  sol.main.load_file("scripts/hero_manager/collision_test_manager.lua")(game)
  local hud_manager = require("scripts/hud/hud")
  local hud
  local pause_manager = require("scripts/menus/pause")
  local pause_menu
  
  local hero_manager_builder = require("scripts/hero_manager/hero_manager")
  game.save_between_maps = require("scripts/hero_manager/save_between_maps")
  game.active_maps = {}
  game.independent_entities = {}
  
  -- Function called when the player runs this game.
  function game:on_started()
    -- Prepare the dialog box menu and the HUD.
    game:initialize_dialog_box()
	  hud = hud_manager:create(game)
	  pause_menu = pause_manager:create(game, exists)
	  game.hero_manager = hero_manager_builder:create(game, exists)
    -- Configure some joypad buttons. [Change this for a menu later!]
    game:set_command_joypad_binding("action", "button 10")
    game:set_command_joypad_binding("attack", "button 11")
    game:set_command_joypad_binding("item_1", "button 12")
    game:set_command_joypad_binding("item_2", "button 13")
    -- Modify metatable of hero to make carried entities follow him with hero:on_position_changed().
    local hero_metatable = sol.main.get_metatable("hero")
    function hero_metatable:on_position_changed()
      if self.custom_carry then
        local x, y, layer = self:get_position()
        self.custom_carry:set_position(x, y+2, layer)
      end
    end
  end

  -- Function called when the game stops.  
  function game:on_finished()
    -- Clean the dialog box and the HUD.
    game:quit_dialog_box()
	  hud:quit()
	  game.hero_manager:quit()
	  --hud = nil; pause_menu = nil; game.hero_manager = nil; game.save_between_maps = nil
  end
  
  -- Function called when the game is paused.
  function game:on_paused()
    -- Start the pause menu. Tell the HUD and the hero manager we are paused. 
	  hud:on_paused()
	  game.hero_manager:on_paused()
	  if game.custom_pause_menu == nil then sol.menu.start(game, pause_menu)
	  else sol.menu.start(game, game.custom_pause_menu) end
  end   

-- Function called when the game is unpaused.
  function game:on_unpaused() 
    -- Stop the pause menu. Tell the HUD and the hero manager we are no longer paused.
	  hud:on_unpaused() 
	  game.hero_manager:on_unpaused()
	  if game.custom_pause_menu == nil then sol.menu.stop(pause_menu)	
	  else sol.menu.stop(game.custom_pause_menu) end
  end
  

  -- Function called when the player goes to another map.
  function game:on_map_changed(map)  
    -- Notify the HUD and hero manager(some HUD elements need to know that).
    hud:on_map_changed(map)
	  game.hero_manager:on_map_changed(map) -- Create npc_heroes.
	  game.save_between_maps:load_map(map) -- Create saved and carried entities.
  end

  -- After a dialog, the HUD is restarted, which gives a problem with custom_carrying_items. This solves the problem.
  -- This function is called from the event game:on_dialog_finished(), defined in the dialog_box file.
  function game:on_custom_dialog_finished()
    local hero = game:get_hero()
    if hero.custom_carry then 	
	  game:set_custom_command_effect("action", "custom_carry")
	  game:set_custom_command_effect("attack", "custom_carry")
	end
  end 

  local custom_command_effects = {}
  -- Returns the current customized effect of the action or attack command.
  -- nil means the built-in effect.
  function game:get_custom_command_effect(command)
    return custom_command_effects[command]
  end
  -- Overrides the effect of the action or attack command.
  -- Set the effect to nil to restore the built-in effect.
  function game:set_custom_command_effect(command, effect)
    custom_command_effects[command] = effect
  end
  
  -- More functions.
  function game:is_hud_enabled() return hud:is_enabled() end
  function game:set_hud_enabled(enable) return hud:set_enabled(enable) end
  function game:is_hero_manager_enabled() return game.hero_manager:is_enabled() end
  function game:set_hero_manager_enabled(enable) return game.hero_manager:set_enabled(enable) end


  function game:on_command_pressed(command)
    -- Skip function if dialog box is enabled.
    if game:is_dialog_enabled() then return false end
    -- Deal with action command.
    if command == "action" then
      if game:get_command_effect("action") == nil then
        local action_effect = game:get_custom_command_effect("action")
        -- Custom action effects.
        if action_effect and game:get_interaction_entity() then
         game:get_hero().custom_interaction:on_custom_interaction(); return true
        end
        -- Here we deal with the features "switch hero" and the hero dialog menu.
        if not game.hero_manager.enabled or game.hero_manager.dialog_enabled then return end
        if action_effect == nil or action_effect == "custom_carry" then
          -- Switch hero.
          game.hero_manager:switch_hero(); return true
        end
      else
        return false -- The engine handles the action.
      end
	  end
	  -- Deal with attack command.
	  if command == "attack" then
      local attack_effect = game:get_custom_command_effect("attack")
	    if attack_effect == "custom_carry" then
	      game:get_hero().custom_carry:throw(); return true
	    elseif attack_effect == "custom_jump" then
        return true -- Do nothing during the jump.
      end
	  end
    -- Avoid using items during custom_carry state.
	  if command == "item_1" or command == "item_2" then
      local custom_action = game:get_custom_command_effect("action")
      if custom_action == "custom_carry" or custom_action == "custom_jump" then
        return true
      end
    end

  end

 
  -- Functions for pause menus.
  function game:get_custom_pause_menu() return game.custom_pause_menu end 
  function game:set_custom_pause_menu(other_menu) game.custom_pause_menu = other_menu end


  --------------------------------------------------------------------------------------------------------------------
	 
  return game
end

return game_manager
