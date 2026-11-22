-- Real voca binary from the plugin; a fake Kindle gst-launch records how playback is started.
local plugin=assert(arg[1])
package.path=plugin..'/?.lua;'..package.path
local jobs={}
package.loaded.device={isKindle=function()return true end}
package.loaded['ui/uimanager']={scheduleIn=function(_,_,fn)jobs[#jobs+1]=fn end,
 unschedule=function(_,fn)for i=#jobs,1,-1 do if jobs[i]==fn then table.remove(jobs,i)end end end}
local focus
package.loaded.liblipclua={init=function()return {set_string_property=function(_,s,p,v)focus={s,p,v}end,close=function()end}end}
local function run(limit)
 for _=1,limit do
  if #jobs==0 then return true end
  os.execute('sleep 0.1');table.remove(jobs,1)()
 end
end
local V=require('english_voca')

-- WAV -> raw PCM with 0.5 s lead-in and 1 s tail of silence.
local header='RIFF'..('\0'):rep(4)..'WAVEfmt '..string.char(16,0,0,0,1,0,1,0,0xC0,0x5D,0,0,0x80,0xBB,0,0,2,0,16,0)..'data'..('\0'):rep(4)
local pcm,rate,channels,seconds=V.pcm(header..'abcd')
assert(rate==24000 and channels==1 and #pcm==12000*2+4+24000*2 and pcm:sub(24001,24004)=='abcd' and seconds==4/48000)
assert(not V.pcm('nope') and not V.pcm(header:sub(1,20)..string.char(3,0)..header:sub(23)..'ab'),'non-PCM input must be rejected')
local m={base=6,per=0.08}
assert(V.percent(0,100,m)==0 and V.percent(7,100,m)==50 and V.percent(99,100,m)==99,'percent = elapsed / (base + per*chars), capped at 99')
local short=V.learn(m,10,10);assert(short.base==8 and short.per==0.08,'short text learns the fixed cost')
local long=V.learn(m,200,26);assert(long.base==6 and math.abs(long.per-0.09)<1e-9,'long text learns the per-character cost')
print('PASS: Loading % estimate and learning')
print('PASS: WAV converts to frame-aligned raw PCM with lead-in and tail silence; bad input rejected')

local bin=os.tmpname();os.remove(bin);os.execute('mkdir -p '..bin)
local log=bin..'/args'
local fake=io.open(bin..'/gst-launch-0.10','w')
fake:write('#!/bin/sh\nprintf "%s\\n" "$@" > '..log..'\n[ -n "$LEAF_SLEEP" ] && sleep 5\nexit 0\n');fake:close()
os.execute('chmod +x '..bin..'/gst-launch-0.10')
V.bin_dir=bin
local commands={}
local popen=io.popen
io.popen=function(c,...)commands[#commands+1]=c;return popen(c,...)end
local speech=V.new(plugin)
assert(speech:available(),'voca binary and data must be installed in the plugin')
local text=[[Don't stop; `touch /tmp/leaf-pwned` $(touch /tmp/leaf-pwned)]]
local done,err=0
local began=0
assert(speech:speak(text,function(e)done=done+1;err=e end,function()began=began+1 end))
assert(began==0,'not audible until the voice is generated')
assert(speech:isSpeaking())
assert(run(200),'speech must finish')
assert(done==1 and not err and not speech:isSpeaking(),tostring(err))
assert(began==1,'playback start must be reported once')
-- Loading %: a slow voca (0.5 s) and a slow clock (2 s per reading) make every poll report.
local slow=os.tmpname();os.remove(slow);os.execute('mkdir -p '..slow..'/voca && ln -s '..plugin..'/voca/data '..slow..'/voca/data')
local sv=io.open(slow..'/voca/voca','w');sv:write('#!/bin/sh\nsleep 0.5\nexec '..plugin..'/voca/voca "$@"\n');sv:close()
os.execute('chmod +x '..slow..'/voca/voca')
local clock,now=0,V.now;V.now=function()clock=clock+2;return clock end
local pcts={}
assert(V.new(slow):speak('Progress please.',function()end,nil,function(p)pcts[#pcts+1]=p end))
assert(run(200));V.now=now;os.execute('rm -rf '..slow)
assert(#pcts>=1 and pcts[#pcts]<100,'progress must be reported while generating: '..#pcts)
for i=2,#pcts do assert(pcts[i]>=pcts[i-1]) end
for _,c in ipairs(commands)do assert(not c:find('leaf-pwned',1,true),'text must never reach the shell') end
assert(not io.open('/tmp/leaf-pwned'),'text must never be executed')
local args=io.open(log):read('*a')
assert(args:find('location=/tmp/leaf-speech/out.pcm',1,true)
 and args:find('caps=audio/x-raw-int,endianness=1234,signed=true,width=16,depth=16,rate=24000,channels=1',1,true)
 and args:find('mixersink\nstream-type=Music\nsync=true',1,true),args)
assert(focus and focus[1]=='com.lab126.audiomgrd' and focus[3]=='Music','Kindle playback must take Music audio focus')
local raw=io.open('/tmp/leaf-speech/out.pcm','rb'):read('*a')
assert(#raw>24000*3 and raw:sub(1,24000)==('\0'):rep(24000),'raw audio must start with silence')
print('PASS: real voca speech -> raw PCM -> Kindle gst-launch mixersink with Music focus; text never reaches the shell')

-- Stop during playback: one callback, process killed, nothing left scheduled.
local f=io.open(bin..'/gst-launch-0.10','w')
f:write('#!/bin/sh\nexec sleep 30\n');f:close()
done=0
assert(speech:speak('Stop me.',function(e)done=done+1;err=e end))
for _=1,100 do
 if #jobs==0 then break end
 os.execute('sleep 0.1');table.remove(jobs,1)()
 if io.open('/tmp/leaf-speech/out.pcm') and #jobs>0 then
  -- playback started (pcm written); give it a moment then stop
  os.execute('sleep 0.3');break
 end
end
speech:stop();speech:stop()
assert(done==1 and not err and not speech:isSpeaking() and #jobs==0,'stop must finish once and cancel polling')
os.execute('sleep 0.2')
local h=popen('pgrep -f "sleep 30" | wc -l');local left=tonumber(h:read('*a'));h:close()
assert(left==0,'stop must kill the player process')
print('PASS: stop during playback kills the player, finishes once and cancels polling')
io.popen=popen
os.execute('rm -rf '..bin)
