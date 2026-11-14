-- Independent queue and NPC state for Weapons; one trader-led squad, plus patrol for Bar.
local queue=require('Core.NPC.Scheduler')
return queue.new('weapons',{

 {name='trader',driver=require('Core.Weapons.NPC.Trader')},
 {name='guard',driver=require('Core.Weapons.NPC.Guard')},
})
