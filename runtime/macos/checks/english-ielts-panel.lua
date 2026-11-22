package.path=assert(arg[1])..'/?.lua;'..package.path
local J=require('json')
local I=require('english_ielts')
local f=assert(io.open(arg[1]..'/../../../../ielts-sample.json'));local raw=f:read('*a');f:close()
local shown={}
local modes={}
local UI={show=function(_,w,mode) shown[#shown+1]=w;modes[#modes+1]=mode end,close=function() end}
local Widget={}
function Widget:new(t) return t or {} end
local Scroll={}
function Scroll:new(t) t=t or {};t.off={x=0,y=0};function t:getScrolledOffset() return self.off end;function t:setScrolledOffset(o) self.off=o end;return t end
local lastScroll
package.preload['ui/uimanager']=function() return UI end
package.preload['device']=function() return {screen={getWidth=function() return 600 end,getHeight=function() return 800 end,scaleBySize=function(_,s) return s end}} end
for _,n in ipairs({'container/inputcontainer','container/framecontainer','button','horizontalgroup','verticalgroup','verticalspan','textboxwidget','textwidget','buttontable'}) do
  package.preload['ui/widget/'..n]=function() return Widget end
end
package.preload['ui/font']=function() return {getFace=function() return {} end} end
package.preload['ffi/blitbuffer']=function() return {COLOR_WHITE=255} end
package.preload['ui/geometry']=function() return Widget end
package.preload['ui/widget/container/scrollablecontainer']=function() return Scroll end
local boxes={}
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
local closedW;UI.close=function(_,w) closedW=w end
local before=shown[#shown];before._scroll.off={x=0,y=40}
button('6  ____')() ;assert(picked==6 and pickedOff.y==40 and closedW==before,'gap tap closes panel, passes scroll')
button('← Passage')();assert(done)
session:setAnswer(5,'ember');session:setAnswer(6,'three big words');P.show(opts)
assert(has('ember') and has('three big words !'))
-- two-passage fixture shows the switch
local g={version=1,minutes=20,passages={{n=1,from=1,to=1},{n=2,from=2,to=2}},groups={{from=1,to=1,title='G1',instructions='i'},{from=2,to=2,title='G2',instructions='i'}},
  questions={{n=1,type='choice',options={'A','B'},answer='A',text='one'},{n=2,type='choice',options={'C','D'},answer='C',text='two'}}}
local t2=assert(I.parse(J.encode(g)));local s2=S.new(t2,store())
P.show({test=t2,session=s2,passage=1,on_pick=function()end,on_evidence=function()end,on_passage=function()end})
assert(walk(shown[#shown],function(t) return t.text=='Passage 1' and t.preselect end) and button('Passage 2') and has('G1') and not has('G2'))
button('Passage 2')();assert(has('G2') and not has('G1'))
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
print('PASS: ielts panel, selection, multi cap, blanks, passage switch, results')
