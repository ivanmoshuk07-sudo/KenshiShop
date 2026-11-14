-- KenshiShop alpha.37: stable, bar-only 50/50 seating split; all non-seating to NPC.
-- Source of furniture display names: native FCS GameData.name.
-- Never guess an ID->name association; unknown categories remain NPC with a warning.
local M={}
local PLAYER_NAME={
 'bench','chair','stool','bed','sofa','couch','seat','sleeping','futon','cot',
 'лавк','скам','стул','табур','кроват','диван','сидень','кушет',
}
local NPC_NAME={
 'table','counter','shelf','shelves','storage','cabinet','cupboard',
 'container','chest','cook','stove','light','lamp','lantern','decor',
 'стол','прилав','стойк','шкаф','полк','стеллаж','контейнер',
 'хранили','кухон','печ','свет','ламп','освещ','декор',
}
local function nativeName(record)
 if not record then return nil end
 local ok,name=pcall(function()return record.name end)
 if ok and type(name)=='string' and name~='' then return name end
 return nil
end
local function includes(name,words)
 for _,w in ipairs(words) do
  if name:find(w,1,true) then return true,w end
 end
 return false,nil
end
function M.classify(item,record)
 -- Prefix-based identifier is not the physical furniture type.
 -- Explicitly prefer tables/counters in composite names (e.g. "bedside table").
 local raw=nativeName(record)
 if raw then
  local lower=raw:lower() -- ASCII for English; match case variants for Cyrillic below.
  local target=lower
  if includes(target,NPC_NAME) then return 'NPC','NAME_NPC',raw end
  if includes(target,PLAYER_NAME) then return 'SHARED','NAME_SEATING',raw end
  -- Cyrillic uppercase is not lowered by stock Lua; common labels below.
  for _,word in ipairs({'Лавк','Скам','Стул','Табур','Кроват','Диван','Сидень','Кушет'}) do
   if raw:find(word,1,true) then return 'SHARED','NAME_SEATING',raw end
  end
  for _,word in ipairs({'Стол','Прилав','Стойк','Шкаф','Полк','Стеллаж','Контейнер','Кухон','Печ','Освещ','Ламп','Декор'}) do
   if raw:find(word,1,true) then return 'NPC','NAME_NPC',raw end
  end
 end
 return 'NPC','UNCLASSIFIED_DEFAULT_NPC',raw or 'NAME_UNAVAILABLE'
end
-- Build a stable per-index plan using immutable layout order, not current ownership.
-- For an odd number of shared seats, player receives one extra (19/18 for 37).
-- This plan is regenerated on each load, so the same individual seats stay assigned.
function M.plan(layout,gamedata)
 local result={owners={},shared={},sharedTotal=0,sharedPlayer=0,sharedNPC=0,player=0,npc=0,unclassified=0}
 if not layout or not layout.objects or not gamedata then return nil,'LAYOUT_OR_GAMEDATA_UNAVAILABLE' end
 if #layout.objects>110 then return nil,'LAYOUT_CAP' end
 for i,item in ipairs(layout.objects) do
  local record=gamedata:getData(item.id,0)
  if not record then return nil,'MISSING_GAME_DATA index='..i..' id='..tostring(item.id) end
  local category,source,name=M.classify(item,record)
  local owner='NPC'
  if category=='SHARED' then
   result.sharedTotal=result.sharedTotal+1
   -- Alternate evenly across the ENTIRE shared group, with deterministic indices.
   owner=(result.sharedTotal%2)==1 and 'PLAYER' or 'NPC'
   result.shared[#result.shared+1]={index=i,owner=owner,id=tostring(item.id),name=name}
   if owner=='PLAYER' then result.sharedPlayer=result.sharedPlayer+1 else result.sharedNPC=result.sharedNPC+1 end
  end
  if source=='UNCLASSIFIED_DEFAULT_NPC' then result.unclassified=result.unclassified+1 end
  result.owners[i]=owner
  if owner=='PLAYER' then result.player=result.player+1 else result.npc=result.npc+1 end
 end
 return result
end
return M
