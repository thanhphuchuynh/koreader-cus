-- Offline neural English speech: tiny-voca (Rust "voca", github.com/sultson/voca) writes a WAV,
-- then the Kindle plays raw PCM through its own gst-launch -> mixersink -> Bluetooth.
-- That playback route is the one audiobook.koplugin verified on Kindle Basic (AGPL-3.0).
-- The Mac preview plays the WAV with afplay. Text goes through a file, never the shell.
local M={}
local TMP='/tmp/leaf-speech'
M.bin_dir='/usr/bin' -- system tools; replaced by checks

local function q(s)return "'"..tostring(s):gsub("'","'\\''").."'" end
local function exists(path)local f=io.open(path,'rb');if f then f:close();return true end end
local function ok(status)return status==0 or status==true end

-- 16-bit PCM WAV -> raw PCM with 0.5 s silence before (A2DP wake-up swallows the start)
-- and 1 s after (the mixer ring and BT chain still hold audio at end of stream).
function M.pcm(wav)
 if type(wav)~='string' or #wav<44 or wav:sub(1,4)~='RIFF' or wav:sub(9,12)~='WAVE' then return nil,'not a WAV file' end
 local function u16(o)return wav:byte(o)+wav:byte(o+1)*256 end
 local function u32(o)return u16(o)+u16(o+2)*65536 end
 local format,channels,rate,bits=u16(21),u16(23),u32(25),u16(35)
 if format~=1 or bits~=16 or channels<1 or channels>2 or rate==0 then return nil,'unsupported WAV format' end
 local frame=channels*2
 return string.rep('\0',math.floor(rate/2)*frame)..wav:sub(45)..string.rep('\0',rate*frame),rate,channels,(#wav-44)/(rate*frame)
end

function M.new(dir)
 local Device=require('device')
 local UI=require('ui/uimanager')
 local bin,data=dir..'/voca/voca',dir..'/voca/data'
 local self={}
 local pid,poll,completion,playing,generation=nil,nil,nil,false,0
 local function kindle()return type(Device.isKindle)=='function' and Device:isKindle() end
 local function gst()
  for _,version in ipairs({'0.10','1.0'})do
   if exists(M.bin_dir..'/gst-launch-'..version)then return version end
  end
 end
 local function player()
  if kindle() then return gst() end
  if require('ffi').os=='OSX' and exists(M.bin_dir..'/afplay') then return 'afplay' end
 end
 local function spawn(command)
  local h=io.popen(command..' >/dev/null 2>&1 & echo $!')
  local out=h and h:read('*a') or '';if h then h:close() end
  return tonumber(out:match('%d+'))
 end
 local procfs=exists('/proc/self/stat')
 local function alive(id)
  if not id then return false end
  if procfs then return exists('/proc/'..id..'/stat') end
  return ok(os.execute('kill -0 '..id..' 2>/dev/null'))
 end
 local function finish(err)
  if poll then UI:unschedule(poll);poll=nil end
  pid=nil;playing=false
  local callback=completion;completion=nil
  if callback then callback(err) end
 end
 -- Calls next() when the current process exits; kills it after the deadline.
 local function wait(deadline,next,my)
  poll=function()
   poll=nil
   if my~=generation then return end
   if alive(pid) then
    if os.time()>deadline then os.execute('kill '..pid..' 2>/dev/null');finish('Speech took too long and was stopped.');return end
    return wait(deadline,next,my)
   end
   next()
  end
  UI:scheduleIn(0.15,poll)
 end
 function self:available()return exists(bin) and exists(data..'/tiny-voca.safetensors') and player()~=nil end
 function self:isSpeaking()return playing end
 function self:stop()
  if not playing then return end
  generation=generation+1
  if pid then os.execute('kill '..pid..' 2>/dev/null') end
  finish(nil)
 end
 function self:speak(text,on_done,on_start)
  if not self:available() then return nil,'Offline voice is not installed.' end
  if type(text)~='string' or not text:find('%S') or text:find('%z') or #text>2000 then
   return nil,'Select a short English word or passage for speech (up to 2 KB).'
  end
  self:stop()
  os.execute('mkdir -p '..q(TMP))
  local input,wav,raw=TMP..'/in.txt',TMP..'/out.wav',TMP..'/out.pcm'
  os.remove(wav);os.remove(raw)
  local f=io.open(input,'wb');if not f then return nil,'Could not prepare speech.' end
  f:write(text);f:close()
  pid=spawn('VOCA_HOME='..q(data)..' '..q(bin)..' -f '..q(input)..' -o '..q(wav))
  if not pid then return nil,'Could not start the offline voice.' end
  generation=generation+1
  local my=generation
  playing=true;completion=on_done
  wait(os.time()+60,function()
   local w=io.open(wav,'rb');local bytes=w and w:read('*a');if w then w:close() end
   local pcm,rate,channels,seconds=M.pcm(bytes)
   if not pcm then finish('Could not generate speech.');return end
   local command
   local how=player()
   if how=='afplay' then
    command=q(M.bin_dir..'/afplay')..' '..q(wav)
   else
    local o=io.open(raw,'wb');if not o then finish('Could not prepare speech audio.');return end
    o:write(pcm);o:close()
    pcall(function()
     local lipc=assert(require('liblipclua').init('com.github.koreadercus.speech'))
     lipc:set_string_property('com.lab126.audiomgrd','setFocus','Music');lipc:close()
    end)
    local caps=how=='0.10'
     and ('audio/x-raw-int,endianness=1234,signed=true,width=16,depth=16,rate=%d,channels=%d'):format(rate,channels)
     or ('audio/x-raw,format=S16LE,rate=%d,channels=%d,layout=interleaved'):format(rate,channels)
    command=q(M.bin_dir..'/gst-launch-'..how)..' filesrc location='..q(raw)..' ! capsfilter caps='..q(caps)
     ..' ! mixersink stream-type=Music sync=true'
   end
   pid=spawn(command)
   if not pid then finish('Could not play speech.');return end
   if on_start then on_start() end
   wait(os.time()+math.ceil(seconds)+10,function()finish(nil)end,my)
  end,my)
  return true
 end
 return self
end
return M
