package.path=assert(arg[1])..'/?.lua;'..package.path
local shown,closed,dirty,boxes={},{},{},{}
local UI={show=function(_,w) shown[#shown+1]=w end,close=function(_,w) closed[#closed+1]=w end,
  setDirty=function(_,w,mode,r) dirty[#dirty+1]={w,mode,r} end,
  scheduleIn=function() end}
local Widget={}
local made={}
function Widget:new(t) t=t or {};made[#made+1]=t;return t end
local Input={}
function Input:new(t) t=t or {};t.handleEvent=function() return nil end;return t end
package.preload['ui/uimanager']=function() return UI end
package.preload['device']=function() return {screen={getWidth=function() return 600 end,getHeight=function() return 800 end,scaleBySize=function(_,s) return s end}} end
for _,n in ipairs({'framecontainer','button','horizontalgroup','verticalgroup','verticalspan','textwidget','overlapgroup','horizontalspan'}) do
  package.preload['ui/widget/'..n]=function() return Widget end
end
package.preload['ui/widget/container/inputcontainer']=function() return Input end
package.preload['ui/widget/container/framecontainer']=function() return Widget end
package.preload['ui/widget/container/centercontainer']=function() return Widget end
package.preload['ui/widget/confirmbox']=function() return {new=function(_,t) boxes[#boxes+1]=t;return t end} end
package.preload['ui/font']=function() return {getFace=function() return {} end} end
package.preload['ffi/blitbuffer']=function() return {COLOR_WHITE=255,COLOR_BLACK=0} end
package.preload['ui/geometry']=function() return {new=function(_,t) return t end} end
local B=require('english_ielts_bars')
local function walk(x,fn,seen) seen=seen or {}
  if type(x)~='table' or seen[x] then return end seen[x]=true
  if fn(x) then return x end
  for _,v in pairs(x) do local r=walk(v,fn,seen) if r then return r end end
end
local function btn(w,l) return walk(w,function(t) return t.text==l and t.callback end) end
local function has(w,s) return walk(w,function(t) return type(t.text)=='string' and t.text:find(s,1,true) end) end
local function call(w,l) local b=btn(w,l);assert(b,'no button '..l);b.callback() end
-- top: tabs
local hit={}
local t=B.top(600,{tab='questions',timer='12:34',on_passage=function() hit.p=true end,on_questions=function() hit.q=true end})
assert(btn(t,'Passage') and btn(t,'Questions') and has(t,'12:34'))
assert(walk(t,function(x) return x.text=='Questions' and x.preselect end) and not walk(t,function(x) return x.text=='Passage' and x.preselect end))
call(t,'Passage');call(t,'Questions');assert(hit.p and hit.q)
t=B.top(600,{tab='passage'});assert(walk(t,function(x) return x.text=='Passage' and x.preselect end) and not walk(t,function(x) return type(x.text)=='string' and x.text:find(':',1,true) end),'no timer when nil')
-- top: pick
local done,cancel
t=B.top(600,{pick=7,on_done=function() done=true end,on_cancel=function() cancel=true end})
assert(has(t,'Tap the word for Q7') and not btn(t,'Passage'));call(t,'Done');call(t,'Cancel');assert(done and cancel)
-- bottom
local f,q,p=0
local b=B.bottom(600,{view='passage',on_questions=function() q=true end,on_finish=function() f=f+1 end,on_passage=function() p=true end})
assert(btn(b,'Questions →') and btn(b,'Finish') and not btn(b,'← Passage'));call(b,'Questions →');call(b,'Finish');assert(q and f==1)
b=B.bottom(600,{view='questions',on_passage=function() p=true end,on_finish=function() f=f+1 end})
assert(btn(b,'← Passage') and btn(b,'Finish') and not btn(b,'Questions →'));call(b,'← Passage');assert(p)
-- geometry: real Button is height+2*padding_v+2*bordersize tall (button.lua); must fit the bar; widths fit the screen; show_parent is the overlay
local function fits(w)
  walk(w,function(x)
    if x.callback and x.height then assert(x.height+2*(x.padding_v or 0)+2*(x.bordersize or 0)<=48,'button taller than bar') end
    return false end)
end
fits(B.top(600,{tab='passage',timer='12:34'}));fits(B.bottom(600,{view='passage'}))
-- rows fill exactly the width (label/timer in fixed-width cells), frame has no border so the bar is exactly Bars.height
for _,r in ipairs({B.top(600,{tab='passage',timer='12:34'}),B.top(600,{tab='passage'}),B.top(600,{pick=3}),B.bottom(600,{view='passage'})}) do
  assert(r.bordersize==0 and r.height==B.height(),'bar frame: no border, exact height')
  local sum=0
  for _,x in ipairs(r[1]) do local cw=x.width or (x.dimen and x.dimen.w);assert(cw,'cell without fixed width');sum=sum+cw end
  assert(sum==600,'row must fill the width: '..sum)
end
assert(#B.top(600,{pick=3})[1]==3,'pick form: label + Done + Cancel, no timer cell')
-- listening forms
t=B.top(600,{title='Section 1',timer='28:40'})
assert(has(t,'Section 1') and has(t,'28:40') and not btn(t,'Passage') and not btn(t,'Questions') and #t[1]==2,'title form: title + timer, no tabs')
assert(t.timer_text and t.timer_text.text=='28:40','timer widget kept for in-place updates')
local sum=0;for _,x in ipairs(t[1]) do sum=sum+(x.width or x.dimen.w) end;assert(sum==600,'title row fills width: '..sum)
t=B.top(600,{title='Section 1'});assert(#t[1]==1 and t[1][1].dimen.w==600 and not t.timer_text,'title only')
b=B.bottom(600,{view='listening',on_finish=function() f=f+1 end})
assert(btn(b,'Finish') and not btn(b,'← Passage') and not btn(b,'Questions →') and #b[1]==1);call(b,'Finish')
t=B.top(600,{tab='passage',passage_label='Transcript'});assert(btn(t,'Transcript') and not btn(t,'Passage'),'passage_label')
-- confirmFinish
local yes=false
B.confirmFinish(function() yes=true end)
local box=boxes[#boxes];assert(box.text=='Finish and see your score?' and box.ok_text=='Finish' and box.cancel_text=='Cancel')
box.ok_callback();assert(yes)
-- overlay
local fwd={}
local o={tab='passage',view='passage',timer='01:00',forward=function(e) fwd[#fwd+1]=e;return true end,
  on_passage=function() end,on_questions=function() end,on_finish=function() end}
local h=B.overlay(o)
local ov=shown[#shown];assert(ov)
assert(walk(ov,function(x) return x.text=='Finish' and x.show_parent==ov end),'show_parent must be the overlay')
local th,bh=h:heights();assert(th>=44 and bh>=44)
local function tap(y) return {handler='onGesture',args={{ges='tap',pos={x=100,y=y}}}} end
assert(ov:handleEvent(tap(400)) and #fwd==1,'tap outside forwarded')
assert(ov:handleEvent(tap(th-1)) and ov:handleEvent(tap(800-bh+1)) and #fwd==1,'tap in a bar stays')
local function g(kind,y) return {handler='onGesture',args={{ges=kind,pos={x=100,y=y}}}} end
assert(ov:handleEvent(g('hold',5)) and ov:handleEvent(g('swipe',795)) and #fwd==1,'hold/swipe starting in a bar stay')
for _,k in ipairs({'hold_pan','hold_release','pan_release'}) do
  local n=#fwd;ov:handleEvent(g(k,5));ov:handleEvent(g(k,795));assert(#fwd==n+2,k..' over a bar must reach the reader')
end
local nf=#fwd;ov:handleEvent({handler='onKeyPress',args={{}}});assert(#fwd==nf+1,'keys forwarded')
ov:handleEvent({handler='onPageUpdate',args={}});assert(#fwd==nf+1,'broadcasts are not forwarded')
assert(has(ov,'01:00'));local nd=#dirty
o.timer='02:00';h:update(o)
assert(has(ov,'02:00') and not has(ov,'01:00') and #dirty==nd+1 and dirty[#dirty][2]=='ui' and dirty[#dirty][3].y==0,'timer-only update refreshes the top bar only')
nd=#dirty;h:update({pick=4,forward=o.forward});assert(#dirty==nd+2,'form change refreshes both bars')
h:close();h:close();assert(#closed==1 and closed[1]==ov,'close once')
print('PASS')
