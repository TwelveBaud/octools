local computer = require("computer")
local thread = require("thread")
local component = require("component")
local tty = require("tty")
local my_thread = nil
local should_run = false

local altar = args or require("sides").front

function tick()
  if not tty.isAvailable() then return end

  local gpu = tty.gpu()
  local x,y = gpu.getResolution()

  local tp = component.proxy(component.list("transposer")())
  local bloodAvailable = tp.getFluidInTank(altar)[1]["amount"]
  local bloodCapacity = tp.getFluidInTank(altar)[1]["capacity"]
  local logAvailable = math.log(bloodAvailable, 2)
  local logCapacity = math.log(bloodCapacity, 2)

  local trackwidth = x / 2 - 1
  local barwidth = (trackwidth-3) * (logAvailable/logCapacity)
  local trackBg = 0x800000
  local barBg = 0xFF0000
  if gpu.getDepth() == 1 then
    trackBg = 0x000000
    barBg = 0xFFFFFF
  end
  
  local oldBg = gpu.setBackground(trackBg)
  local oldFg = gpu.setForeground(0xFFFFFF)  
  gpu.fill(1, 1, trackwidth, 1, ' ')
  gpu.setBackground(barBg)
  gpu.setForeground(0x000000)
  gpu.fill(4, 1, barwidth, 1, ' ')
  gpu.set(1, 1, "Bld")

  local tiers = {1000, 2000, 5000, 15000, 30000}

  for tier in pairs(tiers) do
    if(tiers[tier] < bloodCapacity) then
      if(tiers[tier] > bloodAvailable) then
        gpu.setBackground(trackBg)
        gpu.setForeground(0xFFFFFF)
      end
    local mark = (trackwidth - 3) * (math.log(tiers[tier], 2)/logCapacity)
    gpu.set(mark + 3, 1, tostring(tier))
    end
  end

  gpu.setBackground(oldBg)
  gpu.setForeground(oldFg)
end

function threadProc()
  repeat
    tick()
    os.sleep(1)
  until not should_run
end

function start()
  if my_thread ~= nil then
    return
  end

  should_run = true
  my_thread = thread.create(threadProc):detach()
end

function stop()
  if my_thread == nil then
    return
  end

  should_run = false
  my_thread:join()
  my_thread = nil
end