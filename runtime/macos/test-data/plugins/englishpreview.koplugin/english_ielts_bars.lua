-- IELTS test bars: top [Passage][Questions] + timer (or pick form), bottom [Questions →|← Passage][Finish],
-- and a non-modal overlay that shows both over the reader and hands everything else to the reader.
local M={}

local function dims()
  local Screen=require('device').screen
  local s=Screen:scaleBySize(48) -- bar height; button = bar-2 tall + 1px border each side, tap target >= 44
  return Screen:getWidth(),Screen:getHeight(),s
end

-- Equal-width row inside a 1px frame; `selected` buttons are inverted (preselect), as in english_ielts_panel.lua.
local function row(w,items,extra,parent)
  local Frame=require('ui/widget/container/framecontainer')
  local HGroup=require('ui/widget/horizontalgroup')
  local Button=require('ui/widget/button')
  local TextWidget=require('ui/widget/textwidget')
  local Font=require('ui/font')
  local Blitbuffer=require('ffi/blitbuffer')
  local _,_,bh=dims()
  local frame=Frame:new{padding=0,margin=0,bordersize=1,background=Blitbuffer.COLOR_WHITE,width=w,height=bh}
  local g=HGroup:new{align='center'}
  local lw=extra and extra.label and math.floor(w*0.4) or 0
  if lw>0 then g[#g+1]=TextWidget:new{text=extra.label,face=Font:getFace('cfont',18),max_width=lw} end
  local tw=extra and extra.timer and math.floor(w*0.25) or 0
  local bw=math.floor((w-lw-tw-2)/#items)
  for _,b in ipairs(items) do
    g[#g+1]=Button:new{text=b.text,callback=b.callback,preselect=b.selected,width=bw,height=bh-2,padding_v=0,margin=0,bordersize=1,show_parent=parent}
  end
  if extra and extra.timer then g[#g+1]=TextWidget:new{text=extra.timer,face=Font:getFace('cfont',18),max_width=tw} end
  frame[1]=g
  return frame
end

local function call(f) return function() if f then f() end end end

function M.top(w,o,parent)
  if o.pick then
    return row(w,{{text='Done',callback=call(o.on_done)},{text='Cancel',callback=call(o.on_cancel)}},
      {label=('Tap the word for Q%d'):format(o.pick)},parent)
  end
  return row(w,{{text='Passage',selected=o.tab=='passage',callback=call(o.on_passage)},
    {text='Questions',selected=o.tab=='questions',callback=call(o.on_questions)}},{timer=o.timer},parent)
end

function M.bottom(w,o,parent)
  local first=o.view=='questions' and {text='← Passage',callback=call(o.on_passage)} or {text='Questions →',callback=call(o.on_questions)}
  return row(w,{first,{text='Finish',callback=call(o.on_finish)}},nil,parent)
end

function M.confirmFinish(on_yes)
  local UI=require('ui/uimanager')
  UI:show(require('ui/widget/confirmbox'):new{text='Finish and see your score?',ok_text='Finish',cancel_text='Cancel',ok_callback=on_yes})
end

-- Non-modal: gestures/keys outside both bars go to o.forward (the reader). Broadcasts already reach
-- the reader directly, so forwarding them would double them.
function M.overlay(o)
  local UI=require('ui/uimanager')
  local Input=require('ui/widget/container/inputcontainer')
  local Overlap=require('ui/widget/overlapgroup')
  local Geom=require('ui/geometry')
  local w,h,bar=dims()
  local handle={}
  local top,bottom,ov
  local function region(y) return Geom:new{x=0,y=y,w=w,h=bar} end
  local function build()
    if ov[1] and ov[1].free then ov[1]:free() end
    top,bottom=M.top(w,o,ov),M.bottom(w,o,ov)
    bottom.overlap_offset={0,h-bar}
    ov[1]=Overlap:new{dimen=Geom:new{x=0,y=0,w=w,h=h},top,bottom}
  end
  ov=Input:new{name='english_ielts_bars',dimen=Geom:new{x=0,y=0,w=w,h=h}}
  local handleEvent=ov.handleEvent
  ov.handleEvent=function(b,event)
    if handleEvent and handleEvent(b,event) then return true end
    if event.handler~='onGesture' and event.handler~='onKeyPress' and event.handler~='onKeyRepeat' then return end
    local ges=event.handler=='onGesture' and event.args and event.args[1]
    local y=ges and ges.pos and ges.pos.y
    if y and (y<bar or y>=h-bar) then return true end -- a bar's own strip, also beside its buttons
    return o.forward and o.forward(event)
  end
  build()
  UI:show(ov,'ui',region(0))
  UI:setDirty(ov,'ui',region(h-bar))
  function handle:update(n)
    o=n;build()
    UI:setDirty(ov,'ui',region(0));UI:setDirty(ov,'ui',region(h-bar))
  end
  function handle:heights() return bar,bar end
  function handle:close() if ov then UI:close(ov);ov=nil end end
  return handle
end

return M
