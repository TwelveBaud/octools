tiers = {
  {name = "Blank Slate", blood=1000},
  {name = "Reinforced Slate", blood=2000},
  {name = "Imbued Slate", blood=5000},
  {name = "Demonic Slate", blood=15000},
  {name = "Ethereal Slate", blood=30000},
  n=5,
  [0] = { name = "Stone Block", blood=0, have = 64}
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
  cl[0] = { name = "Stone Block", blood=0, have = 64}
  return cl
end

local computer = require("computer")
local thread = require("thread")
local sides = require("sides")
local component = require("component")
local tp = component.proxy(component.list("transposer")())
local refi = component.proxy(component.list("block_refinedstorage_interface")())

guts = {}
status = {
  job = nil,
  action = nil,
  state = "Stopped",
  thread = nil,
  should_run = false
}

guts.needhave = function()
  local tiers = tiers:clone()
  local needy_jobs = {}

  for t = 1, tiers.n do
    tiers[t].have = 
        (tp.getStackInSlot(sides.left, t) or {size = 0}).size 
      + (tp.getStackInSlot(sides.left, t + 9) or {size=0}).size
    tiers[t].need = 0
  end

  local jobs = refi.getTasks()
  for j = 1, jobs.n do
    local job = jobs[j]
    local should_care = false

    for m = 1, job.missing.n do
      local need = job.missing[m]
      if need.name == "bloodmagic:ItemSlate" then
        if not should_care then
          should_care = true
          job.tiers = tiers:clone()
        end        
        job.tiers[need.damage + 1].need = job.tiers[need.damage + 1].need + need.size
      end
    end

    if should_care then
      needy_jobs[#needy_jobs + 1] = job
      job.ops = 0
      for t = job.tiers.n, 1, -1 do
        job.tiers[t].craft = job.tiers[t].need - job.tiers[t].have
        if t < job.tiers.n then
          job.tiers[t].craft = job.tiers[t].craft + job.tiers[t + 1].craft
        end
        if job.tiers[t].craft < 0 then job.tiers[t].craft = 0 end
        job.ops = job.ops + job.tiers[t].craft
      end
    end
  end -- for j = 1, jobs.n do

  table.sort(needy_jobs, function(job_a, job_b) return job_a.ops < job_b.ops end)

  if #needy_jobs > 0 then
    status.job = needy_jobs[1]
  else
    status.job = nil
  end
end

guts.do_job = function(job)
  if job == nil then return end

  if job.ops == 0 then return guts.finish_job(job) end

  local target = 99
  for t = job.tiers.n, 1, -1 do
    if job.tiers[t].craft > 0 and job.tiers[t-1].have > 0 then
      target = t
      break
    end
  end
  if target == 99 then return end

  return guts.do_create(target)
end

guts.do_create = function(tier)
  local blood
  repeat --until altar is ready
    blood = tp.getFluidInTank(sides.front, 1)[1].amount
    status.action = string.format("Filling altar -- %d/%d mb", blood, tiers[tier].blood)
    os.sleep(0.1)
  until blood > tiers[tier].blood

  --Move the blood orb out of the way
  tp.transferItem(sides.front, sides.left, 1, 1, 19)

  status.action = string.format("Creating %s from %s", tiers[tier].name, tiers[tier - 1].name)

  if tier ~= 1 then
    if not tp.transferItem(sides.left, sides.front, 1, tier - 1, 1) then
      tp.transferItem(sides.left, sides.front, 1, tier + 8, 1)
    end
  else
    tp.transferItem(sides.right, sides.front, 1, 10, 1)
  end

  local hasChanged
  repeat --until item has transformed
    os.sleep(0.1)
    local item = tp.getStackInSlot(sides.front, 1)
    isDone = item ~= nil and item.name == "bloodmagic:ItemSlate" and item.damage + 1 == tier
  until isDone

  if not tp.transferItem(sides.front, sides.left, 1, 1, tier) then
    tp.transferItem(sides.front, sides.left, 1, 1, tier + 9)
  end
  
  -- Restore blood orb to its rightful place
  tp.transferItem(sides.left, sides.front, 1, 19, 1)
  status.action = "Recharging blood orb"
  os.sleep(3)
end

guts.finish_job = function(job)
  status.action = "Delivering slates"
  for t = job.tiers.n, 1, -1 do
    for s = 1, 9 do
      if job.tiers[t].need == 0 then break end
      local success, count = tp.transferItem(sides.left, sides.right, job.tiers[t].need, t + 9, s)
      if success then 
        job.tiers[t].need = job.tiers[t].need - count
      end
      if job.tiers[t].need == 0 then break end
      local success, count = tp.transferItem(sides.left, sides.right, job.tiers[t].need, t, s)
      if success then
        job.tiers[t].need = job.tiers[t].need - count
      end
      if job.tiers[t].need == 0 then break end
    end
  end
  local p = 0
  status.action = "Waiting for acceptance"
  repeat
    p = 0
    for s = 1, 9 do
      p = p + (tp.getStackInSlot(sides.right, s) or {size = 0}).size
    end
    os.sleep(1)
  until p == 0
end

guts.recover = function(err)
  local item = tp.getStackInSlot(sides.front, 1)
  if item == nil then 
    item = {name = "minecraft:air"} 
  end
  
  if item.name == "bloodmagic:ItemSlate" then
    if not tp.transferItem(sides.front, sides.left, 1, 1, item.damage + 1) then
      tp.transferItem(sides.front, sides.left, 1, 1, item.damage + 10)
    end
  elseif item.name == "bloodmagic.ItemBloodOrb" then
    -- Do nothing, this is the case we wanted
  else
    for slot = 27, 20, -1 do
      if tp.transferItem(sides.front, sides.left, 1, 1, slot) then break end
    end
  end
  
  if item.name ~= "bloodmagic.ItemBloodOrb" then
    tp.transferItem(sides.left, sides.front, 1, 19, 1)
  end

  status.state = "Errored: " .. err
  return err
end

guts.tick = function()
  guts.needhave()

  if status.job ~= nil then
    status.state = "Active"
    guts.do_job(status.job)
  else
    status.state = status.thread and "Idle" or "Stopped"
    status.action = nil
  end
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