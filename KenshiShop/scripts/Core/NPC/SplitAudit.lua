-- alpha.69: strictly read-only verification of independent merchant/guard platoons.
-- No spawns, changes to AI, NPC home, ownership, jobs or navigation.
local Existing=require('Core.NPC.ExistingSquads')
local M={}
local FACTION='400-KenshiShop.mod'
local SHOPS={
 ['100-KenshiShop.mod']={name='bar',trader='300-KenshiShop.mod',guard='7800-KenshiShop.mod'},
 ['101-KenshiShop.mod']={name='engineering',trader='303-KenshiShop.mod',guard='7801-KenshiShop.mod'},
 ['102-KenshiShop.mod']={name='armour',trader='305-KenshiShop.mod',guard='7802-KenshiShop.mod'},
 ['103-KenshiShop.mod']={name='weapons',trader='307-KenshiShop.mod',guard='7803-KenshiShop.mod'},
}
local ORDER={'100-KenshiShop.mod','101-KenshiShop.mod','102-KenshiShop.mod','103-KenshiShop.mod'}
local function call(obj,name,...)
 if not obj then return nil end
 local ok,method=pcall(function()return obj[name] end)
 if not ok or type(method)~='function' then return nil end
 local yes,value=pcall(method,obj,...)
 if yes then return value end
 return nil
end
local function sid(b)
 local data=call(b,'getGameData')
 local ok,id=pcall(function()return data and data.stringID end)
 return ok and id and tostring(id) or nil
end
local function role(b,roleName,template,expected)
 local found,p,why=pcall(Existing.find,b,{template=template,faction=FACTION})
 if not found then return 'LOOKUP_EXCEPTION '..tostring(p),'ERROR' end
 if p==false then return 'NOT_FOUND (not spawned or saved)', 'MISSING' end
 if not p then return 'LOOKUP_UNVERIFIED '..tostring(why), 'ERROR' end
 local id=call(p,'getPlatoonStringID') or '?'
 local ap=call(p,'getActivePlatoon')
 if not ap then return 'SAVED_UNLOADED platoon='..tostring(id),'UNLOADED' end
 local count=call(ap,'getSquadSize')
 if count==expected then
  return 'PASS '..count..'/'..expected..' platoon='..tostring(id),'PASS'
 end
 if roleName=='trader' and count==3 then
  return 'LEGACY_MIXED 3/3 platoon='..tostring(id)..' new_guard_spawn_must_be_blocked','LEGACY'
 end
 return 'COUNT_MISMATCH '..tostring(count)..'/'..expected..' platoon='..tostring(id),'MISMATCH'
end
function M.check(b)
 local id=sid(b)
 local cfg=id and SHOPS[id]
 if not cfg then return 'SPLIT_CHECK NOT_SPLIT_SHOP '..tostring(id),'NOT_APPLICABLE' end
 local trader,tc=role(b,'trader',cfg.trader,1)
 local guard,gc=role(b,'guard',cfg.guard,2)
 local state
 if tc=='LEGACY' then state='LEGACY'
 elseif tc=='ERROR' or gc=='ERROR' then state='LOOKUP_ERROR'
 elseif tc=='MISMATCH' or gc=='MISMATCH' then state='COUNT_MISMATCH'
 elseif tc=='MISSING' or gc=='MISSING' then state='INCOMPLETE'
 elseif tc=='UNLOADED' or gc=='UNLOADED' then state='SAVED_UNLOADED'
 else state='PASS' end
 return 'SPLIT_CHECK shop='..cfg.name..' state='..state..' trader='..trader..' guard='..guard..' read_only=true',state
end
function M.templates(world)
 local gd=world and world.gamedata
 if not gd then return 'SPLIT_FCS unavailable_gameworld; not_tested',nil end
 local found=0
 local errors={}
 for _,id in ipairs(ORDER) do
  local cfg=SHOPS[id]
  for _,r in ipairs({'trader','guard'}) do
   local template=cfg[r]
   local ok,rec=pcall(gd.getData,gd,template,52)
   if ok and rec then found=found+1 else errors[#errors+1]=cfg.name..'_'..r..'='..template end
  end
 end
 local msg='SPLIT_FCS templates='..found..'/8 read_only=true'
 if #errors>0 then msg=msg..' missing='..table.concat(errors,',')end
 return msg,found==8
end
function M.isSplitShop(b)return SHOPS[sid(b)]~=nil end
return M
