-- Small native Kindle speech test. No shell commands, network, voice downloads or pairing changes.
-- Uses KOReader's bundled LIPC binding and the playermgr TTS protocol documented by:
-- https://github.com/stradichenko/audiobook.koplugin/blob/52b8e6e97d5fa3071364394944ba902f452c229f/docs/PLATFORM_AUDIO.md
local M={}
function M.new()
 local Device=require('device')
 local UI=require('ui/uimanager')
 local time=require('ui/time')
 local self={}
 local handle,poll,completion,playing,started,heard,owns_session
 local function finish(err,stop)
  if not handle and not playing then return end
  if poll then UI:unschedule(poll);poll=nil end
  if handle then
   if owns_session then
    if stop then pcall(handle.set_string_property,handle,'com.lab126.playermgr','Stop','')end
    pcall(handle.set_string_property,handle,'com.lab126.playermgr','Close','')
   end
   pcall(handle.close,handle);handle=nil
  end
  owns_session=false
  playing=false
  local callback=completion;completion=nil
  if callback then callback(err) end
 end
 function self:available()return type(Device.isKindle)=='function' and Device:isKindle()end
 function self:isSpeaking()return playing==true end
 function self:stop()finish(nil,true)end
 function self:speak(text,on_done)
  if not self:available() then return nil,'English speech requires a supported Kindle and paired Bluetooth audio.' end
  if type(text)~='string' or not text:find('%S') or text:find('%z') or #text>2000 then
   return nil,'Select a short English word or passage for speech (up to 2 KB).'
  end
  self:stop()
  local ok=pcall(function()
   handle=assert(require('liblipclua').init('com.github.koreadercus.speech'))
   -- Probe before opening a session; unsupported firmware should fail without playback.
   handle:get_int_property('com.lab126.playermgr','TTS_State')
   handle:set_string_property('com.lab126.playermgr','Stop','')
   handle:set_string_property('com.lab126.audiomgrd','setFocus','tts')
   handle:set_string_property('com.lab126.playermgr','Open',require('json').encode{type='TTS'})
   owns_session=true
   handle:set_string_property('com.lab126.playermgr','PlayParameter',require('json').encode{
    type='TTS',data={paramName='textsource',paramValue=text},
   })
   handle:set_string_property('com.lab126.playermgr','Play','')
   heard=handle:get_int_property('com.lab126.playermgr','TTS_State')>0
  end)
  if not ok then
   finish(nil,true)
   return nil,'Kindle native speech is unavailable. Pair Bluetooth audio first; this firmware may need another speech engine.'
  end
  completion=on_done;playing=true;started=time.now()
  poll=function()
   if not playing or not handle then return end
   local valid,state=pcall(handle.get_int_property,handle,'com.lab126.playermgr','TTS_State')
   if not valid or type(state)~='number' then finish('Could not read the Kindle speech state.',true);return end
   if state>0 then heard=true elseif heard then finish(nil,false);return end
   local elapsed=time.to_ms(time.now()-started)
   if not heard and elapsed>5000 then
    finish('Native speech did not start. Check the Bluetooth connection; this Kindle may need another speech engine.',true);return
   end
   if elapsed>180000 then finish('Speech stopped after the time limit.',true);return end
   UI:scheduleIn(0.2,poll)
  end
  UI:scheduleIn(0.2,poll)
  return true
 end
 return self
end
return M
