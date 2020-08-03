tiers = {
  { label = "Stone Block",      name = "minecraft:stone",      damage = 0, blood = 0},
  { label = "Blank Slate",      name = "bloodmagic:ItemSlate", damage = 0, blood = 1000},
  { label = "Reinforced Slate", name = "bloodmagic:ItemSlate", damage = 1, blood = 2000},
  { label = "Imbued Slate",     name = "bloodmagic:ItemSlate", damage = 2, blood = 5000},
  { label = "Demonic Slate",    name = "bloodmagic:ItemSlate", damage = 3, blood = 15000},
  { label = "Ethereal Slate",   name = "bloodmagic:ItemSlate", damage = 4, blood = 30000},
  n = 6
}

tiers.clone = function(self) 
  local cl = {n = self.n, clone = self.clone}
  for i in ipairs(self) do
    local c = {}
    for k, v in pairs(self[i]) do
      c[k] = v
    end
    cl[i] = c
  end
  return cl
end

local computer = require("computer")
local thread = require("thread")
local sides = require("sides")
local component = require("component")
local tp = component.proxy(component.list("transposer")())

guts = {}
status = {
  job = nil,
  action = nil,
  state = "Stopped",
  thread = nil,
  should_run = false
}

guts.id = function(stack)
  stack = stack or {label = "Air", name = "minecraft:air", damage = 0}
  return stack.name .. "/" .. stack.damage
end

guts.find_jobs = function()
  if status.job ~= nil then
    return
  end
  local j = { slot = 0, tier = 9000}
  for ss = 1, 26 do
    s = tp.getStackInSlot(sides.top, ss)
    for tt = 1, tiers.n - 1 do
      if tt < j.tier and guts.id(s) == guts.id(tiers[tt]) then
        j.tier = tt
        j.slot = ss
      end
    end
  end
  if j.tier < 9000 then
    status.job = j
  end
end

guts.do_job = function(job)
  local blood
  repeat --until altar is ready
    blood = tp.getFluidInTank(sides.front, 1)[1].amount
    status.action = string.format("Filling altar -- %d/%d mb", blood, 
        tiers[job.tier + 1].blood)
    os.sleep(0.1)
  until blood > tiers[job.tier + 1].blood

  --Move the blood orb out of the way
  tp.transferItem(sides.front, sides.top, 1, 1, 27)

  status.action = string.format("Creating %s from %s", 
      tiers[job.tier + 1].label, tiers[job.tier].label)

  tp.transferItem(sides.top, sides.front, 1, job.slot, 1)

  local isDone
  repeat --until item has transformed
    os.sleep(0.1)
    local item = tp.getStackInSlot(sides.front, 1)
    isDone = guts.id(item) == guts.id(tiers[job.tier + 1])
    isValid = isDone or guts.id(item) == guts.id(tiers[job.tier])
    if not isValid then
      if item == nil then
        error("Item removed during job.")
      else
        error("Unexpected item " .. item.name .. "/" .. item.damage
            .. " during job.")
      end
    end
  until isDone

  tp.transferItem(sides.front, sides.right, 1, 1, 1)
  
  -- Restore blood orb to its rightful place
  tp.transferItem(sides.top, sides.front, 1, 27, 1)
  status.action = "Recharging blood orb"
  os.sleep(3)
  seq.info("Job complete")
  status.job = nil
end

guts.tick = function()
  guts.find_jobs()

  if status.job ~= nil then
    status.state = "Active"
    guts.do_job(status.job)
  else
    status.state = status.thread and "Idle" or "Stopped"
    status.action = nil
  end
end

guts.recover = function(err)
  print(err)
  local item = tp.getStackInSlot(sides.front, 1) or 
      {name = "minecraft:air", damage = 0}
  if item.name ~= "bloodmagic:ItemBloodOrb" then
    if item.name ~= "minecraft:air" then 
      tp.transferItem(sides.front, sides.right, 1, 1, 1)
    end
    tp.transferItem(sides.top, sides.front, 1, 27, 1)
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
      if status.job == nil then
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