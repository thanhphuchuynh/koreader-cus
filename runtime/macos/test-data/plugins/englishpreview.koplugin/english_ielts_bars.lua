-- IELTS test bars: top [Passage][Questions] + timer (or pick form), bottom [Close][Finish|Results],
-- and a non-modal overlay that shows both over the reader and hands everything else to the reader.
local M={}

function M.height() return require('device').screen:scaleBySize(48) end -- button = bar-2 tall + 1px border each side, tap target >= 44

local function dims()
  local Screen=require('device').screen
  local s=M.height()
  return Screen:getWidth(),Screen:getHeight(),s
end

-- Equal-width buttons (borderless frame, so the bar is exactly M.height()) plus fixed-width label/timer cells,
-- filling exactly w; `selected` buttons are inverted (preselect), as in english_ielts_panel.lua.
local function row(w,items,extra,parent)
  local Frame=require('ui/widget/container/framecontainer')
  local HGroup=require('ui/widget/horizontalgroup')
  local Button=require('ui/widget/button')
  local TextWidget=require('ui/widget/textwidget')
  local Center=require('ui/widget/container/centercontainer')
  local Geom=require('ui/geometry')
  local Font=require('ui/font')
  local Blitbuffer=require('ffi/blitbuffer')
  local _,_,bh=dims()
  local frame=Frame:new{padding=0,margin=0,bordersize=0,background=Blitbuffer.COLOR_WHITE,width=w,height=bh}
  local g=HGroup:new{align='center'}
  local lw=extra and extra.label and (extra.labelw or math.floor(w*0.4)) or 0
  local function cell(text,cw) return Center:new{dimen=Geom:new{w=cw,h=bh},TextWidget:new{text=text,face=Font:getFace('cfont',18),max_width=cw}} end
  if lw>0 then g[#g+1]=cell(extra.label,lw) end
  local tw=extra and extra.timer and math.floor(w*0.25) or 0
  local bw=math.floor((w-lw-tw)/math.max(1,#items))
  for i,b in ipairs(items) do
    local last=i==#items and w-lw-tw-bw*(#items-1) or bw -- last button takes the rounding remainder
    g[#g+1]=Button:new{text=b.text,callback=b.callback,preselect=b.selected,width=last,height=bh-2,padding_v=0,margin=0,bordersize=1,show_parent=parent}
  end
  if tw>0 then local c=cell(extra.timer,tw);frame.timer_text=c[1];g[#g+1]=c end -- kept so the timer can change in place
  frame[1]=g
  return frame
end

local function call(f) return function() if f then f() end end end

function M.top(w,o,parent)
  if o.pick then
    return row(w,{{text='Done',callback=call(o.on_done)},{text='Cancel',callback=call(o.on_cancel)}},
      {label=('Tap the word for Q%d'):format(o.pick)},parent)
  end
  if o.title then -- listening: title + optional timer, no tabs
    local tw=o.timer and math.floor(w*0.25) or 0
    return row(w,{},{label=o.title,labelw=w-tw,timer=o.timer},parent)
  end
  return row(w,{{text=o.passage_label or 'Passage',selected=o.tab=='passage',callback=call(o.on_passage)},
    {text='Questions',selected=o.tab=='questions',callback=call(o.on_questions)}},{timer=o.timer},parent)
end

function M.bottom(w,o,parent)
  -- Close asks first while the test is open; a finished test leaves at once.
  local close={text='Close',callback=o.finished and call(o.on_leave) or function() M.confirmLeave(call(o.on_leave)) end}
  if o.view=='listening' then return row(w,{close,{text='Finish',callback=call(o.on_finish)}},nil,parent) end
  -- Passage/Questions are the top bar's tabs; the bottom leaves the test (the reader's menu sits under the bars)
  -- and finishes it, or, once finished, reopens the results.
  local last=o.finished and {text='Results',callback=call(o.on_questions)} or {text='Finish',callback=call(o.on_finish)}
  return row(w,{close,last},nil,parent)
end

function M.confirmLeave(on_yes)
  local UI=require('ui/uimanager')
  UI:show(require('ui/widget/confirmbox'):new{text='Leave this test?\nYour answers are saved — continue it later from the Tests tab.',
    ok_text='Leave',cancel_text='Stay',ok_callback=on_yes})
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
    -- Swallow only tap/hold/swipe starting in a bar's strip (beside its buttons); releases and drags
    -- always reach the reader, or a hold-drag released over a bar leaves ReaderHighlight stuck.
    local starts=ges and (ges.ges=='tap' or ges.ges=='hold' or ges.ges=='swipe')
    if starts and y and (y<bar or y>=h-bar) then return true end
    return o.forward and o.forward(event)
  end
  build()
  UI:show(ov,'ui',region(0))
  UI:setDirty(ov,'ui',region(h-bar))
  function handle:update(n)
    local same=n.pick==o.pick and n.tab==o.tab and n.view==o.view and n.finished==o.finished -- else only the timer changed
    o=n;build()
    UI:setDirty(ov,'ui',region(0))
    if not same then UI:setDirty(ov,'ui',region(h-bar)) end
  end
  function handle:heights() return bar,bar end
  function handle:close() if ov then UI:close(ov);ov=nil end end
  return handle
end

return M
