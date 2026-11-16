-- Spread squad monitoring across frames. One owner hook and at most one squad
-- callback per frame, with a 40-frame minimum interval for each squad.
local M={}
local jobs,hook,frame,sequence={},nil,0,0
function M.remove(token)
 jobs[token]=nil
 if not next(jobs) and hook then Events.off(hook);hook=nil end
end
function M.tick()
 frame=frame+1
 local pick
 for token in pairs(jobs)do
  if token.due<=frame and (not pick or token.due<pick.due
    or (token.due==pick.due and token.id<pick.id))then pick=token end
 end
 if pick then pick.due=frame+40;pick.fn()end
end
function M.add(fn,delayFrames)
 if not hook then
  local ok,id=pcall(Events.on,'MyGUI::Gui::eventFrameStart',M.tick)
  if not ok or not id then return nil,tostring(id)end
  hook=id
 end
 sequence=sequence+1
 local token={fn=fn,due=frame+(delayFrames or 0),id=sequence}
 jobs[token]=true
 return token
end
return M
