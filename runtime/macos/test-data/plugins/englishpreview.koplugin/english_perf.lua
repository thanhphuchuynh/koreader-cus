-- Explicit, one-shot checks. No timers or measurement hooks during normal reading.
local M={}
function M.new(plugin)
 local UI=require('ui/uimanager')
 local Info=require('ui/widget/infomessage')
 local Popup=require('english_popup')
 local time=require('ui/time')
 local store=require('luasettings'):open(require('datastorage'):getSettingsDir()..'/english-performance.lua')
 local measurements=store:readSetting('measurements',{})
 local self={}
 local function info(text)UI:show(Info:new{text=text})end
 local function save(name,value)
  measurements[name]=value
  measurements.arch=jit.arch;measurements.os=jit.os;measurements.measured_at=os.date('!%Y-%m-%dT%H:%M:%SZ')
  store:saveSetting('measurements',measurements);store:flush()
 end
 function self:show()
  local lines={'Software timings on this device ('..(measurements.arch or jit.arch)..').',
   'Includes rendering and refresh submission; it does not measure complete E Ink settling.'}
  for _,metric in ipairs({{'lookup_ms','Exact dictionary lookup'},{'popup_ms','Popup creation + paint'},{'page_ms','Page event + paint'}})do
   lines[#lines+1]=metric[2]..': '..(measurements[metric[1]] and string.format('%.1f ms',measurements[metric[1]]) or 'Not measured')
  end
  if measurements.measured_at then lines[#lines+1]='Last check: '..measurements.measured_at end
  return Popup.show{title='Performance checks',text=table.concat(lines,'\n\n'),buttons=function(close)return {{{text='Close',callback=close}}}end}
 end
 function self:checkLookup()
  local dictionary=plugin.ui.dictionary
  if not dictionary or (dictionary.enabled_dict_names and #dictionary.enabled_dict_names==0) then info('Enable an offline dictionary first.');return end
  require('ui/trapper'):wrap(function()
   local start=time.now()
   local ok,results=pcall(dictionary.startSdcv,dictionary,'example',dictionary.enabled_dict_names,false)
   local elapsed=time.to_ms(time.now()-start)
   if not ok or not results or results.lookup_cancelled then info('Dictionary check failed or was cancelled.');return end
   save('lookup_ms',elapsed)
   start=time.now()
   local probe=Popup.show{title='Checking popup',text='Measuring creation and painting…',buttons=function(close)return {{{text='Close',callback=close}}}end}
   UI:forceRePaint()
   local popup_ms=time.to_ms(time.now()-start)
   probe:close_popup(true)
   save('popup_ms',popup_ms)
   self:show()
  end)
 end
 function self:armPageTurn()
  local controller=plugin.ui.rolling or plugin.ui.paging
  if not controller or not controller.onGotoViewRel then info('Open a book first.');return end
  if self.armed then info('The next page turn is already armed.');return end
  local original=controller.onGotoViewRel
  self.armed=true
  controller.onGotoViewRel=function(owner,diff,...)
   if diff~=1 and diff~=-1 then return original(owner,diff,...) end
   controller.onGotoViewRel=original;self.armed=false
   local start=time.now()
   local result=original(owner,diff,...)
   UI:forceRePaint()
   save('page_ms',time.to_ms(time.now()-start))
   UI:nextTick(function()self:show()end)
   return result
  end
  info('Close this message, then turn one page. The measurement runs once and is saved locally.')
 end
 return self
end
return M
