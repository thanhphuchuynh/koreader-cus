-- IELTS wiring in main.lua: detection, footer, panel, word pick, evidence, time-up. arg[1] = plugin dir.
package.path=assert(arg[1])..'/?.lua;'..package.path
local J=require('json')
local f=assert(io.open(arg[1]..'/../../../../ielts-sample.json'));local raw=f:read('*a');f:close()
local d=J.decode(raw);for _,p in ipairs(d.passages) do p.paragraphs=nil end
local KEY=J.encode(d)
local clock=1000;os.time=function() return clock end
local shown,closed,scheduled,unscheduled,dirty={},{},{},0,0
local UI={show=function(_,w) shown[#shown+1]=w end,close=function(_,w) closed[#closed+1]=w end,
  scheduleIn=function(_,s,fn) scheduled[#scheduled+1]={s,fn} end,unschedule=function() unscheduled=unscheduled+1 end,
  setDirty=function() dirty=dirty+1 end}
local Widget={};function Widget:new(t) t=t or {};t.handleEvent=t.handleEvent or function() end;return t end
package.preload['ui/widget/container/widgetcontainer']=function() return {extend=function(_,t) return t end} end
package.preload['ui/uimanager']=function() return UI end
package.preload['ui/widget/textviewer']=function() return Widget end
package.preload['ui/widget/dictquicklookup']=function() return {buildButtonLayout=function() return {} end} end
package.preload['device']=function() return {screen={getWidth=function() return 600 end,getHeight=function() return 800 end,scaleBySize=function(_,s) return s end}} end
for _,n in ipairs({'container/inputcontainer','container/framecontainer','verticalgroup','textboxwidget','buttontable','infomessage','inputdialog'}) do
  package.preload['ui/widget/'..n]=function() return Widget end
end
package.preload['ui/font']=function() return {getFace=function() return {} end} end
package.preload['ffi/blitbuffer']=function() return {COLOR_WHITE=255} end
local panels,popups={},{}
package.preload['english_ielts_panel']=function() return {show=function(o) panels[#panels+1]=o;return {panel=true} end} end
package.preload['english_popup']=function() return {show=function(o) popups[#popups+1]=o;return {} end} end
local Preview=assert(loadfile(arg[1]..'/main.lua'))()

local function walk(x,fn,seen) seen=seen or {}
  if type(x)~='table' or seen[x] then return end seen[x]=true
  if fn(x) then return x end
  for _,v in pairs(x) do local r=walk(v,fn,seen) if r then return r end end
end
local function store() local s={} return {readSetting=function(_,k) return s[k] end,saveSetting=function(_,k,v) s[k]=v end,data=s} end

local function reader(content)
  local r={tapped=nil,clears=0,footerTaps=0,added={},gotos={},cleared=0}
  local highlight={
    clear=function(h) r.clears=r.clears+1;h.selected_text=nil end,
    view={screenToPageTransform=function(_,p) return p end},
    onTap=function() end,
    onHold=function(h) h.selected_text={text=r.word or 'reluctantly'};return true end,
    _resetHoldTimer=function() end,
    lookupDictWord=function(h) r.tapped=h.selected_text.text end,
  }
  local footer={addAdditionalFooterContent=function(_,fn) r.added[#r.added+1]=fn end,
    removeAdditionalFooterContent=function(_,fn) for i,v in ipairs(r.added) do if v==fn then table.remove(r.added,i) end end end,
    TapFooter=function() r.footerTaps=r.footerTaps+1;return 'native' end,maybeUpdateFooter=function() end}
  r.footer=footer;r.highlight=highlight;r.store=store()
  r.passage='Boca Grande replaced its white lamps with ‘amber’ ones'
  local doc={getWordFromPosition=function() return {sbox={x=280,y=200,w=100,h=40}} end,
    getDocumentFileContent=function(_,p) assert(p=='META-INF/leaf-ielts.json');return content end,
    getXPointer=function() return '/body/DocFragment['..r.frag..']/body/p[2]/text().0' end,
    getCurrentPage=function() return 7 end,
    clearSelection=function() r.cleared=r.cleared+1 end,
    -- Like cre.cpp: findText only searches from/around the current position (reverse=dir==1);
    -- findAllText searches the whole book.
    findText=function(_,pat,origin,reverse)
      local hits={}
      for _,h in ipairs(r.hits(pat)) do
        local k=tonumber(h.start:match('DocFragment%[(%d+)%]'))
        local after=(reverse and origin==-1) or (not reverse and origin~=-1)
        if after and k>=r.frag or not after and k<=r.frag then hits[#hits+1]=h end
      end
      return #hits>0 and hits or nil
    end,
    findAllText=function(_,pat,ci,ctx,max,regex)
      assert(ci==true and max>0 and not regex)
      local h=r.hits(pat);return #h>0 and h or nil
    end}
  r.frag=1
  r.hits=function(pat)
    if not r.passage:find(pat,1,true) then return {} end
    return {{start='/body/DocFragment[1]/body/p[3]/text().4'},{start='/body/DocFragment[2]/body/p[1]/text().0'}}
  end
  r.events={}
  r.ui={menu={registerToMainMenu=function() end},handleEvent=function(_,e) r.events[#r.events+1]=e;if r.boom then error('boom') end;return true end,rolling=true,highlight=highlight,document=doc,doc_settings=r.store,
    dictionary={addToDictButtons=function() end},view={footer=footer},
    link={onGotoLink=function(_,l) r.gotos[#r.gotos+1]=l.xpointer end}}
  r.plugin=setmetatable({ui=r.ui},{__index=Preview})
  r.plugin:init()
  r.tap=function(word) r.word=word;return highlight:onTap(nil,{pos={x=300,y=220}}) end
  return r
end

-- Non-test books: nothing changes.
for _,content in ipairs({false,'{','{"version":2}'}) do
  local r=reader(content or nil)
  r.plugin:onReaderReady()
  assert(r.plugin._ielts==nil and #r.added==0 and #popups==0,'non-test must not add ielts state')
  assert(r.tap('reluctantly')==true and r.tapped=='reluctantly','non-test tap still opens dictionary')
  assert(r.footer:TapFooter()=='native' and r.footerTaps==1,'non-test footer tap stays native')
  r.plugin:onCloseDocument()
end
print('PASS: non-test books keep dictionary tap and native footer, no ielts state')

-- A test: footer, mode prompt, timer.
local r=reader(KEY)
r.plugin:onReaderReady()
local st=assert(r.plugin._ielts,'test detected')
assert(#r.added==1 and r.added[1]()=='Q 0/6','study/no mode footer')
local prompt=assert(popups[#popups],'mode prompt shown')
local row=prompt.buttons(function() end)[1]
assert(row[1].text=='Practice' and row[2].text=='Study')
row[1].callback()
assert(st.session:mode()=='practice' and r.added[1]()=='Q 0/6 · 20:00','practice footer '..r.added[1]())
clock=clock+65
assert(r.added[1]()=='Q 0/6 · 18:55')
-- Footer tap opens the panel at the current chapter.
assert(r.footer:TapFooter()==true and r.footerTaps==0 and panels[#panels].passage==1,'footer tap opens panel')
-- One-word gap: tap "amber," fills Q5, no dictionary, panel reopened.
local n0=#panels
panels[#panels].on_pick(5,{x=0,y=120})
assert(st.picking==5 and walk(shown[#shown],function(t) return t.text=='Q5 · tap words in the passage' end),'banner shown')
assert(r.tap('amber,')==true and st.session:answer(5)=='amber','one-word pick')
assert(r.tapped==nil and r.clears>=1,'pick must not open the dictionary and must clear the selection')
assert(st.picking==nil and #panels==n0+1 and panels[#panels].offset.y==120,'one-word gap returns to the panel at the same scroll')
-- Two-word gap: two taps, still picking until Done.
panels[#panels].on_pick(6)
r.tap('motion');r.tap('“sensors”')
assert(st.session:answer(6)=='motion sensors' and st.picking==6,'two-word pick keeps picking')
assert(walk(shown[#shown],function(t) return t.text=='Q6 · motion sensors' end),'banner shows answer')
local function bannerButton(l) return walk(shown[#shown],function(t) return t.text==l and t.callback end).callback end
bannerButton('Clear')()
assert(st.session:answer(6)=='' and st.picking==6)
r.tap('sensors’');r.tap('don’t.')
assert(st.session:answer(6)=="sensors don't",'bare word: curly apostrophe kept inside, edges stripped')
local n1=#panels
bannerButton('Done')()
assert(st.picking==nil and #panels==n1+1 and r.tapped==nil,'Done returns to panel')
-- After picking, taps look up words again.
assert(r.tap('reluctantly')==true and r.tapped=='reluctantly')
-- A failing pick must not break tapping.
st.picking=99;r.tapped=nil
assert(r.tap('word')==true and r.tapped==nil,'pick errors are contained')
st.picking=nil
-- Banner: input outside it goes to the reader; its own area, broadcasts and reader errors stay put.
panels[#panels].on_pick(6)
local b=st.banner
local function pos(inside) return {intersectWith=function() return inside end} end
b.dimen={}
assert(b:handleEvent({handler='onGesture',args={{pos=pos(false)}}})==true and #r.events==1,'tap outside forwarded')
assert(b:handleEvent({handler='onGesture',args={{pos=pos(true)}}})==true and #r.events==1,'tap on banner kept')
assert(b:handleEvent({handler='onKeyPress',args={}})==true and #r.events==2,'key page turn forwarded')
assert(not b:handleEvent({handler='onPageUpdate',args={}}) and #r.events==2,'broadcasts not doubled')
r.boom=true;assert(not b:handleEvent({handler='onKeyPress',args={}}),'reader error contained');r.boom=nil
bannerButton('Done')()
print('PASS: test footer and mode prompt, footer tap opens panel, word pick fills gaps without dictionary')

-- Evidence: straight-quote evidence finds a curly-quote passage, only inside the question's chapter.
r.frag=2
panels[#panels].on_evidence({n=5,evidence="replaced its white lamps with 'amber' ones"})
assert(r.gotos[#r.gotos]=='/body/DocFragment[1]/body/p[3]/text().4','evidence jump in passage chapter: '..tostring(r.gotos[#r.gotos]))
local c=r.cleared
r.plugin:onPageUpdate(7);assert(r.cleared==c,'same page keeps highlight')
r.plugin:onPageUpdate(8);assert(r.cleared==c+1,'page turn clears evidence highlight')
r.plugin:onPageUpdate(9);assert(r.cleared==c+1)
local before=#shown
panels[#panels].on_evidence({n=5,evidence='not in the passage'})
assert(#shown==before+1 and #panels>0,'missing evidence says so')
before=#shown
panels[#panels].on_evidence({n=5,evidence="with 'amber' ones"})
assert(#shown==before+1 and #r.gotos==1,'short quote-free fallback must not match a stray fragment')
r.frag=1
print('PASS: evidence found book-wide across quote styles in its chapter, cleared on page turn')

-- Time up: once.
local function infos() local k=0 for _,w in ipairs(shown) do if w.text=='Time is up — you can keep answering.' then k=k+1 end end return k end
assert(scheduled[1][1]==60)
scheduled[1][2]();assert(infos()==0)
clock=clock+20*60
scheduled[#scheduled][2]();assert(infos()==1,'time up shown')
scheduled[#scheduled][2]();assert(infos()==1,'time up shown once')
-- Finished tests stop the clock: resume and reopen do not restart it.
st.session:finish();st.session:pause(clock);r.plugin:onResume()
assert(st.session.startedAt==nil,'resume after Finish must not restart the clock')
local r2=reader(KEY);r2.store.data.leaf_ielts=r.store.data.leaf_ielts;r2.plugin:onReaderReady()
assert(r2.plugin._ielts and r2.plugin._ielts.session.startedAt==nil,'reopen after Finish must not restart the clock')
r2.plugin:onCloseDocument()
st.session.rec.finished=nil;st.session:start(clock)
-- Suspend/close persist elapsed; close removes footer and restores native taps.
r.plugin:onSuspend();local e=st.session.rec.elapsed;clock=clock+500;r.plugin:onResume();clock=clock+10
r.plugin:onCloseDocument()
assert(st.session.rec.elapsed==e+10,'suspended time is not counted')
assert(#r.added==0 and r.plugin._ielts==nil and unscheduled>0,'close cleans up')
assert(r.footer:TapFooter()=='native','footer tap native after close')
print('PASS: time-up message once, suspend/resume/close keep elapsed and clean up')
