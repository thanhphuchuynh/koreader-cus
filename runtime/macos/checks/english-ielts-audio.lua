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
-- rate 100 -> 200 B/s, 2 B per 10 ms block; block i holds the byte char(48+i%64) twice
local rate=100
local function blk(i)return string.char(48+i%64):rep(2) end
local function blocks(a,b)local t={};for i=a,b-1 do t[#t+1]=blk(i) end return table.concat(t) end
local LEAD,TAIL=('\0'):rep(rate),('\0'):rep(rate*2)
local pcm=bin..'/a.pcm'
local f=io.open(pcm,'wb');f:write(blocks(0,300));f:close()
local clock=100;A.now=function()return clock end
local function read()local h=io.open(out,'rb');local d=h and h:read('*a') or '';if h then h:close() end return d end
local function drain()for _=1,#jobs do local j=table.remove(jobs,1);j() end end
local function waitEnd(a)for _=1,60 do if not a:isPlaying() then return true end os.execute('sleep 0.1');clock=clock+0.1;drain() end end

local a=A.new{path=pcm,rate=rate,seconds=3,kindle=true}
local ended=0;a.on_end=function()ended=ended+1 end
assert(a:play(1,2));assert(a:isPlaying())
assert(focus and focus[3]=='Music','Music focus')
assert(waitEnd(a));assert(ended==1,'on_end once on natural end')
assert(read()==LEAD..blocks(100,200)..TAIL,'to limits the stream, padded: '..read())
local args=io.open(bin..'/args'):read('*a')
assert(args:find('caps=audio/x-raw-int,endianness=1234,signed=true,width=16,depth=16,rate=100,channels=1',1,true)
 and args:find('mixersink\nstream-type=Music\nsync=true',1,true),args)

os.remove(out);ended=0
assert(a:play(1));assert(waitEnd(a));assert(read()==LEAD..blocks(100,300)..TAIL,'play(1) streams from 1 s');assert(ended==1)
os.remove(out);assert(a:play(99));assert(waitEnd(a));assert(read()==LEAD..blocks(299,300)..TAIL,'from clamps below seconds')
-- sub-second from/to
os.remove(out);assert(a:play(1.5,2.2));assert(waitEnd(a));assert(read()==LEAD..blocks(150,220)..TAIL,'fractional from/to: '..read())

-- gst exits long before the clip's end (no Bluetooth): on_fail with the place reached, never on_end
do
  local b=A.new{path=pcm,rate=rate,seconds=3,kindle=true}
  local ends,fails,at=0,0,nil
  b.on_end=function() ends=ends+1 end;b.on_fail=function(p) fails=fails+1;at=p end
  os.remove(out);assert(b:play(0));assert(waitEnd(b))
  assert(fails==1 and ends==0 and at and at<1 and b:position()==at,'early exit is a stop, not the end: '..tostring(at))
  -- the same exit after the clip's duration has passed is the natural end
  os.remove(out);assert(b:play(2.5));clock=clock+5;assert(waitEnd(b))
  assert(ends==1 and fails==1,'late exit is the end')
end

-- position: nothing during the 0.5 s lead-in, then follows the clock; frozen on pause; stop keeps the stop point
local sleeper=io.open(bin..'/gst-launch-0.10','w');sleeper:write('#!/bin/sh\nexec sleep 30\n');sleeper:close()
ended=0
assert(a:play(0.5));clock=clock+0.25
assert(math.abs(a:position()-0.5)<1e-6,'lead-in does not advance position')
clock=clock+1
assert(math.abs(a:position()-1.25)<1e-6,a:position())
local pos=a:pause();assert(math.abs(pos-1.25)<1e-6 and not a:isPlaying() and #jobs==0)
clock=clock+10;assert(math.abs(a:position()-1.25)<1e-6,'frozen while paused')
assert(a:play(pos));clock=clock+1.5;assert(math.abs(a:position()-2.25)<1e-6,'resumed offset: '..a:position())
local pid=a._pid()
assert(pid and V.alive(pid))
a:stop()
assert(math.abs(a:position()-2.25)<1e-6,'stop keeps the stop point')
os.execute('sleep 0.2')
assert(not V.alive(pid),'stop kills the player')
assert(#jobs==0 and ended==0 and not a:isPlaying(),'stop leaves nothing scheduled and no on_end')

a:seek(1.5);assert(a:position()==1.5,'seek sets the stopped position (saved position restored on reopen)')

-- WAV slice (Mac path): header + PCM from offset up to `to`
local w=A.wav(5,'0123456789',2,6)
assert(#w==44+4 and w:sub(1,4)=='RIFF' and w:sub(9,12)=='WAVE' and w:sub(45)=='2345','wav slice bytes')
assert(w:byte(25)==5 and w:byte(41)==4,'rate and data size')
os.execute('rm -rf '..bin)
print('PASS: ielts audio player (Kindle gst route, seek, to, position, pause, stop, on_end, WAV slice)')
