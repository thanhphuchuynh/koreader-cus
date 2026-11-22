-- Listening player: Kindle route with a fake gst-launch (cat > file) and the real dd; fake clock.
local plugin=assert(arg[1])
package.path=plugin..'/?.lua;'..package.path
local jobs={}
package.loaded.device={isKindle=function()return true end}
package.loaded['ui/uimanager']={scheduleIn=function(_,_,fn)jobs[#jobs+1]=fn end,
 unschedule=function(_,fn)for i=#jobs,1,-1 do if jobs[i]==fn then table.remove(jobs,i)end end end}
local focus
package.loaded.liblipclua={init=function()return {set_string_property=function(_,s,p,v)focus={s,p,v}end,close=function()end}end}
local V=require('english_voca')
local A=require('english_ielts_audio')

local bin=os.tmpname();os.remove(bin);os.execute('mkdir -p '..bin)
local out=bin..'/out'
local fake=io.open(bin..'/gst-launch-0.10','w')
fake:write('#!/bin/sh\nprintf "%s\\n" "$@" > '..bin..'/args\ncat > '..out..'\n');fake:close()
os.execute('chmod +x '..bin..'/gst-launch-0.10')
V.bin_dir=bin
-- 3 s of 10 B/s... rate 5 -> 10 bytes/s; byte i of second s is the digit s
local rate=5
local pcm=bin..'/a.pcm'
local f=io.open(pcm,'wb');for s=0,2 do f:write(tostring(s):rep(10)) end f:close()
local clock=100;A.now=function()return clock end
local function read()local h=io.open(out,'rb');local d=h and h:read('*a') or '';if h then h:close() end return d end
local function settle()for _=1,50 do os.execute('sleep 0.1');if not V.alive(nil) and read()~='' then break end end end
local function drain()for _=1,#jobs do local j=table.remove(jobs,1);j() end end
local function waitEnd(a)for _=1,60 do if not a:isPlaying() then return true end os.execute('sleep 0.1');clock=clock+0.1;drain() end end

local a=A.new{path=pcm,rate=rate,seconds=3,kindle=true}
local ended=0;a.on_end=function()ended=ended+1 end
assert(a:play(1,2));assert(a:isPlaying())
assert(focus and focus[3]=='Music','Music focus')
assert(waitEnd(a));assert(ended==1,'on_end once on natural end')
assert(read()==('1'):rep(10),'to limits the stream: '..read())
local args=io.open(bin..'/args'):read('*a')
assert(args:find('caps=audio/x-raw-int,endianness=1234,signed=true,width=16,depth=16,rate=5,channels=1',1,true)
 and args:find('mixersink\nstream-type=Music\nsync=true',1,true),args)

-- no end: from 1 s to the file end
os.remove(out);ended=0
assert(a:play(1));assert(waitEnd(a));assert(read()==('1'):rep(10)..('2'):rep(10),'play(1) streams from 1 s: '..read())
assert(ended==1)
-- clamp
os.remove(out);assert(a:play(99));assert(waitEnd(a));assert(read()==('2'):rep(10),'from clamps below seconds')

-- position follows the clock, freezes on pause; stop does not call on_end
local sleeper=io.open(bin..'/gst-launch-0.10','w');sleeper:write('#!/bin/sh\nexec sleep 30\n');sleeper:close()
ended=0
assert(a:play(0.5));clock=clock+1.25
assert(math.abs(a:position()-1.75)<1e-6,a:position())
local pos=a:pause();assert(math.abs(pos-1.75)<1e-6 and not a:isPlaying() and #jobs==0)
clock=clock+10;assert(math.abs(a:position()-1.75)<1e-6,'frozen while paused')
assert(a:play(pos));clock=clock+1;assert(math.abs(a:position()-2.75)<1e-6)
local pid=a._pid()
assert(pid and V.alive(pid))
a:stop()
os.execute('sleep 0.2')
assert(not V.alive(pid),'stop kills the player')
assert(#jobs==0 and ended==0 and not a:isPlaying(),'stop leaves nothing scheduled and no on_end')

-- WAV slice (Mac path): header + PCM from offset up to `to`
local w=A.wav(rate,'0123456789',2,6)
assert(#w==44+4 and w:sub(1,4)=='RIFF' and w:sub(9,12)=='WAVE' and w:sub(45)=='2345','wav slice bytes')
assert(w:byte(25)==rate and w:byte(41)==4,'rate and data size')
os.execute('rm -rf '..bin)
print('PASS: ielts audio player (Kindle gst route, seek, to, position, pause, stop, on_end, WAV slice)')
