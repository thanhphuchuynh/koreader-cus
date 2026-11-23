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
package.preload['ui/widget/infomessage']=function() return {new=function(_,t) t.kind='info';return t end} end
local M=require('english_tests_module')
assert(M.id=='leaf_tests' and M.name=='Leaf · Tests' and M.enabled_key=='leaf_tests_enabled' and M.default_on==false and M.getMenuItems()==nil)
M.actions.open('x');M.actions.review('x');M.actions.retry('x') -- defaults are no-ops
local function qs(n) local q={} for i=1,n do q[i]={n=i,type='gap',words=1,answer='a'..i} end return q end
local function book(title,min,total,np) local p={} for i=1,np do p[i]={n=i,from=1,to=total} end
  return J.encode{version=1,title=title,minutes=min,passages=p,questions=qs(total)} end
local files={['/home/IELTS/a.epub']=book('Alpha',20,6,1),['/home/IELTS/b.epub']=book('Beta',60,13,1),['/home/IELTS/c.epub']=book('Gamma',20,13,1)}
local recs,mt={},{}
local function toeic(title,part,n) local q={} for i=1,n do q[i]={n=i,type='choice',options={'A','B','C','D'},answer='A'} end
  return J.encode{version=1,exam='toeic',part=part,skill=part<=4 and 'listening' or nil,title=title,
    audio=part<=4 and {file='a.pcm',rate=16000,seconds=60} or nil,questions=q} end
local byDir={['/home/IELTS']={'/home/IELTS/a.epub','/home/IELTS/b.epub','/home/IELTS/c.epub'}};local dirs={}
M.io={list=function(d) dirs[#dirs+1]=d;return byDir[d] or {} end,stat=function(p) return {size=#files[p],mtime=1} end,readJson=function(p) return files[p] end,
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
local function btn(l) local b=walk(widget,function(t) return t.text==l and t.callback end);assert(b,'no button '..l);return b.callback end
local I=require('english_ielts');local bd=I.band(13,13)
widget=M.build(560,{})
assert(dirs[1]=='/home/IELTS' and dirs[3]=='/home/IELTS/Reading' and dirs[#dirs]=='/home/TOEIC/Part 7' and #dirs==11,'scans IELTS and TOEIC folders')
for _,s in ipairs{'TESTS','CONTINUE','FOLDERS','3','1','tests','finished','last band','Alpha','In progress · 3/6 answered · 12:40 left','Continue',
  'IELTS Listening  ·  0 tests · 0 done  ›','IELTS Reading  ·  3 tests · 1 done · band '..bd..'  ›','TOEIC  ·  0 sets · 0 done  ›'} do assert(has(s),'missing '..s) end
assert(walk(widget,function(t) return t.text and t.text:find('^TOEIC') and t.width==560 and t.height>=44 and t.align=='left' end),'folder row: full width, tall, left')
local opened,rev,ret
M.actions={open=function(p) opened=p end,review=function(p) rev=p end,retry=function(p) ret=p end}
btn('Continue')();assert(opened=='/home/IELTS/a.epub')
-- IELTS Reading folder: every reading test with its status
btn('IELTS Reading  ·  3 tests · 1 done · band '..bd..'  ›')()
local menu=shown[#shown];assert(menu.kind=='menu' and menu.title=='IELTS Reading' and #menu.item_table==3)
local function entry(m,title) for _,e in ipairs(m.item_table) do if e.text==title then return e end end error('no entry '..title) end
assert(entry(menu,'Gamma').mandatory=='Not started' and entry(menu,'Alpha').mandatory=='3/6 · 12:40 left' and entry(menu,'Beta').mandatory:find('^13/13 · Band ≈ '))
assert(menu.item_table[1].text=='Gamma' and menu.item_table[3].text=='Beta','new, then in progress, then done')
local function act(m,title,label,also) entry(m,title).callback();local d=shown[#shown];assert(d.kind=='dialog' and d.title==title)
  for _,b in ipairs(d.buttons[1]) do if b.text==label then b.callback();assert(closed[d] and closed[m] and (not also or closed[also]));return d end end error('no '..label..' for '..title) end
local d=act(menu,'Beta','Retry');assert(ret=='/home/IELTS/b.epub' and d.buttons[1][1].text=='Review')
act(menu,'Beta','Review');assert(rev=='/home/IELTS/b.epub');act(menu,'Gamma','Start');assert(opened=='/home/IELTS/c.epub')
act(menu,'Alpha','Continue');assert(opened=='/home/IELTS/a.epub' and #shown[#shown].buttons[1]==1,'no Retry before finishing')
-- TOEIC: parts, then a part's sets; percent for done sets; listening part 2 goes to Part 2 wherever it sits
files['/home/TOEIC/Part 5/s1.epub']=toeic('Set 1',5,6);files['/home/TOEIC/Part 5/s2.epub']=toeic('Set 2',5,6);files['/home/TOEIC/q.epub']=toeic('Q-R 1',2,5)
byDir['/home/TOEIC/Part 5']={'/home/TOEIC/Part 5/s1.epub','/home/TOEIC/Part 5/s2.epub'};byDir['/home/TOEIC']={'/home/TOEIC/q.epub'}
recs['/home/TOEIC/Part 5/s1.epub']={mode='study',answers={'A','A','A','A','A','B'},finished=true,finished_at=5};mt['/home/TOEIC/Part 5/s1.epub']=7
widget=M.build(560,{})
local tb=walk(widget,function(t) return type(t.text)=='string' and t.text:find('^TOEIC') end);assert(tb.text=='TOEIC  ·  3 sets · 1 done · 83%  ›','toeic folder: '..tb.text)
assert(has('6') and has('2') and has(tostring(bd)),'summary: all tests, all finished, IELTS last band')
btn('TOEIC  ·  3 sets · 1 done · 83%  ›')()
local parts=shown[#shown];assert(parts.kind=='menu' and parts.title=='TOEIC' and #parts.item_table==7)
assert(parts.item_table[5].text=='Part 5 · Incomplete sentences' and parts.item_table[5].mandatory=='2 sets · 1 done · 83%')
assert(parts.item_table[2].mandatory=='1 set · 0 done' and parts.item_table[1].mandatory=='0 sets · 0 done')
parts.item_table[1].callback();assert(shown[#shown].kind=='info' and shown[#shown].text:find('documents/TOEIC/Part 1',1,true),'empty part: hint')
parts.item_table[5].callback();local sets=shown[#shown]
assert(sets.kind=='menu' and sets.title=='Part 5 · Incomplete sentences' and #sets.item_table==2)
assert(entry(sets,'Set 1').mandatory=='5/6 · 83%' and entry(sets,'Set 2').mandatory=='Not started')
act(sets,'Set 2','Start',parts);assert(opened=='/home/TOEIC/Part 5/s2.epub','opening a set closes the set list and the parts list')
-- empty
byDir={};widget=M.build(560,{})
assert(has('No tests yet — put test files in documents/IELTS or documents/TOEIC') and not has('CONTINUE') and not has('FOLDERS'))
print('PASS: tests module folders, lists, actions, TOEIC parts, empty state')
