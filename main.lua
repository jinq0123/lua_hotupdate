local HU = require "luahotupdate"
HU.Init("hotupdatelist")
HU.FailNotify = print
-- HU.InfoNotify = print
-- HU.DebugNotify = print

function sleep(t)
  local now_time = os.clock()
  while true do
    if os.clock() - now_time > t then
      HU.Update() 
      return 
    end
  end
end

local test = require "test"
print("start runing")
while true do
  test.func()
  sleep(3)
end
