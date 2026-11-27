local Config=require('Core.Police.Services.Config')
local Scheduler=require('Core.NPC.Scheduler')
local driver=require('Core.Crematorium.NPC')
local queue=Scheduler.new('crematorium',{{name='undertaker',driver=driver}})

return {sid=Config.crematorium,name='crematorium',enqueue=queue.start,
 npcStart=queue.start,npcResume=queue.resume,npcStatus=queue.status,npcCheck=queue.check,
 resetSession=queue.resetSession}
