-- SimpleUI module "Leaf · Tests": summary, the test to continue, and every test with its status.
local Tests=require('english_tests')
local M={id='leaf_tests',name='Leaf · Tests',enabled_key='leaf_tests_enabled',default_on=false}
local function noop() end
M.actions={open=noop,review=noop,retry=noop} -- wired by Leaf at startup
M.io=nil -- checks inject a fake; default is built on first use (docsettings is not loadable at require time)
M.now=os.time
function M.getMenuItems() return nil end

local last -- {width, widget}: getHeight is asked right before build for the same width
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
  local home=G_reader_settings and G_reader_settings:readSetting('home_dir') or '/mnt/us/documents'
  local items=Tests.scan(home..'/IELTS',M.io or Tests.defaultIO())
  if #items==0 then
    text('No tests yet — put test files in documents/IELTS')
    return col
  end
  local function card(it)
    gap();text(it.title,20,'tfont');text(it.meta,15)
    local buttons={}
    local function b(t,fn) buttons[#buttons+1]=Button:new{text=t,height=btnH,width=math.floor((w-pad)/2),callback=function() fn(it.path) end} end
    if it.state=='new' then
      text('Not started',15);b('Start',function(p) M.actions.open(p) end)
    elseif it.state=='progress' then
      local d={};for i=1,math.min(it.total,13) do d[i]=i<=it.answered and '■' or '□' end
      text(table.concat(d,' ')..(it.total>13 and ' …'..it.total or ''),15)
      local left=it.remaining and ('%02d:%02d'):format(math.floor(it.remaining/60),it.remaining%60)
      text(('In progress · %d/%d answered'):format(it.answered,it.total)..(left and ' · '..left..' left' or ''),15)
      b('Continue',function(p) M.actions.open(p) end)
    else
      text(('%d/%d · Band ≈ %s'):format(it.right,it.total,it.band)..(it.rough and ' (rough)' or ''),15)
      b('Review',function(p) M.actions.review(p) end);b('Retry',function(p) M.actions.retry(p) end)
    end
    local row=HG:new{};for _,x in ipairs(buttons) do row[#row+1]=x end
    gap(pad/2);col[#col+1]=row
  end
  local s=Tests.summary(items)
  label('TESTS')
  local cw=math.floor(w/3);local row=HG:new{}
  for _,c in ipairs{{s.count,'tests'},{s.finished,'finished'},{s.lastBand or '—','last band'}} do
    local cell=VG:new{align='left'}
    cell[1]=TB:new{text=tostring(c[1]),face=Font:getFace('tfont',24),width=cw}
    cell[2]=TB:new{text=c[2],face=Font:getFace('cfont',14),width=cw}
    row[#row+1]=cell
  end
  col[#col+1]=row
  local cont=Tests.continueItem(items)
  if cont then label('CONTINUE');card(cont) end
  label('ALL TESTS')
  for _,it in ipairs(Tests.ordered(items)) do if it~=cont then card(it) end end
  return col
end

local function width(ctx) return ctx and (ctx.col_w or ctx.inner_w) or require('device').screen:getWidth() end

function M.build(w,ctx)
  local x=build(w)
  last={w,x}
  return x
end

function M.getHeight(ctx)
  local w=width(ctx)
  local x=last and last[1]==w and last[2] or build(w)
  last={w,x}
  return x:getSize().h
end

return M
