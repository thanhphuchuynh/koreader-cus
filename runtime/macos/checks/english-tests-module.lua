package.path=assert(arg[1])..'/?.lua;'..package.path
local J=require('json')
-- Stub widgets: groups sum child heights, text is 20 px, buttons 50 px.
local function W(h) local c={};function c:new(t) t=t or {};setmetatable(t,{__index=c});return t end
  function c:getSize() local s=0;for _,x in ipairs(self) do s=s+(type(x)=='table' and x.getSize and x:getSize().h or 0) end;return {w=0,h=h or s} end
  return c end
local VG=W();local HG=W();function HG:getSize() local m=0;for _,x in ipairs(self) do m=math.max(m,x:getSize().h) end;return {w=0,h=m} end
local stub={['verticalgroup']=VG,['horizontalgroup']=HG,['verticalspan']=(function() local c=W();function c:getSize() return {w=0,h=self.width} end;return c end)(),
  ['textboxwidget']=W(20),['button']=(function() local c=W();function c:getSize() return {w=0,h=self.height or 30} end;return c end)(),
  ['container/framecontainer']=W(),['widget']=W(),['textwidget']=W(20),['horizontalspan']=W(0)}
for k,v in pairs(stub) do package.preload['ui/widget/'..k]=function() return v end end
package.preload['device']=function() return {screen={getWidth=function() return 600 end,scaleBySize=function(_,s) return s end}} end
package.preload['ui/font']=function() return {getFace=function() return {} end} end
package.preload['ffi/blitbuffer']=function() return {COLOR_BLACK=0,COLOR_WHITE=255,COLOR_DARK_GRAY=64} end
package.preload['ui/geometry']=function() return W() end
package.preload['apps/filemanager/filemanagerutil']=function() return {getHomeFolder=function() return '/home' end} end
local shown,closed={},{}
package.preload['ui/uimanager']=function() return {show=function(_,x) shown[#shown+1]=x end,close=function(_,x) closed[x]=true end} end
package.preload['ui/widget/menu']=function() return {new=function(_,t) t.kind='menu';return t end} end
package.preload['ui/widget/buttondialog']=function() return {new=function(_,t) t.kind='dialog';return t end} end
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
for _,s in ipairs{'TESTS','CONTINUE','ALL TESTS','3','1','tests','finished','last band','Alpha','Beta','Gamma','Not started','In progress · 3/6 answered · 12:40 left','Continue','Review','Start'} do assert(has(s),'missing '..s) end
assert(hasSub('13/13 · Band ≈ '),'done line')
-- band value from a 13-question test, rough
local I=require('english_ielts');local bd,rough=I.band(13,13)
assert(hasSub('Band ≈ '))
local opened,rev,ret
M.actions={open=function(p) opened=p end,review=function(p) rev=p end,retry=function(p) ret=p end}
btn('Continue')();assert(opened=='/home/IELTS/a.epub')
btn('Review')();assert(rev=='/home/IELTS/b.epub');assert(not has('Retry'),'Retry only in the list');btn('Start')()
assert(opened=='/home/IELTS/c.epub')
for _,b in ipairs{'Continue','Review','Start'} do assert(walk(widget,function(t) return t.text==b and t.height>=44 end),b..' height') end
local n=0;walk(widget,function(t) if t.text=='Alpha' then n=n+1 end end);assert(n==1,'continue item not repeated')
-- dots: 3 of 6 answered
assert(walk(widget,function(t) return t.text=='■ ■ ■ □ □ □' end),'dots')
-- long test: 13 dots then …total
files['/home/IELTS/d.epub']=book('Delta',20,40,1);recs['/home/IELTS/d.epub']={mode='study',answers={[1]='a1'},elapsed=0};listed[4]='/home/IELTS/d.epub';mt['/home/IELTS/d.epub']=200
widget=M.build(560,{});assert(walk(widget,function(t) return type(t.text)=='string' and t.text:find('…40',1,true) and select(2,t.text:gsub('■',''))+select(2,t.text:gsub('□',''))==13 end),'long dots')
assert(has('3/6 · 12:40 left'),'practice row status')
mt['/home/IELTS/d.epub']=0;widget=M.build(560,{});assert(has('1/40'),'study row status')
assert(M.getHeight({col_w=560})==widget:getSize().h,'getHeight matches build')
assert(not hasSub('All tests'),'no All tests button with few tests')
-- empty
M.build(560,{});listed={};widget=M.build(560,{})
assert(has('No tests yet — put test files in documents/IELTS') and not has('CONTINUE') and not has('ALL TESTS'))
assert(M.getHeight({col_w=560})==widget:getSize().h)
-- engine builds at the chrome-inset width; getHeight must measure at that width
listed={'/home/IELTS/a.epub'};local calls={}
package.preload['features/sui_module_chrome']=function() return {resolve=function(p,id) calls[#calls+1]=id return {} end,contentWidth=function(c) return c-40 end} end
assert(M.getHeight({col_w=600,pfx='x_'})==M.build(560,{}):getSize().h and calls[1]=='leaf_tests','getHeight at inset width')
-- 10 tests: at most 6 rows, then All tests (10) opening a Menu of every test
listed={};recs={};mt={}
for i=1,10 do local p=('/home/IELTS/t%02d.epub'):format(i);files[p]=book(('T%02d'):format(i),20,6,1);listed[i]=p end
recs[listed[1]]={mode='practice',answers=three,elapsed=0};mt[listed[1]]=9
recs[listed[2]]={mode='practice',answers=ans,elapsed=1,finished=true}
widget=M.build(560,{})
local rows=0;walk(widget,function(t) if t.callback and t.width==140 then rows=rows+1 end end) -- row buttons are w/4 wide
assert(rows==6,'rows '..rows)
assert(walk(widget,function(t) return t.text=='All tests (10)' and t.callback and t.height>=44 end),'All tests button')
btn('All tests (10)')();local menu=shown[#shown];assert(menu.kind=='menu' and menu.title=='Tests' and #menu.item_table==10)
local function entry(title) for _,e in ipairs(menu.item_table) do if e.text:find(title..' · ',1,true)==1 then return e end end end
assert(entry('T03').text=='T03 · Not started' and entry('T01').text=='T01 · 3/6 · 20:00 left')
local function act(title,label) entry(title).callback();local d=shown[#shown];assert(d.kind=='dialog' and d.title==title)
  for _,b in ipairs(d.buttons[1]) do if b.text==label then b.callback();assert(closed[d] and closed[menu]);return d end end error('no '..label..' for '..title) end
ret=nil;local d=act('T02','Retry');assert(ret==listed[2] and #d.buttons[1]==2 and d.buttons[1][1].text=='Review')
act('T02','Review');assert(rev==listed[2]);act('T03','Start');assert(opened==listed[3]);act('T01','Continue');assert(opened==listed[1])
assert(#shown[#shown].buttons[1]==1,'no Retry before finishing')
print('PASS: tests module layout, actions, empty state')
