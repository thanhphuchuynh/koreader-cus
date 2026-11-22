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
local sum=0
for _,x in ipairs(B.top(600,{tab='passage',timer='12:34'})[1]) do sum=sum+(x.width or x.max_width or 0) end
assert(sum<=600,'top row wider than screen: '..sum)
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
ov:handleEvent({handler='onKeyPress',args={{}}});assert(#fwd==2,'keys forwarded')
ov:handleEvent({handler='onPageUpdate',args={}});assert(#fwd==2,'broadcasts are not forwarded')
assert(has(ov,'01:00'));local nd=#dirty
o.timer='02:00';h:update(o)
assert(has(ov,'02:00') and not has(ov,'01:00') and #dirty>nd and dirty[#dirty][2]=='ui','update rebuilds in place')
h:close();h:close();assert(#closed==1 and closed[1]==ov,'close once')
print('PASS')
