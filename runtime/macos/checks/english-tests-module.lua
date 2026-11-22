package.path=assert(arg[1])..'/?.lua;'..package.path
local J=require('json')
-- Stub widgets: groups sum child heights, text is 20 px, buttons 50 px.
local function W(h) local c={};function c:new(t) t=t or {};setmetatable(t,{__index=c});return t end
  function c:getSize() local s=0;for _,x in ipairs(self) do s=s+(type(x)=='table' and x.getSize and x:getSize().h or 0) end;return {w=0,h=h or s} end
  return c end
local VG=W();local HG=W();function HG:getSize() local m=0;for _,x in ipairs(self) do m=math.max(m,x:getSize().h) end;return {w=0,h=m} end
local stub={['verticalgroup']=VG,['horizontalgroup']=HG,['verticalspan']=(function() local c=W();function c:getSize() return {w=0,h=self.width} end;return c end)(),
  ['textboxwidget']=W(20),['button']=(function() local c=W();function c:getSize() return {w=0,h=self.height or 30} end;return c end)(),
  ['container/framecontainer']=W(),['widget']=W()}
for k,v in pairs(stub) do package.preload['ui/widget/'..k]=function() return v end end
package.preload['device']=function() return {screen={getWidth=function() return 600 end,scaleBySize=function(_,s) return s end}} end
package.preload['ui/font']=function() return {getFace=function() return {} end} end
package.preload['ffi/blitbuffer']=function() return {COLOR_BLACK=0,COLOR_WHITE=255,COLOR_DARK_GRAY=64} end
package.preload['ui/geometry']=function() return W() end
_G.G_reader_settings={readSetting=function() return '/home' end}
local M=require('english_tests_module')
assert(M.id=='leaf_tests' and M.name=='Leaf · Tests' and M.enabled_key=='leaf_tests_enabled' and M.default_on==false and M.getMenuItems()==nil)
M.actions.open('x');M.actions.review('x');M.actions.retry('x') -- defaults are no-ops
local function qs(n) local q={} for i=1,n do q[i]={n=i,type='gap',words=1,answer='a'..i} end return q end
local function book(title,min,total,np) local p={} for i=1,np do p[i]={n=i,from=1,to=total} end
  return J.encode{version=1,title=title,minutes=min,passages=p,questions=qs(total)} end
local files={['/home/IELTS/a.epub']=book('Alpha',20,6,1),['/home/IELTS/b.epub']=book('Beta',60,13,1),['/home/IELTS/c.epub']=book('Gamma',20,13,1)}
local recs,mt={},{}
local listed={'/home/IELTS/a.epub','/home/IELTS/b.epub','/home/IELTS/c.epub'};local dirSeen
M.io={list=function(d) dirSeen=d;return listed end,stat=function(p) return {size=#files[p],mtime=1} end,readJson=function(p) return files[p] end,
  record=function(p) return recs[p] end,recordMtime=function(p) return mt[p] or 0 end}
M.now=function() return 0 end
local ans={};for i=1,13 do ans[i]='a'..i end
local three={};for i=1,3 do three[i]='a'..i end
recs['/home/IELTS/a.epub']={mode='practice',answers=three,elapsed=440};mt['/home/IELTS/a.epub']=100
recs['/home/IELTS/b.epub']={mode='practice',answers=ans,elapsed=1,finished=true};mt['/home/IELTS/b.epub']=50
local function walk(x,fn,seen) seen=seen or {}
  if type(x)~='table' or seen[x] then return end seen[x]=true
  if fn(x) then return x end
  for _,v in pairs(x) do local r=walk(v,fn,seen) if r then return r end end end
local widget
local function has(s) return walk(widget,function(t) return t.text==s end) end
local function hasSub(s) return walk(widget,function(t) return type(t.text)=='string' and t.text:find(s,1,true) end) end
local function btn(l) local b=walk(widget,function(t) return t.text==l and t.callback end);assert(b,'no button '..l);return b.callback end
widget=M.build(560,{pfx='x_'});assert(dirSeen=='/home/IELTS')
for _,s in ipairs{'TESTS','CONTINUE','ALL TESTS','3','1','tests','finished','last band','Alpha','Beta','Gamma','Not started','In progress · 3/6 answered · 12:40 left'} do assert(has(s),'missing '..s) end
assert(hasSub('13/13 · Band ≈ '),'done line')
-- band value from a 13-question test, rough
local I=require('english_ielts');local bd,rough=I.band(13,13)
assert(hasSub('Band ≈ '))
local opened,rev,ret
M.actions={open=function(p) opened=p end,review=function(p) rev=p end,retry=function(p) ret=p end}
btn('Continue')();assert(opened=='/home/IELTS/a.epub')
btn('Review')();assert(rev=='/home/IELTS/b.epub');btn('Retry')();assert(ret=='/home/IELTS/b.epub');btn('Start')()
assert(opened=='/home/IELTS/c.epub')
for _,b in ipairs{'Continue','Review','Retry','Start'} do assert(walk(widget,function(t) return t.text==b and t.height>=44 end),b..' height') end
local n=0;walk(widget,function(t) if t.text=='Alpha' then n=n+1 end end);assert(n==1,'continue item not repeated')
-- dots: 3 of 6 answered
assert(walk(widget,function(t) return t.text=='■ ■ ■ □ □ □' end),'dots')
-- long test: 13 dots then …total
files['/home/IELTS/d.epub']=book('Delta',20,40,1);recs['/home/IELTS/d.epub']={mode='study',answers={[1]='a1'},elapsed=0};listed[4]='/home/IELTS/d.epub'
widget=M.build(560,{});assert(walk(widget,function(t) return type(t.text)=='string' and t.text:find('…40',1,true) and select(2,t.text:gsub('■',''))+select(2,t.text:gsub('□',''))==13 end),'long dots')
assert(M.getHeight({col_w=560})==widget:getSize().h,'getHeight matches build')
-- empty
listed={};widget=M.build(560,{})
assert(has('No tests yet — put test files in documents/IELTS') and not has('CONTINUE') and not has('ALL TESTS'))
assert(M.getHeight({col_w=560})==widget:getSize().h)
print('PASS: tests module layout, actions, empty state')
