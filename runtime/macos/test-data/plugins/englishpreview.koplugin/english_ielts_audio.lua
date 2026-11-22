-- Listening-test audio: raw 16-bit mono PCM streamed from a byte offset (dd) into the Kindle's
-- gst-launch -> mixersink (the route english_voca verified); the Mac preview plays a WAV slice with afplay.
local V=require('english_voca')
local M={}
local WAV='/tmp/leaf-ielts-audio.wav'
M.now=function()return V.now() end

local function q(s)return "'"..tostring(s):gsub("'","'\\''").."'" end
local function le(n,bytes)local t={};for i=1,bytes do t[i]=string.char(n%256);n=math.floor(n/256) end return table.concat(t) end

-- 16-bit mono WAV of pcm bytes [from,to) (byte offsets); pure, for the Mac path and checks.
function M.wav(rate,pcm,from,to)
 local data=pcm:sub(from+1,to)
 return 'RIFF'..le(36+#data,4)..'WAVEfmt '..le(16,4)..le(1,2)..le(1,2)..le(rate,4)..le(rate*2,4)..le(2,2)..le(16,2)..'data'..le(#data,4)..data
end

function M.new(o)
 local UI=require('ui/uimanager')
 local self={on_end=nil}
 local pid,poll,start,began,limit,frozen=nil,nil,0,0,nil,0
 local function halt()
  if poll then UI:unschedule(poll);poll=nil end
  if pid then os.execute('kill '..pid..' 2>/dev/null');pid=nil end
 end
 function self._pid()return pid end
 function self:isPlaying()return pid~=nil end
 function self:position()
  if not pid then return frozen end
  -- the first 0.5 s on the Kindle is silent lead-in
  local p=start+math.max(0,M.now()-began-(o.kindle and 0.5 or 0))
  return math.min(p,limit)
 end
 function self:seek(p)if not pid then frozen=p end end -- restore a saved position while stopped
 function self:stop()local p=self:position();halt();frozen=p end
 function self:pause()
  local p=self:position();halt();frozen=p;return p
 end
 function self:play(from,to)
  halt()
  from=math.max(0,math.min(from or 0,o.seconds-1/o.rate))
  to=to and math.min(to,o.seconds) or nil
  if to and to<=from then return nil end
  local command,skip
  if o.kindle then
   local v=V.gstVersion();if not v then return nil end
   V.musicFocus()
   local caps=v=='0.10'
    and ('audio/x-raw-int,endianness=1234,signed=true,width=16,depth=16,rate=%d,channels=1'):format(o.rate)
    or ('audio/x-raw,format=S16LE,rate=%d,channels=1,layout=interleaved'):format(o.rate)
   -- 10 ms blocks give sub-second seek; 0.5 s lead-in (A2DP wake-up) and 1 s tail (mixer ring) of silence as in english_voca.
   skip=math.floor(from*100+1e-6)
   local count=to and math.ceil(to*100-1e-6)-skip or nil
   if count and count<1 then return nil end
   limit=count and (skip+count)/100 or o.seconds
   command='( dd if=/dev/zero bs='..o.rate..' count=1 ; dd if='..q(o.path)..' bs='..math.floor(o.rate/50)..' skip='..skip
    ..(count and ' count='..count or '')..' ; dd if=/dev/zero bs='..(o.rate*2)..' count=1 ) 2>/dev/null | '
    ..q(V.bin_dir..'/gst-launch-'..v)..' fdsrc ! capsfilter caps='..q(caps)..' ! mixersink stream-type=Music sync=true'
  else
   local f=io.open(o.path,'rb');if not f then return nil end
   local pcm=f:read('*a');f:close()
   local w=io.open(WAV,'wb');if not w then return nil end
   w:write(M.wav(o.rate,pcm,math.floor(from*o.rate)*2,to and math.floor(to*o.rate)*2 or #pcm));w:close()
   command=q(V.bin_dir..'/afplay')..' '..q(WAV)
  end
  -- $! is the last pipeline command (gst); killing it ends dd by SIGPIPE.
  pid=V.spawn(command)
  if not pid then return nil end
  start=skip and skip/100 or from
  began,frozen=M.now(),start
  if not skip then limit=to or o.seconds end
  local function tick()
   poll=nil
   if not pid then return end
   if V.alive(pid) then poll=tick;UI:scheduleIn(0.5,tick);return end
   pid=nil;frozen=limit
   if self.on_end then self.on_end() end
  end
  poll=tick;UI:scheduleIn(0.5,tick)
  return true
 end
 return self
end
return M
