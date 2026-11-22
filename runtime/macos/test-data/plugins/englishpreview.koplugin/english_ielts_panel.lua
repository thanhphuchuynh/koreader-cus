-- IELTS questions panel + results. Redraw = close and show a new widget with the same options.
local I=require('english_ielts')
local M={}

local function first(q) return type(q.n)=='table' and q.n[1] or q.n end

function M.show(o)
  local UI=require('ui/uimanager')
  local Screen=require('device').screen
  local InputContainer=require('ui/widget/container/inputcontainer')
  local FrameContainer=require('ui/widget/container/framecontainer')
  local Scroll=require('ui/widget/container/scrollablecontainer')
  local VerticalGroup=require('ui/widget/verticalgroup')
  local VerticalSpan=require('ui/widget/verticalspan')
  local TextBox=require('ui/widget/textboxwidget')
  local Button=require('ui/widget/button')
  local HGroup=require('ui/widget/horizontalgroup')
  local ButtonTable=require('ui/widget/buttontable')
  local Font=require('ui/font')
  local Geom=require('ui/geometry')
  local Blitbuffer=require('ffi/blitbuffer')
  local test,session=o.test,o.session
  local w,h=Screen:getWidth(),Screen:getHeight()
  local pad=Screen:scaleBySize(12)
  local inner=w-2*pad
  local now=o.now or os.time
  local widget=InputContainer:new{name='english_ielts_panel',dimen=Geom:new{x=0,y=0,w=w,h=h}}
  local col=VerticalGroup:new{align='left'}
  local dotsText
  local function text(s,size,face)
    col[#col+1]=TextBox:new{text=s,face=Font:getFace(face or 'cfont',size or 18),width=inner}
  end
  local function gap() col[#col+1]=VerticalSpan:new{width=pad} end
  local function buttons(row) col[#col+1]=ButtonTable:new{width=inner,buttons={row}} end
  -- Equal-width row; Button preselect = inverted (black fill, white text) for the selected one.
  local function choices(row)
    local g=HGroup:new{}
    for _,b in ipairs(row) do g[#g+1]=Button:new{text=b.text,callback=b.callback,preselect=b.selected,width=math.floor(inner/#row),show_parent=widget} end
    col[#col+1]=g
  end
  local function redraw(extra)
    local n={};for k,v in pairs(o) do n[k]=v end
    n.offset=widget._scroll and widget._scroll:getScrolledOffset()
    n.refresh='ui' -- in-panel redraws: no flashing full refresh
    UI:close(widget)
    for k,v in pairs(extra or {}) do n[k]=v end
    M.show(n)
  end
  local function filled(n)
    local q=test.byNumber[n]
    if q.type=='multi' then
      local l=session:answer(first(q)) or {}
      for i,x in ipairs(q.n) do if x==n then return #l>=i end end
    end
    local a=session:answer(n);return a~=nil and a~=''
  end

  if o.results then
    local answers={}
    for _,q in ipairs(test.questions) do answers[first(q)]=session:answer(first(q)) end
    local r=I.score(test,answers)
    text('Results',22,'tfont')
    text(('%d/%d'):format(r.right,r.total),22,'tfont')
    if #r.passages>1 then for _,p in ipairs(r.passages) do text(('Passage %d: %d/%d'):format(p.n,p.right,p.total)) end end
    local band,rough=I.band(r.right,r.total)
    text('Band ≈ '..band..(rough and ' (rough)' or ''))
    if session:mode()=='practice' then
      local used=session:elapsed(now())
      text(('Time used %02d:%02d'):format(math.floor(used/60),used%60))
    end
    gap()
    for _,row in ipairs(r.rows) do
      local ans=row.answer~='' and row.answer or '—'
      text(row.ok and ('✓ %d. %s'):format(row.n,ans) or ('✗ %d. %s → %s'):format(row.n,ans,row.correct))
      buttons{{text='Show in passage',callback=function() UI:close(widget);o.on_evidence(test.byNumber[row.n]) end}}
    end
    gap()
    buttons{{text='Try again',callback=function() session:reset();session:start(now());redraw{results=false,offset=false} end},
      {text='Done',callback=function() UI:close(widget);o.on_passage() end}}
  else
    local multi=#test.passages>1
    local pn=o.passage or 1
    local dots={}
    local ns={};for n in pairs(test.byNumber) do ns[#ns+1]=n end;table.sort(ns)
    for _,n in ipairs(ns) do dots[#dots+1]=filled(n) and '■' or '□' end
    if multi then
      local head={}
      for _,p in ipairs(test.passages) do
        head[#head+1]={text=('Passage %d'):format(p.n),callback=function() redraw{passage=p.n,offset=false} end,selected=p.n==pn}
      end
      choices(head)
    end
    dotsText=table.concat(dots,' ')
    local P=multi and test.passages[pn] or nil
    -- Gaps written as {n} inside a group's text are shown there; their rows stay short.
    local inline={}
    for _,g in ipairs(test.groups or {}) do for n in (g.text or ''):gmatch('{(%d+)}') do inline[tonumber(n)]=true end end
    local function shown(n,a)
      if not a or a=='' then return '____' end
      return a..(I.overLimit(test.byNumber[n],a) and ' !' or '')
    end
    local function question(q)
      local n=first(q)
      if q.type=='gap' then
        if q.text then text(q.text) end
        local label=shown(n,session:answer(n))
        if not inline[n] then label=((q.before or '')..' '..label..' '..(q.after or '')):match('^%s*(.-)%s*$') end
        buttons{{text=('%d  %s'):format(n,label),callback=function()
          local off=widget._scroll and widget._scroll:getScrolledOffset()
          UI:close(widget);o.on_pick(n,off)
        end}}
        return
      end
      local sel,row={},{}
      local list=session:answer(n)
      if q.type=='multi' then for _,l in ipairs(list or {}) do sel[l]=true end elseif list then sel[list]=true end
      text(('%s. %s'):format(type(q.n)=='table' and q.n[1]..'-'..q.n[#q.n] or n,q.text or ''))
      for _,opt in ipairs(q.options or {}) do
        row[#row+1]={text=opt,selected=sel[opt],callback=function()
          if q.type=='multi' then
            local l,had={},false
            for _,x in ipairs(list or {}) do if x==opt then had=true else l[#l+1]=x end end
            if not had and #l<(q.picks or #q.n) then l[#l+1]=opt end
            session:setAnswer(n,l)
          else session:setAnswer(n,opt) end
          redraw()
        end}
      end
      choices(row)
    end
    -- Questions in number order; a group's header comes before its first question. Ungrouped ones show too.
    local qs={}
    for _,q in ipairs(test.questions) do
      local n=first(q)
      if not P or n>=P.from and n<=P.to then qs[#qs+1]=q end
    end
    table.sort(qs,function(a,b) return first(a)<first(b) end)
    local current
    for _,q in ipairs(qs) do
      local n,g=first(q),nil
      for _,x in ipairs(test.groups or {}) do if n>=x.from and n<=x.to then g=x;break end end
      if g~=current then
        if current~=nil or g==nil then gap() end
        current=g
        if g then
          if g.title then text(g.title,22,'tfont') end
          if g.instructions then text(g.instructions) end
          for _,l in ipairs(g.list or {}) do text(l) end
          if g.text then text((g.text:gsub('{(%d+)}',function(x) x=tonumber(x);return shown(x,session:answer(x)) end))) end
        end
      end
      question(q)
    end
    gap()
  end
  local Bars,top,bottom,dh=nil,nil,nil,0
  if not o.results then
    Bars=require('english_ielts_bars')
    local function toPassage() UI:close(widget);o.on_passage() end
    local r=session:mode()=='practice' and session:remaining(now())
    top=Bars.top(w,{tab='questions',timer=r and ('%02d:%02d'):format(math.floor(r/60),r%60) or nil,on_passage=toPassage},widget)
    bottom=Bars.bottom(w,{view='questions',on_passage=toPassage,on_finish=function()
      Bars.confirmFinish(function() session:pause(now());session:finish();redraw{results=true,offset=false,refresh='full'} end)
    end},widget)
    dh=Screen:scaleBySize(30)
  end
  local sh=Bars and h-2*Screen:scaleBySize(48)-dh or h -- bar height as in english_ielts_bars.lua
  local scroll=Scroll:new{dimen=Geom:new{w=w,h=sh},show_parent=widget,FrameContainer:new{padding=pad,bordersize=0,col}}
  widget._scroll=scroll;widget.cropping_widget=scroll
  if o.offset then scroll:setScrolledOffset(o.offset) end
  local body=scroll
  if Bars then
    body=VerticalGroup:new{align='left',top,
      FrameContainer:new{padding=0,padding_left=pad,bordersize=0,height=dh,TextBox:new{text=dotsText,face=Font:getFace('cfont',15),width=inner}},
      scroll,bottom}
  end
  widget[1]=FrameContainer:new{padding=0,bordersize=0,background=Blitbuffer.COLOR_WHITE,body}
  widget._col=col
  UI:show(widget,o.refresh or 'full')
  return widget
end
return M
