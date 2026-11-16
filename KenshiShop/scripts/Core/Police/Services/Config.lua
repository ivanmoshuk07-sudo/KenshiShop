local M={faction='400-KenshiShop.mod',tower='105-KenshiShop.mod',hired='11000-KenshiShop.mod'}
local definitions={
 {'300','bar','trader',1,'Core.Bar.NPC.Trader'},
 {'7800','bar','guard',2,'Core.Bar.NPC.Guard'},
 {'303','engineering','trader',1,'Core.Engineering.NPC.Trader'},
 {'7801','engineering','guard',2,'Core.Engineering.NPC.Guard'},
 {'305','armour','trader',1,'Core.Armour.NPC.Trader'},
 {'7802','armour','guard',2,'Core.Armour.NPC.Guard'},
 {'307','weapons','trader',1,'Core.Weapons.NPC.Trader'},
 {'7803','weapons','guard',2,'Core.Weapons.NPC.Guard'},
 {'309','robotics','trader',1,'Core.Robotics.NPC.Skeleton'},
 {'310','police','chief',1,'Core.Police.NPC.Chief'},
 {'311','police','patrol',3,'Core.Police.NPC.Patrol'},
 {'11000','police','patrol',3},
}
M.templates={}
for _,v in ipairs(definitions)do
 M.templates[v[1]..'-KenshiShop.mod']={template=v[1]..'-KenshiShop.mod',shop=v[2],role=v[3],count=v[4],driver=v[5],faction=M.faction,
  patrolNight=v[1]=='11000',serviceHired=v[1]=='11000'}
end
function M.copy(template)
 local row=M.templates[template];if not row then return nil end
 local out={};for k,v in pairs(row)do out[k]=v end;return out
end
return M
