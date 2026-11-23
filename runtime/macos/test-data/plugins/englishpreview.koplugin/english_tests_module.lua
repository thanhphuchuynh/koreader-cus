-- SimpleUI module "Leaf · Tests": summary, the test to continue, then folders (IELTS Listening, IELTS Reading, TOEIC by part).
local Tests=require('english_tests')
local M={id='leaf_tests',name='Leaf · Tests',enabled_key='leaf_tests_enabled',default_on=false}
local function noop() end
M.actions={open=noop,review=noop,retry=noop} -- wired by Leaf at startup
M.io=nil -- checks inject a fake; default is built on first use (docsettings is not loadable at require time)
function M.getMenuItems() return nil end

local dio
local function defaultIO() dio=dio or Tests.defaultIO() return dio end
local I=require('english_ielts')
local DIRS={'/IELTS','/IELTS/Listening','/IELTS/Reading','/TOEIC'}
for p=1,7 do DIRS[#DIRS+1]='/TOEIC/Part '..p end
local function clock(sec) return ('%02d:%02d'):format(math.floor(sec/60),sec%60) end
local function status(it)
  if it.state=='new' then return 'Not started' end
  if it.state=='progress' then return ('%d/%d'):format(it.answered,it.total)..(it.remaining and ' · '..clock(it.remaining)..' left' or '') end
  if it.percent then return ('%d/%d · %d%%'):format(it.right,it.total,it.percent) end
  return ('%d/%d · Band ≈ %s'):format(it.right,it.total,it.band)..(it.rough and ' (rough)' or '')
end
-- "3 tests · 1 done · band 6.5" / "2 sets · 1 done · 83%"
local function counts(items,unit)
  local s=Tests.summary(items)
  local t=('%d %s%s · %d done'):format(s.count,unit,s.count==1 and '' or 's',s.finished)
  if s.lastBand then t=t..' · band '..s.lastBand end
  if s.best then t=t..(' · %d%%'):format(s.best) end
  return t
end
local function closeAll(menus) local UIManager=require('ui/uimanager');for _,m in ipairs(menus or {}) do UIManager:close(m) end end
-- Dialog with the actions a test's state allows; closes itself and the open lists before acting.
local function actions(it,menus)
  local UIManager=require('ui/uimanager')
  local dialog
  local function b(t,act) return {text=t,callback=function() UIManager:close(dialog);closeAll(menus);M.actions[act](it.path) end} end
  local row
  if it.state=='done' then row={b('Review','review'),b('Retry','retry')}
  else row={b(it.state=='new' and 'Start' or 'Continue','open')} end
  dialog=require('ui/widget/buttondialog'):new{title=it.title,buttons={row}}
  UIManager:show(dialog)
end
local function menu(title,list)
  local m=require('ui/widget/menu'):new{title=title,item_table=list,covers_fullscreen=true,is_borderless=true,is_popout=false}
  require('ui/uimanager'):show(m)
  return m
end
-- One folder's tests, full screen; `under` = lists already open (closed too when a test opens).
local function showList(title,items,under)
  local menus={unpack(under or {})}
  local list={}
  for _,it in ipairs(Tests.ordered(items)) do
    list[#list+1]={text=it.title,mandatory=status(it),callback=function() actions(it,menus) end}
  end
  menus[#menus+1]=menu(title,list)
end
local function showToeic(items)
  local menus={}
  local list={}
  for p=1,7 do
    local name=('Part %d · %s'):format(p,I.PARTS[p])
    local sets=Tests.inFolder(items,'TOEIC Part '..p)
    list[#list+1]={text=name,mandatory=counts(sets,'set'),callback=function()
      if #sets==0 then
        require('ui/uimanager'):show(require('ui/widget/infomessage'):new{text=('No sets yet — put Part %d files in documents/TOEIC/Part %d'):format(p,p)})
      else showList(name,sets,menus) end
    end}
  end
  menus[1]=menu('TOEIC',list)
end

local function homeDir()
  local ok,h=pcall(function() return require('apps/filemanager/filemanagerutil').getHomeFolder() end)
  return ok and h or '/mnt/us/documents'
end

local function build(w)
  local Screen=require('device').screen
  local VG=require('ui/widget/verticalgroup')
  local HG=require('ui/widget/horizontalgroup')
  local VS=require('ui/widget/verticalspan')
  local TB=require('ui/widget/textboxwidget')
  local Button=require('ui/widget/button')
  local Font=require('ui/font')
  local Blitbuffer=require('ffi/blitbuffer')
  local pad=Screen:scaleBySize(12)
  local btnH=math.max(44,Screen:scaleBySize(44))
  local col=VG:new{align='left'}
  local function text(s,size,face,width,color)
    col[#col+1]=TB:new{text=s,face=Font:getFace(face or 'cfont',size or 18),width=width or w,fgcolor=color}
  end
  local function gap(n) col[#col+1]=VS:new{width=n or pad} end
  local function label(s) gap();text(s,14,'cfont',nil,Blitbuffer.COLOR_DARK_GRAY) end
  local items={}
  for _,sub in ipairs(DIRS) do
    for _,it in ipairs(Tests.scan(homeDir()..sub,M.io or defaultIO())) do items[#items+1]=it end
  end
  if #items==0 then
    text('No tests yet — put test files in documents/IELTS or documents/TOEIC')
    return col
  end
  local function card(it) -- the in-progress test to continue
    gap();text(it.title,20,'tfont');text(it.meta,15)
    local d={};for i=1,math.min(it.total,13) do d[i]=i<=it.answered and '■' or '□' end
    text(table.concat(d,' ')..(it.total>13 and ' …'..it.total or ''),15)
    text(('In progress · %d/%d answered'):format(it.answered,it.total)..(it.remaining and ' · '..clock(it.remaining)..' left' or ''),15)
    gap(math.floor(pad/2))
    col[#col+1]=Button:new{text='Continue',height=btnH,width=math.floor((w-pad)/2),callback=function() M.actions.open(it.path) end}
  end
  local function folder(name,detail,fn) -- full-width row: `name · detail  ›`
    gap(math.floor(pad/2))
    col[#col+1]=Button:new{text=name..'  ·  '..detail..'  ›',align='left',padding_h=pad,height=btnH,width=w,callback=fn}
  end
  local s=Tests.summary(items)
  label('TESTS')
  local cw=math.floor(w/3);local srow=HG:new{}
  for _,c in ipairs{{s.count,'tests'},{s.finished,'finished'},{s.lastBand or '—','last band'}} do
    local cell=VG:new{align='left'}
    cell[1]=TB:new{text=tostring(c[1]),face=Font:getFace('tfont',24),width=cw}
    cell[2]=TB:new{text=c[2],face=Font:getFace('cfont',14),width=cw}
    srow[#srow+1]=cell
  end
  col[#col+1]=srow
  local cont=Tests.continueItem(items)
  if cont then label('CONTINUE');card(cont) end
  label('FOLDERS')
  for _,name in ipairs{'IELTS Listening','IELTS Reading'} do
    local f=Tests.inFolder(items,name)
    folder(name,counts(f,'test'),function() showList(name,f) end)
  end
  local toeic={};for _,it in ipairs(items) do if it.toeic then toeic[#toeic+1]=it end end
  folder('TOEIC',counts(toeic,'set'),function() showToeic(items) end)
  return col
end

function M.build(w) return build(w) end

return M
