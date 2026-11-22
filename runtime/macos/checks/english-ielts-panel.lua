package.path=assert(arg[1])..'/?.lua;'..package.path
local J=require('json')
local I=require('english_ielts')
local f=assert(io.open(arg[1]..'/../../../../ielts-sample.json'));local raw=f:read('*a');f:close()
local shown={}
local modes={}
local dialogs,dirty,sched,unsched={},{},{},{}
local UI={show=function(_,w,mode) if w.is_dialog then dialogs[#dialogs+1]=w else shown[#shown+1]=w;modes[#modes+1]=mode end end,close=function() end,
  setDirty=function(_,w,mode,r) dirty[#dirty+1]={w,mode,r} end,
  scheduleIn=function(_,sec,fn) sched[#sched+1]={sec,fn} end,unschedule=function(_,fn) unsched[#unsched+1]=fn end}
local Widget={}
function Widget:new(t) t=t or {};t.setText=function(self,x) self.text=x end;return t end
local Scroll={}
function Scroll:new(t) t=t or {};t.off={x=0,y=0};function t:getScrolledOffset() return self.off end;function t:setScrolledOffset(o) self.off=o end;return t end
local lastScroll
package.preload['ui/uimanager']=function() return UI end
package.preload['device']=function() return {screen={getWidth=function() return 600 end,getHeight=function() return 800 end,scaleBySize=function(_,s) return s end}} end
for _,n in ipairs({'container/inputcontainer','container/framecontainer','container/leftcontainer','button','horizontalgroup','verticalgroup','verticalspan','textboxwidget','textwidget','buttontable'}) do
  package.preload['ui/widget/'..n]=function() return Widget end
end
package.preload['ui/font']=function() return {getFace=function() return {} end} end
package.preload['ffi/blitbuffer']=function() return {COLOR_WHITE=255} end
package.preload['ui/geometry']=function() return Widget end
package.preload['ui/widget/container/scrollablecontainer']=function() return Scroll end
local boxes={}
package.preload['ui/widget/inputdialog']=function() return {new=function(_,t)
  t.is_dialog=true;t.getInputText=function() return t.typed end;t.onShowKeyboard=function() t.kb=true end;return t end} end
package.preload['ui/widget/confirmbox']=function() return {new=function(_,t) boxes[#boxes+1]=t;return t end} end
local P=require('english_ielts_panel')
local fin

local S=require('english_ielts_session')
local function store() local d={} return {readSetting=function(_,k) return d[k] end,saveSetting=function(_,k,v) d[k]=v end} end
-- depth-first search of the widget tree
local function walk(x,fn,seen) seen=seen or {}
  if type(x)~='table' or seen[x] then return end seen[x]=true
  if fn(x) then return x end
  for _,v in pairs(x) do local r=walk(v,fn,seen) if r then return r end end
end
local function button(label) local b=walk(shown[#shown],function(t) return t.text==label and t.callback end);return b and b.callback end
local function has(sub) return walk(shown[#shown],function(t) return type(t.text)=='string' and t.text:find(sub,1,true) end) end
fin=function() button('Finish')();boxes[#boxes].ok_callback() end
local d=J.decode(raw);for _,p in ipairs(d.passages) do p.paragraphs=nil end
local test=assert(I.parse(J.encode(d)))
local session=S.new(test,store());session:setMode('practice')
local picked,pickedOff,evidence,done
local opts={test=test,session=session,passage=1,now=function() return 0 end,
  on_pick=function(n,off) picked=n;pickedOff=off end,on_evidence=function(q) evidence=q end,on_passage=function() done=true end}
P.show(opts)
assert(walk(shown[#shown],function(t) return t.text=='Questions' and t.preselect end) and button('Passage') and button('Finish') and button('← Passage'),'bars: Questions tab selected, bottom ← Passage + Finish')
local dots=walk(shown[#shown],function(t) return type(t.text)=='string' and t.text:find('□',1,true) end)
assert(dots.text:find(' 0/6',1,true),'count text')
local _,a=dots.text:gsub('■','');local _,b=dots.text:gsub('□','');local count=a+b;assert(count==test.total,'dots='..count)
assert(not button('Passage 1') and not has('[ Passage'),'single passage: no switch')
local function selected(l) return walk(shown[#shown],function(t) return t.text==l and t.preselect end) end
assert(button('TRUE') and not selected('TRUE'))
shown[#shown]._scroll.off={x=0,y=250}
button('TRUE')()
assert(session:answer(1)=='TRUE' and selected('TRUE'),'selected must be preselected (inverted)')
assert(modes[1]=='full' and modes[#modes]=='ui','first open full refresh, in-panel taps ui')
assert(shown[#shown]._scroll.off.y==250 and shown[#shown].cropping_widget==shown[#shown]._scroll,'scroll kept, cropping_widget set')
button('B')();button('A')();button('C')()
assert(#session:answer(3)==2 and session:answer(3)[1]=='B','multi capped at picks')
button('B')();assert(#session:answer(3)==1)
local closedW,closedMode;UI.close=function(_,w,mode) closedW=w;closedMode=mode end
local before=shown[#shown];before._scroll.off={x=0,y=40}
assert(walk(shown[#shown],function(t) return t.text=='6  ____' end).align=='left','question rows are left-aligned')
button('6  ____')() ;assert(picked==6 and pickedOff.y==40 and closedW==before,'gap tap closes panel, passes scroll')
-- Leaving the panel for the passage must refresh the screen, or the panel ghosts on E Ink
-- (UIManager:close with no refresh type repaints the reader but never updates the display).
assert(closedMode=='full','gap tap → passage must refresh the screen')
P.show(opts);closedMode=nil
button('← Passage')();assert(done and closedMode=='full','← Passage must refresh the screen')
P.show(opts);closedMode=nil
button('Passage')();assert(closedMode=='full','Passage tab must refresh the screen')
session:setAnswer(5,'ember');session:setAnswer(6,'three big words');P.show(opts)
assert(has('ember') and has('three big words !'))
-- two-passage fixture shows the switch
local g={version=1,minutes=20,passages={{n=1,from=1,to=1},{n=2,from=2,to=2}},groups={{from=1,to=1,title='G1',instructions='i'},{from=2,to=2,title='G2',instructions='i'}},
  questions={{n=1,type='choice',options={'A','B'},answer='A',text='one'},{n=2,type='choice',options={'C','D'},answer='C',text='two'}}}
local t2=assert(I.parse(J.encode(g)));local s2=S.new(t2,store())
P.show({test=t2,session=s2,passage=1,on_pick=function()end,on_evidence=function()end,on_passage=function()end})
assert(walk(shown[#shown],function(t) return t.text=='Passage 1' and t.preselect end) and button('Passage 2') and has('G1') and not has('G2'))
button('Passage 2')();assert(has('G2') and not has('G1'))
-- 40 questions over 3 passages: dots only for the shown passage, plus overall count
local qs={};for i=1,40 do qs[i]={n=i,type='choice',options={'A','B'},answer='A',text='q'..i} end
local g6={version=1,minutes=60,passages={{n=1,from=1,to=13},{n=2,from=14,to=26},{n=3,from=27,to=40}},questions=qs}
local t6=assert(I.parse(J.encode(g6)));local s6=S.new(t6,store())
P.show({test=t6,session=s6,passage=2,on_pick=function()end,on_evidence=function()end,on_passage=function()end})
local dt=walk(shown[#shown],function(t) return type(t.text)=='string' and t.text:find('□',1,true) end).text
local _,n1=dt:gsub('□','');local _,n2=dt:gsub('■','')
assert(n1+n2<=14 and dt:find('0/40',1,true),'dots for the passage only + x/40: '..dt)
-- Study: no timer; Practice: bar frame height matches Bars.height
local Bars=require('english_ielts_bars')
local topf=shown[#shown][1][1][1]
assert(topf.height==Bars.height(),'top bar height')
assert(shown[#shown][1].width==600 and shown[#shown][1].height==800,'panel frame fills the screen')
local dotsRow=shown[#shown][1][1][2];assert(dotsRow.dimen and dotsRow.dimen.h==30 and dotsRow.dimen.w==600,'dots row has a fixed height')
local function timer(w) return walk(w,function(t) return type(t.text)=='string' and t.text:match('^%d%d:%d%d$') end) end
assert(not timer(shown[#shown]),'study: no timer')
local s7=S.new(test,store());s7:setMode('practice');s7:start(0)
P.show({test=test,session=s7,now=function() return 0 end,on_pick=function()end,on_evidence=function()end,on_passage=function()end})
assert(timer(shown[#shown]),'practice: timer shown')
-- results
P.show(opts);session:setAnswer(1,'TRUE');button('Finish')();assert(#boxes==1 and not session:finished(),'Finish asks first')
assert(not has('Band ≈'),'unconfirmed: no results')
boxes[1].ok_callback()
assert(has('/6') and has('Band ≈') and has('Time used 00:00') and has('✓ 1. TRUE'))
closedW=nil;button('Show in passage')();assert(evidence==test.byNumber[1] and closedW==shown[#shown],'evidence closes panel')
button('Try again')();assert(session:answered()==0 and button('Finish') and session.startedAt~=nil,'Try again restarts the clock')
assert(modes[#modes]=='ui','Try again redraw is ui')
fin();button('Done')();assert(done)
session:reset();P.show(opts);fin();assert(modes[#modes]=='full','entering results is a full refresh')
-- Time used counts real elapsed time, past the limit.
local s3=S.new(test,store());s3:setMode('practice');s3:start(0)
P.show({test=test,session=s3,now=function() return 1300 end,on_pick=function()end,on_evidence=function()end,on_passage=function()end})
fin();assert(has('Time used 21:40'),'time used not capped')
-- Gap prompt: text above, before ____ after on the row; answer replaces the blank, flagged when over the limit.
local g3={version=1,minutes=20,passages={{n=1,from=1,to=4}},groups={{from=3,to=3,title='G3',instructions='i'}},
  questions={{n=1,type='gap',words=1,text='Table: elephants',before='counts of elephant',after='at night',answer='footprints'},
    {n=2,type='choice',options={'X','Y'},answer='X',text='ungrouped choice'},
    {n=3,type='choice',options={'A','B'},answer='A',text='grouped'},{n=4,type='gap',words=1,before='tail',answer='end'}}}
local t3=assert(I.parse(J.encode(g3)));local s4=S.new(t3,store())
local o3={test=t3,session=s4,on_pick=function()end,on_evidence=function()end,on_passage=function()end}
P.show(o3)
assert(has('Table: elephants') and button('1  counts of elephant ____ at night') and button('4  tail ____'),'gap row shows its prompt')
assert(has('ungrouped choice') and button('X') and has('G3'),'ungrouped questions are drawn')
s4:setAnswer(1,'two words');P.show(o3);assert(button('1  counts of elephant two words ! at night'))
-- No groups at all: every question still shows.
local g4={version=1,minutes=20,passages={{n=1,from=1,to=2}},questions={{n=1,type='choice',options={'P','Q'},answer='P',text='first'},{n=2,type='gap',words=1,answer='z'}}}
local t4=assert(I.parse(J.encode(g4)))
P.show({test=t4,session=S.new(t4,store()),on_pick=function()end,on_evidence=function()end,on_passage=function()end})
assert(has('first') and button('P') and button('2  ____'),'test without groups shows its questions')
-- Numbering need not start at 1 (a single Part 2 file).
local g5={version=1,minutes=20,passages={{n=1,from=14,to=14}},questions={{n=14,type='choice',options={'A'},answer='A',text='later'}}}
local t5=assert(I.parse(J.encode(g5)))
P.show({test=t5,session=S.new(t5,store()),on_pick=function()end,on_evidence=function()end,on_passage=function()end})
assert(has('later'))
-- Listening form
local Ls={version=1,skill='listening',title='Section 1',minutes=30,audio={file='a.pcm',rate=16000,seconds=340},
  questions={{n=1,type='gap',words=2,before='Wanted:',after='today',answer='reporter',at={85,90}},
    {n=2,type='gap',words=1,answer='x'},{n=3,type='choice',options={'A','B'},answer='A',at={100,110}}}}
local lt=assert(I.parse(J.encode(Ls)))
local calls,pos,playing={},192,true
local audio={play=function(_,a,b) calls[#calls+1]={'play',a,b};playing=true;return true end,
  pause=function() calls[#calls+1]={'pause'};playing=false;return pos end,stop=function() end,
  position=function() return pos end,isPlaying=function() return playing end}
local left,heard=1720,nil
local ls=S.new(lt,store());ls:setMode('practice')
local lo={test=lt,session=ls,audio=audio,now=function() return 0 end,exam_left=function() return left end,
  on_pick=function() error('listening gaps use the keyboard') end,on_hear=function(q) heard=q end,on_evidence=function(q) evidence=q end,on_passage=function() done=true end}
local fh,retried;lo.on_finish=function() fh=true end;lo.on_retry=function() retried=true end
local function count(pat) local c=0;walk(shown[#shown],function(t) if type(t.text)=='string' and t.text:find(pat,1,true)==1 and t.callback then c=c+1 end end);return c end
P.show(lo)
assert(has('Section 1') and has('28:40') and has('▶ 03:12 / 05:40 · plays once') and button('Finish'),'exam: title, countdown, audio row')
assert(not button('Passage') and not button('Questions') and not button('← Passage') and not button('−10s') and count('↺')==0,'exam: no tabs, no controls, no replay')
ls:setMode('study');P.show(lo)
assert(button('−10s') and button('❚❚') and has('03:12 / 05:40') and not has('plays once') and not timer(shown[#shown]),'study row')
assert(count('↺')==2 and button('↺ 1:25') and button('↺ 1:40'),'replay only for questions with at')
button('−10s')();assert(calls[#calls][1]=='play' and calls[#calls][2]==182)
pos=5;button('−10s')();assert(calls[#calls][2]==0,'−10s clamps at 0');pos=192
button('❚❚')();assert(calls[#calls][1]=='pause' and button('▶') and not button('❚❚'),'toggle pauses and relabels')
button('▶')();assert(calls[#calls][1]=='play' and calls[#calls][2]==192 and button('❚❚'),'toggle resumes from position')
button('↺ 1:25')();assert(calls[#calls][1]=='play' and calls[#calls][2]==85)
-- discrete events update in place (never reopen the panel): -10s, and updateAudio() when the audio ends by itself
local opened;lo.on_open=function(w) opened=w end
playing=false;pos=192;P.show(lo);local n2=#shown
button('−10s')();assert(#shown==n2 and button('❚❚') and not button('▶'),'-10s updates the label in place')
playing=false;pos=340;opened:updateAudio()
assert(#shown==n2 and button('▶') and has('05:40 / 05:40'),'updateAudio after the audio ended: label and clock')
opened:onCloseWidget();opened:updateAudio();assert(#shown==n2,'closed panel: nothing')
lo.on_open=nil;pos=192;playing=true
-- missing audio file: the panel still opens
local na={};for k,v in pairs(lo) do na[k]=v end;na.audio=nil;na.exam_left=nil
ls:setMode('study');P.show(na);assert(has('Section 1') and button('Finish') and not button('−10s'),'study without audio')
ls:setMode('practice');P.show(na);assert(has('Section 1') and button('Finish'),'exam without audio')
-- gap → keyboard dialog
local ns=#shown;local lastClose
UI.close=function(_,w) lastClose=w end
button('1  Wanted: ____ today')()
local dlg=dialogs[#dialogs]
assert(dlg.title=='Q1 · up to 2 words' and dlg.input=='' and dlg.kb and #shown==ns,'gap opens keyboard dialog, no redraw yet')
local function dbtn(l) for _,r in ipairs(dlg.buttons) do for _,b in ipairs(r) do if b.text==l then return b.callback end end end end
dlg.typed='  cub reporter ';dbtn('Cancel')();assert(ls:answer(1)==nil and lastClose==dlg and #shown==ns,'Cancel saves nothing')
dbtn('Save')();assert(ls:answer(1)=='cub reporter' and #shown==ns+1 and has('cub reporter'),'Save stores, closes dialog, redraws')
ls:setAnswer(2,'x');P.show(lo)
button('2  x')();assert(dialogs[#dialogs].title=='Q2 · up to 1 word' and dialogs[#dialogs].input=='x','singular title, current answer prefilled')
shown[#shown]:closeDialog();assert(lastClose==dialogs[#dialogs],'closeDialog closes the open gap dialog')
-- 10 s tick: in place, never closes or reopens the panel
ls:setMode('practice');P.show(lo)
local w=shown[#shown];local tick=sched[#sched]
assert(tick[1]==10,'tick every 10 s')
pos,left=200,1710;ns=#shown;local nsched,ncl=#sched,0
UI.close=function() ncl=ncl+1 end
tick[2]()
assert(#shown==ns and ncl==0 and shown[#shown]==w,'tick must not redraw the panel')
assert(has('03:20 / 05:40') and has('28:30') and not has('28:40'),'row and timer updated in place')
assert(dirty[#dirty][1]==w and dirty[#dirty][2]=='ui' and dirty[#dirty][3].h<800,'dirty region is the audio row, not the screen')
assert(#sched==nsched+1 and sched[#sched][1]==10,'tick reschedules')
w:onCloseWidget();assert(unsched[#unsched]==sched[#sched][2] or unsched[#unsched]==tick[2],'closing unschedules the tick')
-- results
UI.close=function(_,x,m) closedW=x;closedMode=m end
button('Finish')();boxes[#boxes].ok_callback()
assert(fh,'Finish calls on_finish')
assert(has('Band ≈') and count('▶ Hear it')==2 and count('Transcript')==3 and not button('Show in passage'),'listening results buttons')
local hb=walk(shown[#shown],function(t) return t.text=='▶ Hear it' and t.callback end);hb.callback();assert(heard==lt.byNumber[1] and closedW~=shown[#shown],'Hear it plays, panel stays')
local tb=walk(shown[#shown],function(t) return t.text=='Transcript' and t.callback end);tb.callback();assert(evidence==lt.byNumber[1] and closedMode=='full')
button('Try again')();assert(retried,'Try again calls on_retry')
print('PASS: ielts panel, selection, multi cap, blanks, passage switch, results')
