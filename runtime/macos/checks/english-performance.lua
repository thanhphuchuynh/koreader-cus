package.path=assert(arg[1])..'/?.lua;'..package.path
local tick,shown,records=0,{},{}
package.loaded['ui/time']={now=function()return tick end,to_ms=function(t)return t end}
package.loaded['datastorage']={getSettingsDir=function()return '/unused-test-settings'end}
package.loaded['luasettings']={open=function()return {
 readSetting=function(_,key,default)return records[key] or default end,
 saveSetting=function(_,key,value)records[key]=value end,flush=function()end,
}end}
package.loaded['ui/uimanager']={show=function(_,v)shown[#shown+1]=v end,forceRePaint=function()tick=tick+7 end,nextTick=function(_,fn)fn()end}
package.loaded['ui/widget/infomessage']={new=function(_,v)return v end}
package.loaded['ui/trapper']={wrap=function(_,fn)fn()end}
package.loaded.english_popup={show=function(options)tick=tick+5;return {close_popup=function()end,options=options}end}
local rolling={onGotoViewRel=function(_,diff)tick=tick+10;return diff==1 end}
local original=rolling.onGotoViewRel
local plugin={ui={rolling=rolling,dictionary={enabled_dict_names={'Test'},startSdcv=function()tick=tick+125;return {{definition='Example'}}end}}}
local perf=require('english_perf').new(plugin)
assert(rolling.onGotoViewRel==original,'normal reading must not be instrumented by default')
perf:checkLookup()
assert(records.measurements.lookup_ms==125 and records.measurements.popup_ms==12)
perf:armPageTurn()
assert(rolling.onGotoViewRel~=original)
rolling:onGotoViewRel(0);assert(rolling.onGotoViewRel~=original,'non-turn events must not consume the one-shot measurement')
assert(rolling:onGotoViewRel(1)==true)
assert(rolling.onGotoViewRel==original and records.measurements.page_ms==17,'page hook must restore itself and preserve handler return')
print('PASS: opt-in lookup/popup timing; one-shot page timing restores handler; no background instrumentation')
