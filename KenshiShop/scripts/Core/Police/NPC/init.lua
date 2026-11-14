-- TWO separate squads: police chief alone, patrol of three.
local queue=require('Core.NPC.Scheduler')
return queue.new('police',{
 {name='chief',driver=require('Core.Police.NPC.Chief')},
 {name='patrol',driver=require('Core.Police.NPC.Patrol')},
})
