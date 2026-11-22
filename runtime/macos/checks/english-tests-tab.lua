-- Tests tab wiring in main.lua: SimpleUI module registration, one-time tab setup, Start/Review/Retry. arg[1] = plugin dir.
package.path=assert(arg[1])..'/?.lua;'..package.path
local f=assert(io.open(arg[1]..'/../../../../ielts-sample.json'));local KEY=f:read('*a');f:close()
local shown,closed,soon={},{},{}
local function runSoon() local q=soon;soon={};for _,fn in ipairs(q) do fn() end end
local UI={show=function(_,w) shown[#shown+1]=w end,close=function(_,w) closed[#closed+1]=w end,
  scheduleIn=function(_,t,fn) if t<60 then soon[#soon+1]=fn end end,unschedule=function() end,setDirty=function() end}
local Widget={};function Widget:new(t) t=t or {};t.handleEvent=t.handleEvent or function() end;t.getSize=function() return {w=100,h=40} end;return t end
package.preload['ui/widget/container/widgetcontainer']=function() return {extend=function(_,t) return t end} end
package.preload['ui/uimanager']=function() return UI end
package.preload['ui/widget/textviewer']=function() return Widget end
package.preload['ui/widget/dictquicklookup']=function() return {buildButtonLayout=function() return {} end} end
package.preload['device']=function() return {screen={getWidth=function() return 600 end,getHeight=function() return 800 end,scaleBySize=function(_,s) return s end}} end
for _,n in ipairs({'infomessage','confirmbox'}) do package.preload['ui/widget/'..n]=function() return Widget end end
local panels={}
package.preload['english_ielts_panel']=function() return {show=function(o) panels[#panels+1]=o end} end
package.preload['english_popup']=function() return {show=function() return {} end} end
local opened={}
package.preload['apps/reader/readerui']=function() return {showReader=function(_,p) opened[#opened+1]=p end} end
local function store() local s={} return {readSetting=function(_,k) return s[k] end,saveSetting=function(_,k,v) s[k]=v end,
  isTrue=function(_,k) return s[k]==true end,flush=function() s._flushed=(s._flushed or 0)+1 end,data=s} end
local sidecars={}
package.preload['docsettings']=function() return {open=function(_,p) sidecars[p]=sidecars[p] or store();return sidecars[p] end} end
G_reader_settings=store()

local Preview=assert(loadfile(arg[1]..'/main.lua'))()
local function fm() local p=setmetatable({ui={menu={registerToMainMenu=function() end}}},{__index=Preview});p:init();return p end

-- No SimpleUI: nothing happens, nothing breaks.
fm()
assert(G_reader_settings.data.leaf_tests_tab_done==nil,'no SimpleUI: tab setup not marked done')
print('PASS: without SimpleUI the file manager starts and nothing is registered')

-- Fake SimpleUI.
local registered,screens,sui,tabs,max,qas={},{},{},{'homescreen','home','history','sui_settings'},6,{}
package.preload['modules/moduleregistry']=function() return {register=function(m) registered[#registered+1]=m end} end
package.preload['infra/sui_custom_screens']=function() return {
  create=function(name) local s={id='cs_'..(#screens+1),name=name};s.pfx='simpleui_cs_'..s.id..'_';s.layout_key='simpleui_layout_cs_'..s.id
    screens[#screens+1]=s;qas['open_custom_screen:'..s.id]=true;return s end,
  get=function(id) for _,s in ipairs(screens) do if s.id==id then return s end end end,
  qaId=function(id) return 'open_custom_screen:'..id end} end
local failAfter -- set: reading the tabs throws (a setup that fails half-way)
package.preload['infra/sui_store']=function() return {
  readSetting=function(_,k) if k=='simpleui_bar_tabs' then if failAfter then error('boom') end return tabs end return sui[k] end,
  saveSetting=function(_,k,v) sui[k]=v end,flush=function() end} end
local cache
-- Like sui_config: Custom Screen tabs whose Quick Action is not registered yet are dropped.
package.preload['infra/sui_config']=function() return {
  loadTabConfig=function()
    if not cache then cache={};for _,t in ipairs(tabs) do if not t:match('^open_custom_screen:') or qas[t] then cache[#cache+1]=t end end end
    return cache end,
  saveTabConfig=function(t) cache=nil;tabs={unpack(t)} end,
  effectiveMaxTabs=function() return max end} end

fm()
assert(#registered==1 and registered[1].id=='leaf_tests','module registered')
local s=assert(screens[1],'screen created')
assert(#screens==1 and s.name=='Tests')
assert(sui[s.pfx..'leaf_tests_enabled']==true,'module enabled on the screen')
local layout=sui[s.layout_key]
assert(layout.pages[1].id==1 and layout.pages[1].modules[1]=='leaf_tests' and #layout.pages[1].modules==1,'layout saved')
local qa='open_custom_screen:'..s.id
assert(table.concat(tabs,',')==table.concat({'homescreen',qa,'home','history','sui_settings'},','),'tab after Home: '..table.concat(tabs,','))
assert(G_reader_settings.data.leaf_tests_tab_done==true and G_reader_settings.data._flushed,'flag set and flushed')
print('PASS: first start creates the Tests screen with the module and puts its tab right after Home')

fm()
assert(#registered==1,'registered once per process')
assert(#screens==1 and tabs[2]==qa and #tabs==5,'second start changes nothing')
-- The user removes the tab; Leaf must not add it back.
table.remove(tabs,2);cache=nil
fm()
assert(#screens==1 and #tabs==4,'removed tab is not re-added')
print('PASS: setup runs once; a tab the user removed stays removed')

-- Full bar (page-arrows mode: 4 tabs max).
G_reader_settings=store();max=4;tabs={'homescreen','home','history','sui_settings'};cache=nil
local before=#shown
fm();fm()
assert(#screens==2 and #tabs==4 and tabs[2]=='home','full bar: nothing replaced')
assert(#shown==before+1 and shown[#shown].text=='The tab bar is full. Add "Tests" from SimpleUI → Tab bar.','hint shown once')
print('PASS: full tab bar replaces nothing and shows the hint once')

-- No Home tab: Tests goes first.
G_reader_settings=store();max=6;tabs={'home','history'};cache=nil
fm()
assert(tabs[1]=='open_custom_screen:'..screens[3].id and tabs[2]=='home','no Home: Tests first')
print('PASS: without Home the Tests tab goes first')

-- Actions.
local A=registered[1].actions
A.open('/b/IELTS/t1.epub')
assert(opened[#opened]=='/b/IELTS/t1.epub','Start/Continue opens the test')
-- Retry: confirm, then clear answers keeping the mode, then open.
sidecars['/b/IELTS/t2.epub']=store()
sidecars['/b/IELTS/t2.epub'].data.leaf_ielts={mode='practice',answers={'x'},elapsed=99,finished=true,margins_added=true}
local n=#opened
A.retry('/b/IELTS/t2.epub')
local box=shown[#shown]
assert(box.text=='Clear your answers for this test and start again?' and box.ok_text=='Retry' and box.cancel_text=='Cancel','retry confirm copy')
assert(#opened==n and sidecars['/b/IELTS/t2.epub'].data.leaf_ielts.finished,'nothing cleared before confirm')
box.ok_callback()
local rec=sidecars['/b/IELTS/t2.epub'].data.leaf_ielts
assert(rec.mode=='practice' and next(rec.answers)==nil and rec.elapsed==0 and not rec.finished,'cleared except mode')
assert(rec.margins_added==true,'retry keeps the margins flag, so margins are not added twice')
assert(sidecars['/b/IELTS/t2.epub'].data._flushed,'sidecar flushed')
assert(opened[#opened]=='/b/IELTS/t2.epub','retry opens the test')
print('PASS: Retry asks, clears answers keeping the mode, then opens the test')

-- Review: the reader opened for that book shows the results.
local function reader(path,rec)
  local st=store();st.data.leaf_ielts=rec
  local ui={menu={registerToMainMenu=function() end},rolling={},doc_settings=st,dictionary={addToDictButtons=function() end},
    document={file=path,getDocumentFileContent=function() return KEY end}}
  local p=setmetatable({ui=ui},{__index=Preview});p:init();p:onReaderReady();return p
end
local done={mode='practice',answers={},elapsed=10,finished=true}
reader('/b/IELTS/t3.epub',done);runSoon()
assert(#panels==0,'opening a finished test normally shows no results')
A.review('/b/IELTS/t3.epub')
assert(opened[#opened]=='/b/IELTS/t3.epub','review opens the test')
local rp=reader('/b/IELTS/t3.epub',done)
assert(#panels==0 and #soon==1,'review results deferred until the reader is on screen')
runSoon()
assert(#panels==1 and panels[1].results==true,'review shows results')
runSoon();assert(#panels==1,'fires once')
reader('/b/IELTS/t3.epub',done);runSoon()
assert(#panels==1,'review applies once')
-- Reader closed before the deferred display: nothing shown.
A.review('/b/IELTS/t3.epub');rp=reader('/b/IELTS/t3.epub',done);rp:onCloseDocument();runSoon()
assert(#panels==1,'closed reader shows nothing')
print('PASS: Review opens the test and shows its results once')

-- Other Custom Screen tabs survive the first run, though SimpleUI has not registered their QAs yet.
G_reader_settings=store();max=6;tabs={'homescreen','open_custom_screen:cs_old','home','history'};cache=nil
fm()
local tq='open_custom_screen:'..screens[#screens].id
assert(table.concat(tabs,',')==table.concat({'homescreen',tq,'open_custom_screen:cs_old','home','history'},','),'kept: '..table.concat(tabs,','))
print('PASS: first run keeps the other Custom Screen tabs')

-- A run that failed half-way: the next run reuses its screen.
G_reader_settings=store();tabs={'homescreen','home'};cache=nil
local count=#screens
failAfter=true;fm();failAfter=nil
assert(#screens==count+1 and not G_reader_settings.data.leaf_tests_tab_done,'half-way run made a screen, not done')
fm()
assert(#screens==count+1,'screen reused, not duplicated')
assert(tabs[2]=='open_custom_screen:'..screens[#screens].id and #tabs==3 and G_reader_settings.data.leaf_tests_tab_done,'tab added on retry')
print('PASS: a half-way failed setup reuses its screen next time')

-- A Review whose book opens as a non-test (or non-EPUB) never applies to a later open.
A.review('/b/IELTS/t3.epub')
local ui={menu={registerToMainMenu=function() end},dictionary={addToDictButtons=function() end},document={file='/b/IELTS/t3.epub'}}
local p=setmetatable({ui=ui},{__index=Preview});p:init();p:onReaderReady()
reader('/b/IELTS/t3.epub',done);runSoon()
assert(#panels==1,'stale review not applied')
print('PASS: a pending Review is consumed by the next open, whatever it is')
