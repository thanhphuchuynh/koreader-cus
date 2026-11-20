package.path=assert(arg[1])..'/?.lua;'..package.path
local J=require('json')
local I=require('english_ielts')
local f=assert(io.open(arg[1]..'/../../../../ielts-sample.json'));local raw=f:read('*a');f:close()
local shown={}
local UI={show=function(_,w) shown[#shown+1]=w end,close=function() end}
local Widget={}
function Widget:new(t) return t or {} end
package.preload['ui/uimanager']=function() return UI end
package.preload['device']=function() return {screen={getWidth=function() return 600 end,getHeight=function() return 800 end,scaleBySize=function(_,s) return s end}} end
for _,n in ipairs({'container/inputcontainer','container/framecontainer','container/scrollablecontainer','verticalgroup','verticalspan','textboxwidget','buttontable'}) do
  package.preload['ui/widget/'..n]=function() return Widget end
end
package.preload['ui/font']=function() return {getFace=function() return {} end} end
package.preload['ffi/blitbuffer']=function() return {COLOR_WHITE=255} end
package.preload['ui/geometry']=function() return Widget end
local P=require('english_ielts_panel')
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
local d=J.decode(raw);for _,p in ipairs(d.passages) do p.paragraphs=nil end
local test=assert(I.parse(J.encode(d)))
local session=S.new(test,store());session:setMode('practice')
local picked,evidence,done
local opts={test=test,session=session,passage=1,now=function() return 0 end,
  on_pick=function(n) picked=n end,on_evidence=function(q) evidence=q end,on_passage=function() done=true end}
P.show(opts)
local dots=walk(shown[#shown],function(t) return type(t.text)=='string' and t.text:find('□',1,true) end)
local _,a=dots.text:gsub('■','');local _,b=dots.text:gsub('□','');local count=a+b;assert(count==test.total,'dots='..count)
assert(not button('Passage 1') and not has('[ Passage'),'single passage: no switch')
assert(button('TRUE') and not has('[ TRUE ]'))
button('TRUE')()
assert(session:answer(1)=='TRUE' and has('[ TRUE ]'),'selected must show')
button('B')();button('A')();button('C')()
assert(#session:answer(3)==2 and session:answer(3)[1]=='B','multi capped at picks')
button('[ B ]')();assert(#session:answer(3)==1)
button('6  ____')() ;assert(picked==6)
button('← Passage')();assert(done)
session:setAnswer(5,'ember');session:setAnswer(6,'three big words');P.show(opts)
assert(has('ember') and has('three big words !'))
-- two-passage fixture shows the switch
local g={version=1,minutes=20,passages={{n=1,from=1,to=1},{n=2,from=2,to=2}},groups={{from=1,to=1,title='G1',instructions='i'},{from=2,to=2,title='G2',instructions='i'}},
  questions={{n=1,type='choice',options={'A','B'},answer='A',text='one'},{n=2,type='choice',options={'C','D'},answer='C',text='two'}}}
local t2=assert(I.parse(J.encode(g)));local s2=S.new(t2,store())
P.show({test=t2,session=s2,passage=1,on_pick=function()end,on_evidence=function()end,on_passage=function()end})
assert(button('[ Passage 1 ]') and button('Passage 2') and has('G1') and not has('G2'))
button('Passage 2')();assert(has('G2') and not has('G1'))
-- results
P.show(opts);session:setAnswer(1,'TRUE');button('Finish')()
assert(has('/6') and has('Band ≈') and has('Time used 00:00') and has('✓ 1. TRUE'))
button('Show in passage')();assert(evidence==test.byNumber[1])
button('Try again')();assert(session:answered()==0 and button('Finish'))
button('Finish')();button('Done')();assert(done)
print('PASS: ielts panel, selection, multi cap, blanks, passage switch, results')
