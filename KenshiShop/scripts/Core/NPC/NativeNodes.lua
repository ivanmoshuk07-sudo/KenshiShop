-- Actual engine LocationNodes, created by the dedicated node factory. These
-- are not furniture/Building objects and have no physical model or collision.
local Live=require('Core.NPC.LiveState')
local Transform=require('Transform')
local Posts=require('Core.NPC.PostData')
local Log=require('Diagnostics')
local M={}
local buildings={}
function M.resetSession()buildings={}end
function M.ensure(s,b)
 local world=getGameWorld();local gm=world and world.gamedata
 if not gm or not world.theFactory then return false,'NODE_FACTORY_UNAVAILABLE'end
 if Live.call(b,'isPhysical')~=true then return false,'BUILDING_NOT_PHYSICAL'end
 local root=Live.call(b,'getRootNode')
 if not root then return false,'BUILDING_ROOT_UNAVAILABLE'end
 local physical=tostring(root)
 local r=buildings[s.key]
 if not r or r.gm~=gm or r.physical~=physical then
  r={gm=gm,physical=physical,created={},tries=0};buildings[s.key]=r
 end
 if r.done then return true end
 if r.tries>=3 then return false,'NODE_SETUP_FAILED'end
 local entries=Posts[s.cfg.shop] or {};local pending={}
 for i,p in ipairs(entries)do
  local data=Live.call(gm,'getData',p.id,0)
  if not data then return false,'NODE_TEMPLATE_MISSING '..p.id end
  pending[#pending+1]={index=i,entry=p,data=data,id='KS85_NODE:'..s.key..':'..p.source}
 end
 if #pending==0 then return false,'NODE_COORDINATES_MISSING'end
 local ok,err=pcall(function()
  for _,p in ipairs(pending)do
   if not r.created[p.index]then
    local pos,rot=Transform.world(b:getPosition(),b:getOrientation(),b:getScale(),p.entry)
    local node=world.theFactory:createLocationNode(true,p.data,pos,b,b:getFaction(),rot,nil,p.id)
    assert(node and not tostring(node):find('(nil)',1,true),'LOCATION_NODE_CREATE_FAILED')
    -- Keep the opaque pointer opaque; registration belongs to the factory.
    r.created[p.index]=true
   end
  end
  -- addToNodeListAutomatically=true registers LocationNodes by parent building.
  -- Building.addUsageNode is for NODE_USE (4), not these post types (0/1/2).
 end)
 if not ok then r.tries=r.tries+1;return false,'NATIVE_NODE_SETUP '..tostring(err)end
 r.done=true
 Log.console('NPC_NATIVE_NODES87 shop='..s.cfg.shop..' building='..s.key..' count='..#pending..' factory=createLocationNode furniture_changes=0 registration=factory_auto selection=SEE_WORK_AUDIT')
 return true
end
return M
