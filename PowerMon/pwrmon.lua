local computer = require("computer")
local thread = require("thread")
local component = require("component")
local tty = require("tty")
local unicode = require("unicode")
local my_thread = nil
local should_run = false

function tick()
  if not tty.isAvailable() then return end

  local gpu = tty.gpu()
  local x,y = gpu.getResolution()

  local trackwidth = x / 2
  local barwidth = trackwidth * (computer.energy() / computer.maxEnergy())
  local trackBg = 0x008000
  local barBg = 0x00FF00
  if gpu.getDepth() == 1 then
    trackBg = 0x000000
    barBg = 0xFFFFFF
  end
  
  local oldBg = gpu.setBackground(trackBg)
  local oldFg = gpu.setForeground(0xFFFFFF)  
  gpu.fill(trackwidth, 1, trackwidth, 1, ' ')
  gpu.setBackground(barBg)
  gpu.setForeground(0x000000)
  gpu.fill(trackwidth, 1, barwidth, 1, ' ')
  gpu.set(trackwidth, 1, unicode.char(0x26A1))
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

  local w, h, dx, dy, x, y = tty.getViewport()
  tty.setViewport(w, h-1, dx, dy+1, x, y+1)

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