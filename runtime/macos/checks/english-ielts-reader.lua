-- IELTS wiring in main.lua: detection, bars, margins, panel, word pick, evidence, time-up. arg[1] = plugin dir.
package.path=assert(arg[1])..'/?.lua;'..package.path
local J=require('json')
local f=assert(io.open(arg[1]..'/../../../../ielts-sample.json'));local raw=f:read('*a');f:close()
local d=J.decode(raw);for _,p in ipairs(d.passages) do p.paragraphs=nil end
local KEY=J.encode(d)
local clock=1000;os.time=function() return clock end
trace=nil
local shown,closed,scheduled,unscheduled,dirty,ticks={},{},{},0,0,{}
local UI={show=function(_,w,mode,region,x,y) shown[#shown+1]=w;w._at={x=x,y=y} end,close=function(_,w) closed[#closed+1]=w end,
  scheduleIn=function(_,s,fn) scheduled[#scheduled+1]={s,fn} end,nextTick=function(_,fn) ticks[#ticks+1]=fn end,unschedule=function() unscheduled=unscheduled+1 end,
  setDirty=function(_,w,mode) dirty=dirty+1;if trace then trace[#trace+1]='dirty:'..tostring(w)..':'..tostring(mode) end end}
local Widget={};function Widget:new(t) t=t or {};t.handleEvent=t.handleEvent or function() end;t.getSize=function() return {w=100,h=40} end;return t end
package.preload['ui/widget/container/widgetcontainer']=function() return {extend=function(_,t) return t end} end
package.preload['ui/uimanager']=function() return UI end
package.preload['ui/widget/textviewer']=function() return Widget end
package.preload['ui/widget/dictquicklookup']=function() return {buildButtonLayout=function() return {} end} end
package.preload['device']=function() return {isKindle=function() return false end,screen={getWidth=function() return 600 end,getHeight=function() return 800 end,scaleBySize=function(_,s) return s end}} end
for _,n in ipairs({'container/inputcontainer','container/framecontainer','verticalgroup','textboxwidget','buttontable','infomessage','inputdialog','horizontalgroup','textwidget','button'}) do
  package.preload['ui/widget/'..n]=function() return Widget end
end
package.preload['ui/font']=function() return {getFace=function() return {} end} end
package.preload['ffi/blitbuffer']=function() return {COLOR_WHITE=255} end
local panels,popups,panelBoom={},{},false
local refreshes,dialogsClosed=0,0
package.preload['english_ielts_panel']=function() return {show=function(o) if panelBoom then error('bad test') end;panels[#panels+1]=o
  local w={panel=true,updateAudio=function() refreshes=refreshes+1 end,closeDialog=function() dialogsClosed=dialogsClosed+1 end};o.widget=w;if o.on_open then o.on_open(w) end;return w end} end
package.preload['english_popup']=function() return {show=function(o) popups[#popups+1]=o;return {} end} end
local bars,confirms={},{}
package.preload['english_ielts_bars']=function() return {
  overlay=function(o) local h={o=o}
    function h:update(n) assert(not self.closed,'update after close');self.o=n;self.updates=(self.updates or 0)+1 end
    function h:heights() return 48,48 end
    function h:close() self.closed=true end
    bars[#bars+1]=h;return h end,
  confirmFinish=function(on_yes) confirms[#confirms+1]=on_yes end} end
local function live() local b=bars[#bars];return b and not b.closed and b or nil end
local function margins(r) local k=0 for _,e in ipairs(r.events) do if e.handler:find('Margin') then assert(e.handler=='onSetPageTopAndBottomMargin','one combined margin event');k=k+1 end end return k end
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
    onHold=function(h) local w=r.word or 'reluctantly';h.selected_text={text=w,pos0='p0:'..w,pos1='p1:'..w};return true end,
    _resetHoldTimer=function() end,
    lookupDictWord=function(h) r.tapped=h.selected_text.text end,
  }
  local footer={addAdditionalFooterContent=function(_,fn) r.added[#r.added+1]=fn end,
    removeAdditionalFooterContent=function(_,fn) for i,v in ipairs(r.added) do if v==fn then table.remove(r.added,i) end end end,
    TapFooter=function() r.footerTaps=r.footerTaps+1;return 'native' end,maybeUpdateFooter=function() end}
  r.footer=footer;r.highlight=highlight;r.store=store()
  r.passage='Boca Grande replaced its white lamps with ‘amber’ ones'
  local doc={file=r.file,getWordFromPosition=function() return {sbox={x=280,y=200,w=100,h=40}} end,
    getDocumentFileContent=function(_,p) assert(p=='META-INF/leaf-ielts.json');return content end,
    getXPointer=function() return '/body/DocFragment['..r.frag..']/body/p[2]/text().0' end,
    getCurrentPage=function() return r.page end,
    clearSelection=function() r.cleared=r.cleared+1;r.selected=false end,
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
      local h=r.hits(pat);if #h>0 then r.selected=true;return h end
    end}
  r.frag=1;r.page=7;r.other='Only the second passage mentions coral reefs here.'
  r.hits=function(pat)
    if r.other:find(pat,1,true) then return {{start='/body/DocFragment[2]/body/p[5]/text().0'}} end
    if not r.passage:find(pat,1,true) then return {} end
    return {{start='/body/DocFragment[1]/body/p[3]/text().4',['end']='/body/DocFragment[1]/body/p[3]/text().40'},{start='/body/DocFragment[2]/body/p[1]/text().0',['end']='/body/DocFragment[2]/body/p[1]/text().9'}}
  end
  r.events={}
  local typeset={unscaled_margins={10,15,10,20},configurable={t_page_margin=15,b_page_margin=20}}
  r.ui={menu={registerToMainMenu=function() end},typeset=typeset,handleEvent=function(_,e) r.events[#r.events+1]=e;if r.boom then error('boom') end
    if e.handler=='onSetPageTopAndBottomMargin' then typeset.unscaled_margins[2],typeset.unscaled_margins[4]=e.args[1][1],e.args[1][2] end
    return true end,highlight=highlight,document=doc,doc_settings=r.store,
    dictionary={addToDictButtons=function() end},view={footer=footer},
    link={addCurrentLocationToStack=function() r.stacked=(r.stacked or 0)+1 end}}
  -- Like ReaderRolling: the jump emits PageUpdate synchronously.
  r.ui.rolling={onGotoXPointer=function(_,xp) r.gotos[#r.gotos+1]=xp;r.page=r.jumpTo or r.page
    if trace then trace[#trace+1]='goto' end;r.plugin:onPageUpdate(r.page) end}
  doc.getTextFromXPointers=function(_,a,b,draw) if draw then r.drawn=a..'|'..b end;if trace then trace[#trace+1]='draw:'..a..':'..b..':'..tostring(draw) end end
  r.plugin=setmetatable({ui=r.ui},{__index=Preview})
  r.plugin:init()
  r.tap=function(word) r.word=word;return highlight:onTap(nil,{pos={x=300,y=220}}) end
  return r
end

-- Non-test books: nothing changes (no bars, no margins, native footer and taps).
for _,content in ipairs({false,'{','{"version":2}'}) do
  local r=reader(content or nil)
  r.plugin:onReaderReady()
  assert(r.plugin._ielts==nil and #r.added==0 and #popups==0 and #bars==0 and #r.events==0,'non-test must not add ielts state')
  assert(r.tap('reluctantly')==true and r.tapped=='reluctantly','non-test tap still opens dictionary')
  assert(r.footer:TapFooter()=='native' and r.footerTaps==1,'non-test footer tap stays native')
  r.plugin:onCloseDocument()
end
print('PASS: non-test books: no bars, no margins, dictionary tap and native footer')

-- A test: mode prompt first, then bars and margins; the footer is left alone.
local r=reader(KEY)
r.plugin:onReaderReady()
local st=assert(r.plugin._ielts,'test detected')
assert(#r.added==0 and r.footer:TapFooter()=='native' and r.footerTaps==1,'no footer content, footer tap stays native')
assert(live()==nil,'bars wait for the mode choice')
local prompt=assert(popups[#popups],'mode prompt shown')
local function closePrompt() if prompt.on_close then prompt.on_close() end end
local row=prompt.buttons(closePrompt)[1]
assert(row[1].text=='Practice' and row[2].text=='Study')
row[1].callback()
assert(st.session:mode()=='practice')
local bar=assert(live(),'bars shown after mode choice')
assert(bar.o.tab=='passage' and bar.o.timer=='20:00' and not bar.o.pick,'passage tab, practice timer')
local m=r.ui.typeset.unscaled_margins
assert(m[1]==10 and m[2]==15+48 and m[3]==10 and m[4]==20+48,'bar heights added to user margins: '..table.concat(m,','))
assert(r.ui.typeset.configurable.t_page_margin==63 and r.ui.typeset.configurable.b_page_margin==68,'margins saved with the book')
assert(r.store.data.leaf_ielts.margins_added==true,'margins remembered')
assert(margins(r)==1,'one top-and-bottom margin event')
clock=clock+65
scheduled[#scheduled][2]()
assert(live()==bar and bar.o.timer=='18:55','minute tick refreshes the timer: '..tostring(bar.o.timer))
-- Input outside the bars goes to the reader; reader errors are contained.
local ev={handler='onGesture',args={{pos={x=300,y=300}}}}
local nev=#r.events
assert(bar.o.forward(ev)==true and r.events[#r.events]==ev and #r.events==nev+1,'forwarded to the reader')
r.boom=true;assert(not bar.o.forward(ev),'reader error contained');r.boom=nil
-- Questions → opens the panel at the current chapter; the reader bars close meanwhile.
bar.o.on_questions()
assert(bar.closed and live()==nil and panels[#panels].passage==1,'Questions opens the panel, bars closed')
panels[#panels].on_passage()
bar=assert(live(),'back to the passage: bars again')
assert(bar.o.tab=='passage' and margins(r)==1,'margins not added again')
panelBoom=true;r.plugin:showQuestions();panelBoom=false
assert(live(),'a panel error leaves the bars up')
-- Finish asks first; Cancel leaves the test running, Finish scores.
bar=live()
local nc,np=#confirms,#panels
bar.o.on_finish()
assert(#confirms==nc+1 and not st.session:finished() and st.session.startedAt,'Finish asks, nothing scored yet')
assert(#panels==np and live()==bar,'Cancel: still on the passage')
confirms[#confirms]()
assert(st.session:finished() and st.session.startedAt==nil,'Finish pauses and finishes')
assert(#panels==np+1 and panels[#panels].results==true and live()==nil,'results shown')
st.session.rec.finished=nil;st.session:start(clock)
panels[#panels].on_passage()
-- One-word gap: tap "amber," fills Q5, no dictionary, word highlighted, panel reopened.
local n0=#panels
panels[#panels].on_pick(5,{x=0,y=120})
bar=assert(live())
assert(st.picking==5 and bar.o.pick==5 and bar.o.on_done and bar.o.on_cancel,'pick form in the top bar')
assert(r.tap('amber,')==true and st.session:answer(5)=='amber','one-word pick')
assert(r.tapped==nil and r.clears>=1,'pick must not open the dictionary and must clear the selection')
assert(r.drawn=='p0:amber,|p1:amber,','picked word highlighted: '..tostring(r.drawn))
assert(st.picking==nil and #panels==n0+1 and panels[#panels].offset.y==120 and live()==nil,'one-word gap returns to the panel at the same scroll')
-- Two-word gap: two taps keep picking; Cancel restores the answer from before.
st.session:setAnswer(6,'old')
panels[#panels].on_pick(6)
r.tap('motion');r.tap('“sensors”')
assert(st.session:answer(6)=='old motion sensors' and st.picking==6 and live().o.pick==6,'two-word pick keeps picking')
assert(r.drawn=='p0:“sensors”|p1:“sensors”','last picked word highlighted')
local n1,cl=#panels,r.cleared
live().o.on_cancel()
assert(st.session:answer(6)=='old' and st.picking==nil,'Cancel restores the previous answer')
assert(#panels==n1+1 and r.cleared>cl and live()==nil,'Cancel returns to the panel and clears the highlight')
st.session:setAnswer(6,'')
panels[#panels].on_pick(6)
r.tap('sensors’');r.tap('don’t.')
assert(st.session:answer(6)=="sensors' don't",'bare word: apostrophes kept like answer matching, other edges stripped')
n1=#panels
live().o.on_done()
assert(st.picking==nil and #panels==n1+1 and panels[#panels].passage and r.tapped==nil and st.session:answer(6)=="sensors' don't",'Done returns to the panel')
panels[#panels].on_passage()
-- Questions from English tools mid-pick ends the pick.
panels[#panels].on_pick(5);r.plugin:showQuestions();assert(st.picking==nil,'Questions mid-pick ends the pick')
panels[#panels].on_passage()
-- After picking, taps look up words again.
assert(r.tap('reluctantly')==true and r.tapped=='reluctantly')
-- A failing pick must not break tapping.
st.picking=99;r.tapped=nil
assert(r.tap('word')==true and r.tapped==nil,'pick errors are contained')
st.picking=nil
-- No keyboard anywhere.
local src=assert(io.open(arg[1]..'/main.lua')):read('*a')
assert(not src:find('Type instead',1,true) and not src:find('ieltsType',1,true) and not src:find('ieltsBanner',1,true),'no Type instead')
assert(not walk(shown,function(t) return t.text=='Type instead' end),'no Type instead shown')
print('PASS: mode prompt then bars and margins, Questions/Finish from the bars, tap-only blanks with Cancel/Done')

-- Evidence: straight-quote evidence finds a curly-quote passage, only inside the question's chapter.
r.frag=2
panels[#panels].on_evidence({n=5,evidence="replaced its white lamps with 'amber' ones"})
assert(r.gotos[#r.gotos]=='/body/DocFragment[1]/body/p[3]/text().4','evidence jump in passage chapter: '..tostring(r.gotos[#r.gotos]))
assert(live() and live().o.tab=='passage','Show in passage brings the bars back')
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
-- Second Show in passage from another page keeps its new highlight (PageUpdate fires during the jump).
r.jumpTo=20;panels[#panels].on_evidence({n=5,evidence="replaced its white lamps with 'amber' ones"})
assert(r.selected and r.page==20,'first jump highlighted')
trace={}
r.jumpTo=30;panels[#panels].on_evidence({n=5,evidence="replaced its white lamps with 'amber' ones"})
assert(r.selected and r.page==30,'second jump must keep its highlight')
assert(table.concat(trace,'|')=='goto|draw:/body/DocFragment[1]/body/p[3]/text().4:/body/DocFragment[1]/body/p[3]/text().40:true|dirty:nil:ui',
  'jump, draw the selection, repaint like ReaderSearch: '..table.concat(trace,'|'))
assert(r.stacked and r.stacked>0,'Go back location kept')
trace={}
r.plugin:onPageUpdate(31);assert(not r.selected,'turn after second jump clears')
assert(trace[1]=='dirty:nil:ui','clearing repaints');trace=nil
-- A hit only in another chapter: not shown, and its stray highlight is cleared.
before=#shown;local g=#r.gotos
panels[#panels].on_evidence({n=5,evidence='Only the second passage mentions coral reefs'})
assert(#r.gotos==g and #shown==before+1 and r.selected==false,'other-chapter hit cleared, not shown')
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
-- Reopen: onReaderReady runs before the reader is shown, so the bars wait a tick (or the reader covers them).
local nb,nt=#bars,#ticks
local r2=reader(KEY);r2.store.data.leaf_ielts=r.store.data.leaf_ielts;r2.plugin:onReaderReady()
assert(r2.plugin._ielts and r2.plugin._ielts.session.startedAt==nil,'reopen after Finish must not restart the clock')
assert(#bars==nb and #ticks==nt+1,'no bars during onReaderReady, one task scheduled')
ticks[#ticks]()
local b2=assert(#bars==nb+1 and live(),'mode already chosen: bars shown on the next tick')
local r4=reader(KEY);r4.store.data.leaf_ielts=r.store.data.leaf_ielts;r4.plugin:onReaderReady();r4.plugin:onCloseDocument()
nb=#bars;ticks[#ticks]();assert(#bars==nb,'closed before the tick: no bars')
assert(margins(r2)==0 and r2.ui.typeset.unscaled_margins[2]==15,'margins added once across loads')
r2.plugin:onCloseDocument()
assert(b2.closed and r2.plugin._ielts==nil,'close closes the bars')
st.session.rec.finished=nil;st.session:start(clock)
-- Suspend/close persist elapsed; close removes footer and restores native taps.
-- the reader of r is current again
r.plugin:showIeltsBars()
local b1=assert(live())
r.plugin:onSuspend();local e=st.session.rec.elapsed;clock=clock+500
assert(live()==b1,'suspend leaves the bars (under the screensaver)')
nb=#bars;local nu=b1.updates or 0
r.plugin:onResume();clock=clock+10
assert(live()==b1 and #bars==nb and b1.updates==nu+1,'resume refreshes the bars in place')
-- Suspended in pick mode: the pick form stays.
panels[#panels].on_pick(6)
r.plugin:onSuspend();r.plugin:onResume()
assert(live()==b1 and b1.o.pick==6 and #bars==nb,'resume keeps the pick form')
live().o.on_cancel()
-- Suspended while the panel is open: resume creates no bars.
r.plugin:onSuspend();r.plugin:onResume()
assert(live()==nil and #bars==nb,'no bars over the questions panel after resume')
panels[#panels].on_passage()
local b3=assert(live())
r.plugin:onCloseDocument()
assert(b3.closed and live()==nil,'close closes the bars')
assert(st.session.rec.elapsed==e+10,'suspended time is not counted')
assert(#r.added==0 and r.plugin._ielts==nil and unscheduled>0,'close cleans up')
assert(r.footer:TapFooter()=='native','footer tap native after close')
print('PASS: time-up message once, suspend/resume/close keep elapsed, bars kept over suspend and refreshed on resume, margins once')

-- IELTS Listening wiring
local dir=os.tmpname();os.remove(dir);os.execute('mkdir -p '..dir)
local pf=io.open(dir..'/a.pcm','wb');pf:write('x');pf:close()
local audios={}
package.preload['english_ielts_audio']=function() return {new=function(o)
  local a={o=o,calls={},playing=false,pos=0}
  function a:play(f,t) self.calls[#self.calls+1]={'play',f,t};self.playing=true;self.pos=f or 0;return true end
  function a:pause() self.calls[#self.calls+1]={'pause'};self.playing=false;return self.pos end
  function a:seek(p) self.pos=p end
  function a:stop() self.calls[#self.calls+1]={'stop'};self.playing=false end
  function a:position() return self.pos end
  function a:isPlaying() return self.playing end
  audios[#audios+1]=a;return a end} end
local spoke,speech={}, {}
package.preload['english_speech']=function() return {new=function() return {available=function() return true end,isSpeaking=function() return false end,stop=function() speech.stops=(speech.stops or 0)+1 end,
  speak=function(_,t) spoke[#spoke+1]=t;return true end} end} end
package.preload['english_voca']=function() return {new=function() return {available=function() return false end,isSpeaking=function() return false end,stop=function() end} end} end
local LKEY=J.encode{version=1,skill='listening',title='Section 1',minutes=30,audio={file='a.pcm',rate=16000,seconds=300},
  questions={{n=1,type='gap',words=1,answer='x',at={10,20}},{n=2,type='gap',words=1,answer='y'}}}
local function lreader(file,rec)
  local r=reader(LKEY);r.ui.document.file=file;r.store.data.leaf_ielts=rec
  r.plugin:onReaderReady()
  return r
end
local function find120() for i=#scheduled,1,-1 do if scheduled[i][1]==120 then return scheduled[i] end end end
local function lastCall(a) return a.calls[#a.calls] end
-- first open: prompt Exam/Study (after the tick), then the panel and the audio from 0
local nb,na,npop=#bars,#audios,#popups
local lr=lreader(dir..'/l.epub')
local lst=lr.plugin._ielts
assert(lst and #popups==npop and #panels>=0,'prompt waits for the tick')
ticks[#ticks]()
local pr=popups[#popups]
assert(#popups==npop+1 and pr.title=='IELTS Listening' and pr.buttons(function() end)[1][1].text=='Exam' and pr.buttons(function() end)[1][2].text=='Study','mode prompt copy')
assert(#bars==nb and #audios==na+1,'no reading bars; audio built')
local au=audios[#audios]
assert(au.o.path==dir..'/a.pcm' and au.o.rate==16000 and au.o.seconds==300 and au.o.kindle==false,'audio path beside the book: '..au.o.path)
local np=#panels
pr.buttons(function() if pr.on_close then pr.on_close() end end)[1][1].callback()
assert(lst.session:mode()=='practice' and #panels==np+1 and #bars==nb,'Exam: questions panel, no bars')
local lp=panels[#panels]
assert(lp.audio and au.calls[1][1]=='play' and au.calls[1][2]==0,'exam plays from 0')
assert(lp.exam_left()==420,'exam_left = seconds - pos + 120: '..lp.exam_left())
au.pos=100;assert(lp.exam_left()==320)
assert(lst.panel==lp.widget,'open panel tracked')
-- Hear it plays at[1]..at[2]+1; starting audio stops speech
lr.plugin:getSpeech();speech.stops=0;lp.on_hear({at={10,20}})
assert(lastCall(au)[1]=='play' and lastCall(au)[2]==10 and lastCall(au)[3]==21,'on_hear range')
assert(speech.stops>0,'test audio stops speech')
-- Listen during test audio stops test audio
au.playing=true
lr.plugin:getSpeech():speak('hello')
assert(lastCall(au)[1]=='stop' and spoke[#spoke]=='hello','speech stops test audio')
-- Study first open plays too; Study reopen stays paused (below)
do local sr=lreader(dir..'/l.epub');ticks[#ticks]()
  local sp=popups[#popups];sp.buttons(function() if sp.on_close then sp.on_close() end end)[1][2].callback()
  local sa=audios[#audios]
  assert(sr.plugin._ielts.session:mode()=='study' and sa.calls[1][1]=='play' and sa.calls[1][2]==0,'Study first open plays')
  sr.plugin:onCloseDocument() end
-- suspend saves position and stops, resume plays on (exam)
au.pos=100;au.playing=true
lr.plugin:onSuspend()
assert(lastCall(au)[1]=='stop' and lst.session:audioPos()==100 and lst.session.startedAt==nil,'suspend: stop, save pos, pause clock')
lr.plugin:onResume()
assert(lastCall(au)[1]=='play' and lastCall(au)[2]==100,'resume plays on in exam')
-- audio ends: pos=end, open panel updated in place, countdown = check time, auto-finish 120 s later
local rf,np0=refreshes,#panels
au.playing=false;au.pos=300;au.on_end()
assert(lst.session:audioPos()==300 and refreshes==rf+1 and #panels==np0,'ended: position saved, panel updated in place')
assert(lp.exam_left()==120,'check time counts down from 2:00')
local auto=assert(find120(),'auto-finish scheduled at 120 s')
clock=clock+50;assert(lp.exam_left()==70,'countdown follows the clock')
-- suspend in the check window: unscheduled, left saved; resume re-arms the remainder (not a fresh 120)
local un0=unscheduled
lr.plugin:onSuspend();assert(unscheduled>un0 and lst.session:checkLeft()==70,'suspend saves check time')
clock=clock+500
lr.plugin:onResume();assert(scheduled[#scheduled][1]==70 and lp.exam_left()==70,'resume re-arms the remainder')
scheduled[#scheduled][1]=70
clock=clock+70;assert(lp.exam_left()==0,'never negative')
clock=clock+10;assert(lp.exam_left()==0,'never negative')
np=#panels;local dc=dialogsClosed
auto=scheduled[#scheduled]
auto[2]()
assert(dialogsClosed==dc+1,'auto-finish closes an open gap dialog')
assert(lst.session:finished() and lst.session.startedAt==nil and panels[#panels].results==true and #panels==np+1,'auto-finish scores')
assert(closed[#closed]==lp.widget,'old panel closed before results')
-- Finish by hand stops audio and cancels the auto-finish
local lr2=lreader(dir..'/l.epub',{mode='practice',answers={},elapsed=0,audio_pos=50});ticks[#ticks]()
local au2=audios[#audios]
assert(au2.calls[1][1]=='play' and au2.calls[1][2]==50,'reopen exam: plays from saved position')
local un=unscheduled;panels[#panels].on_finish()
assert(lastCall(au2)[1]=='stop' and unscheduled>un,'on_finish stops audio and unschedules')
-- Reopen exam after the audio ended: no playback, finishes 120 s later
local lr3=lreader(dir..'/l.epub',{mode='practice',answers={},elapsed=0,audio_pos=300,check_left=45});ticks[#ticks]()
local au3=audios[#audios]
assert(#au3.calls==0 and panels[#panels].exam_left()==45,'reopen after end: no play, saved check time left')
assert(scheduled[#scheduled][1]==45)
scheduled[#scheduled][2]()
assert(lr3.plugin._ielts.session:finished() and panels[#panels].results==true,'reopen after end finishes')
-- Try again: audio back to 0, check time cleared; exam plays again
local lr7=lreader(dir..'/l.epub',{mode='practice',answers={},elapsed=0,audio_pos=300,check_left=45,finished=true});ticks[#ticks]()
lr7.plugin:showQuestions();local au7=audios[#audios];local s7=lr7.plugin._ielts.session
s7:reset();panels[#panels].on_retry()
assert(s7:audioPos()==0 and s7:checkLeft()==nil and lastCall(au7)[1]=='play' and lastCall(au7)[2]==0,'Try again (exam) plays from 0')
lr7.plugin:onCloseDocument()
local lr8=lreader(dir..'/l.epub',{mode='study',answers={},elapsed=0,audio_pos=300,finished=true});ticks[#ticks]()
lr8.plugin:showQuestions();local au8=audios[#audios];local s8=lr8.plugin._ielts.session
s8:reset();panels[#panels].on_retry()
assert(au8.pos==0 and s8:audioPos()==0 and lastCall(au8)[1]~='play','Try again (study) stays paused at 0')
lr8.plugin:onCloseDocument()
-- Study: paused until play; saved position kept
local lr4=lreader(dir..'/l.epub',{mode='study',answers={},elapsed=0,audio_pos=50});ticks[#ticks]()
local au4=audios[#audios]
assert(#au4.calls==0 and panels[#panels].audio==au4,'study reopen: panel shown, audio paused')
au4.pos=70;au4.playing=true;lr4.plugin:onSuspend()
lr4.plugin:onResume();assert(lastCall(au4)[1]=='stop','study stays paused on resume')
au4.playing=true;lr4.plugin:onCloseDocument()
assert(lastCall(au4)[1]=='stop' and lr4.store.data.leaf_ielts.audio_pos==70,'close stops audio and saves position')
-- Missing audio file: message, panel opens
local lr5=lreader(dir..'/none/l.epub');ticks[#ticks]()
local pr5=popups[#popups];np=#panels
pr5.buttons(function() end)[1][2].callback();pr5.on_close()
local info;for _,w in ipairs(shown) do if w.text=='Audio file not found: a.pcm' then info=w end end
assert(info,'missing audio message')
assert(#panels==np+1 and panels[#panels].audio==nil and panels[#panels].exam_left==nil and lr5.plugin._ielts.session:mode()=='study','test opens without audio')
-- Finished: reading bars labelled Transcript; Hear it works
nb=#bars
local lr6=lreader(dir..'/l.epub',{mode='practice',answers={},elapsed=0,finished=true});ticks[#ticks]()
assert(#bars==nb+1 and live().o.passage_label=='Transcript' and live().o.timer==nil,'finished: Transcript bars, no reading timer')
lr6.plugin:showQuestions();local au6=audios[#audios];panels[#panels].on_hear({at={30,40}})
assert(lastCall(au6)[2]==30 and lastCall(au6)[3]==41,'Hear it after finish')
lr6.plugin:onCloseDocument()
os.execute('rm -rf '..dir)
print('PASS: listening wiring: prompt, audio path, suspend/resume/close, auto-finish, missing audio, transcript bars')
