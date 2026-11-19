package.path=assert(arg[1])..'/?.lua;'..package.path
local jobs,commands,closed={}, {},0
local clock,state=0,0
package.loaded.device={isKindle=function()return true end}
package.loaded['ui/time']={now=function()return clock end,to_ms=function(t)return t end}
package.loaded['ui/uimanager']={scheduleIn=function(_,_,fn)jobs[#jobs+1]=fn end,unschedule=function(_,fn)for i=#jobs,1,-1 do if jobs[i]==fn then table.remove(jobs,i)end end end}
package.loaded.liblipclua={init=function(name)
 assert(name=='com.github.koreadercus.speech')
 return {set_string_property=function(_,service,property,value)commands[#commands+1]={service,property,value}end,
  get_int_property=function()return state end,close=function()closed=closed+1 end}
end}
local speech=require('english_speech').new()
local finished,error_message=0,nil
assert(speech:speak([[Don't give up; `echo unsafe` $(no-shell)]],function(err)finished=finished+1;error_message=err end))
local parameter
for _,command in ipairs(commands)do if command[2]=='PlayParameter' then parameter=require('json').decode(command[3])end end
assert(parameter.data.paramValue==[[Don't give up; `echo unsafe` $(no-shell)]],'text must be passed as JSON data, never shell code')
state=1;clock=200;table.remove(jobs,1)()
state=0;clock=500;table.remove(jobs,1)()
assert(finished==1 and not error_message and closed==1 and not speech:isSpeaking())
assert(speech:speak('A short test.',function()finished=finished+1 end))
speech:stop();speech:stop()
assert(finished==2 and closed==2 and #jobs==0,'Stop must cancel polling, close the connection and finish once')
state=0;clock=0
assert(speech:speak('Startup test.',function(err)error_message=err end))
clock=6000;table.remove(jobs,1)()
assert(error_message and not speech:isSpeaking(),'native service that never starts must report a failure')
assert(not speech:speak(string.rep('x',2001),function()end),'long passages must be rejected, not truncated')
package.loaded.device.isKindle=function()return false end
assert(not speech:speak('Unsupported device.',function()end))
print('PASS: native LIPC speech uses data-only parameters, completes, stops once, times out and rejects unsupported input')
package.loaded.device.isKindle=function()return true end
local commands_before=#commands
package.loaded.liblipclua.init=function()return {
 get_int_property=function()error('service unavailable')end,
 set_string_property=function(_,a,b,c)commands[#commands+1]={a,b,c}end,
 close=function()closed=closed+1 end,
}end
assert(not speech:speak('Unavailable service.',function()end))
assert(#commands==commands_before and #jobs==0,'a failed capability probe must not stop or close another audio session')
print('PASS: unsupported native service fails without issuing playback commands')
