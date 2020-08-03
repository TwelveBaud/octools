recipes = nil

do
	local ser = require("serialization")
	local io = require("io")

	local recipe_file = io.open("/etc/slatecreate.recipes.txt")
	recipes = ser.unserialize(recipe_file:read("*a"))
	recipe_file:close()
end

guts = {}
status = {
	should_run = false,
	recipe = nil,
	state = "Stopped",
	action = nil,
	thread = nil
}

local computer = require("computer")
local thread = require("thread")
local sides = require("sides")
local component = require("component")
local tp = component.proxy(component.list("transposer")())

config = args or {}
if config.altar == nil then config.altar = sides.front end
if config.input == nil then config.input = sides.top end
if config.output == nil then config.output = sides.right end
if config.store == nil then config.store = config.input end
if config.store_slot == nil then config.store_slot = tp.getInventorySize(config.store) end
if config.input_slots == nil then
	if config.store == config.input then
		config.input_slots = config.store_slot - 1
	else
		config.input_slots = tp.getInventorySize(config.input)
	end
end
if config.output_slot == nil then config.output_slot = 1

guts.id = function(stack)
	stack = stack or {label = "Air", name = "minecraft:air", damage = 0}
	return stack.name .. "/" .. stack.damage
end

guts.find_job = function()
	if status.job ~= nil then return end
	local slot, recipe_index = 0, 9000
	local bloodcap = tp.getTankCapacity(config.altar, 1)
	for ss = 1, config.input_slots do
		local s = tp.getStackInSlot(config.input, ss)
		for rr = 1, #recipes do
			if rr >= recipe_index then break end
			if guts.id(s) == guts.id(recipes[rr].input) and recipes[rr].blood < bloodcap then
				slot, recipe_index = ss, rr
				break
			end
		end
	end
	return slot, recipe_index
end

guts.do_job = function(slot, recipe)
	do
		local blood
		repeat --until altar is ready
				blood = tp.getFluidInTank(config.altar, 1)[1].amount
				status.action = string.format("Filling altar -- %d/%d mb", blood, recipe.blood)
				os.sleep(0.2)
		until blood > recipe.blood
	end

	--Move the blood orb out of the way
	tp.transferItem(config.altar, config.store, 1, 1, config.store_slot)

	status.action = "Creating ".. recipe.output.label

	tp.transferItem(config.input, config.altar, 1, slot, 1)

	local isDone
	repeat --until item has transformed
		os.sleep(0.1)
		local item = tp.getStackInSlot(config.altar, 1)
		isDone = guts.id(item) == guts.id(recipe.output)
		isValid = isDone or guts.id(item) == guts.id(recipe.input)
		if not isValid then
			if item == nil then
				error("Item removed during job.")
			else
				error("Unexpected item " .. guts.id(item) .. " during job.")
			end
		end
	until isDone

	tp.transferItem(config.altar, config.output, 1, 1, config.output_slot)
	
	-- Restore blood orb to its rightful place
	tp.transferItem(config.store, config.altar, 1, config.store_slot, 1)
	status.action = "Recharging blood orb"
	os.sleep(3)
	status.recipe = nil
end

guts.tick = function()
	local slot, recipe_index = guts.find_job()
	if status.recipe == nil and slot > 0 then
		status.state = "Active"
		status.recipe = recipes[recipe_index]
		guts.do_job(slot, status.recipe)
	elseif status.recipe == nil then
		status.state = status.thread and "Idle" or "Stopped"
		status.action = nil
	end
end

guts.recover = function(err)
  print(err)
  local item = tp.getStackInSlot(config.altar, 1) or 
      {name = "minecraft:air", damage = 0}
  if item.name ~= "bloodmagic:ItemBloodOrb" then
    if item.name ~= "minecraft:air" then 
      tp.transferItem(config.altar, config.output, 1, 1, config.output_slot)
    end
    tp.transferItem(config.store, config.altar, 1, config.store_slot, 1)
  end
  status.state = "Errored: " .. err
  return err
end

function tick()
  guts.tick()
end

guts.threadproc = function()
  repeat
    local success, message = xpcall(guts.tick, guts.recover)
    if success then
      if status.recipe == nil then
        os.sleep(1)
      end
    else
      status.thread = nil
      status.should_run = false
    end
  until not status.should_run
end

function start()
  if status.thread ~= nil then
    return
  end

  status.should_run = true
  status.thread = thread.create(guts.threadproc):detach()
end

function stop()
  if status.thread == nil then
    return
  end

  status.should_run = false
  status.thread:join()
  status.thread = nil
end

function monitor()
	local term = require("term")
	local gpu = term.gpu()
	local event = require("event")
	repeat
		term.clear()
		local of = gpu.setForeground(0xAA5500)
		print("Infusion Crafting System")
		print(status.state)
		gpu.setForeground(0xFFFF00)
		print(status.action)
		gpu.setForeground(of)
	until event.pull(1, "key_down", nil, 0x71) ~= nil
end