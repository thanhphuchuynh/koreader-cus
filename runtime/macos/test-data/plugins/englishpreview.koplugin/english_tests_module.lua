-- SimpleUI module "Leaf · Tests": summary, the test to continue, and every test with its status.
local Tests=require('english_tests')
local M={id='leaf_tests',name='Leaf · Tests',enabled_key='leaf_tests_enabled',default_on=false}
local function noop() end
M.actions={open=noop,review=noop,retry=noop} -- wired by Leaf at startup
M.io=nil -- checks inject a fake; default is built on first use (docsettings is not loadable at require time)
function M.getMenuItems() return nil end

local dio
local function defaultIO() dio=dio or Tests.defaultIO() return dio end
-- ponytail: fixed caps sized for 600x800, use engine height if a screen ever needs more
local MAX_ROWS_WITH_CARD,MAX_ROWS=3,5
local function clock(sec) return ('%02d:%02d'):format(math.floor(sec/60),sec%60) end
local function status(it)
  if it.state=='new' then return 'Not started' end
  if it.state=='progress' then return ('%d/%d'):format(it.answered,it.total)..(it.remaining and ' · '..clock(it.remaining)..' left' or '') end
  return ('%d/%d · Band ≈ %s'):format(it.right,it.total,it.band)..(it.rough and ' (rough)' or '')
end
-- Dialog with the actions a test's state allows; closes itself (and `menu`, if given) before acting.
local function actions(it,menu)
  local UIManager=require('ui/uimanager')
  local dialog
  local function b(t,act) return {text=t,callback=function() UIManager:close(dialog);if menu then UIManager:close(menu) end;M.actions[act](it.path) end} end
  local row
  if it.state=='done' then row={b('Review','review'),b('Retry','retry')}
  else row={b(it.state=='new' and 'Start' or 'Continue','open')} end
  dialog=require('ui/widget/buttondialog'):new{title=it.title,buttons={row}}
  UIManager:show(dialog)
end

-- Every test in a KOReader Menu; an entry opens its actions dialog.
local function showAll(items)
  local UIManager=require('ui/uimanager')
  local Menu=require('ui/widget/menu')
  local menu
  local list={}
  for _,it in ipairs(Tests.ordered(items)) do
    list[#list+1]={text=it.title..' · '..status(it),callback=function() actions(it,menu) end}
  end
  menu=Menu:new{title='Tests',item_table=list,covers_fullscreen=true,is_borderless=true,is_popout=false}
  UIManager:show(menu)
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
  local HS=require('ui/widget/horizontalspan')
  local TB=require('ui/widget/textboxwidget')
  local TW=require('ui/widget/textwidget')
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
  for _,sub in ipairs{'/IELTS','/IELTS/Listening'} do
    for _,it in ipairs(Tests.scan(homeDir()..sub,M.io or defaultIO())) do items[#items+1]=it end
  end
  if #items==0 then
    text('No tests yet — put test files in documents/IELTS')
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
  local bw=math.floor(w/4)
  local function row(it) -- one line `title · status`, one button right; row height = button height
    local t,fn
    if it.state=='done' then t,fn='Review…',function() actions(it) end
    else t,fn=it.state=='new' and 'Start' or 'Continue',function() M.actions.open(it.path) end end
    gap(math.floor(pad/2))
    col[#col+1]=HG:new{align='center',
      TW:new{text=it.title..' · '..status(it),face=Font:getFace('cfont',18),max_width=w-bw-pad},
      HS:new{width=pad},
      Button:new{text=t,height=btnH,width=bw,callback=fn}}
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
  label('ALL TESTS')
  local cap=cont and MAX_ROWS_WITH_CARD or MAX_ROWS
  local shown,more=0,false
  for _,it in ipairs(Tests.ordered(items)) do
    if it~=cont then
      if shown<cap then row(it);shown=shown+1 else more=true end
    end
  end
  if more then -- right after the last row, so it stays on screen
    gap(math.floor(pad/2))
    col[#col+1]=Button:new{text=('All tests (%d)'):format(#items),height=btnH,width=w,callback=function() showAll(items) end}
  end
  return col
end

-- The engine builds at ModuleChrome.contentWidth(col_w, chrome), not at col_w.
local function width(ctx)
  local w=ctx and (ctx.col_w or ctx.inner_w) or require('device').screen:getWidth()
  if ctx and ctx.pfx and ctx.col_w then
    local ok,C=pcall(require,'features/sui_module_chrome')
    if ok and C then
      local ok2,v=pcall(function() return C.contentWidth(ctx.col_w,C.resolve(ctx.pfx,M.id)) end)
      if ok2 and v then return v end
    end
  end
  return w
end

function M.build(w,ctx) return build(w) end
-- SimpleUI only calls build; kept for engines that measure first.
function M.getHeight(ctx) return build(width(ctx)):getSize().h end

return M
