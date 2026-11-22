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
  local p=start+M.now()-began
  return limit and math.min(p,limit) or math.min(p,o.seconds)
 end
 function self:stop()halt();frozen=self:position() end
 function self:pause()
  local p=self:position();halt();frozen=p;return p
 end
 function self:play(from,to)
  halt()
  from=math.max(0,math.min(from or 0,o.seconds-1/o.rate))
  to=to and math.min(to,o.seconds) or nil
  if to and to<=from then return nil end
  local command
  if o.kindle then
   local v=V.gstVersion();if not v then return nil end
   V.musicFocus()
   local caps=v=='0.10'
    and ('audio/x-raw-int,endianness=1234,signed=true,width=16,depth=16,rate=%d,channels=1'):format(o.rate)
    or ('audio/x-raw,format=S16LE,rate=%d,channels=1,layout=interleaved'):format(o.rate)
   local count=to and (' count='..math.ceil(to-math.floor(from))) or ''
   command='dd if='..q(o.path)..' bs='..(o.rate*2)..' skip='..math.floor(from)..count..' 2>/dev/null | '
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
  start,began,limit,frozen=from,M.now(),to,from
  local function tick()
   poll=nil
   if not pid then return end
   if V.alive(pid) then poll=tick;UI:scheduleIn(0.5,tick);return end
   pid=nil;frozen=to or o.seconds
   if self.on_end then self.on_end() end
  end
  poll=tick;UI:scheduleIn(0.5,tick)
  return true
 end
 return self
end
return M
