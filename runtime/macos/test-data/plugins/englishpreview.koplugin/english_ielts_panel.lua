-- IELTS questions panel + results. Redraw = close and show a new widget with the same options.
local I=require('english_ielts')
local M={}

local function mmss(s) s=math.max(0,s);return ('%02d:%02d'):format(math.floor(s/60),math.floor(s%60)) end

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
  local TextWidget=require('ui/widget/textwidget')
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
  local L=test.skill=='listening'
  local audio=o.audio
  local exam=session:mode()=='practice'
  local rowText,top,bottom
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
      local q,b=test.byNumber[row.n],{}
      if L and q.at then b[#b+1]={text='▶ Hear it',callback=function() o.on_hear(q) end} end
      b[#b+1]={text=L and 'Transcript' or 'Show in passage',callback=function() UI:close(widget,'full');o.on_evidence(q) end}
      buttons(b)
    end
    gap()
    buttons{{text='Try again',callback=function() session:reset();session:start(now());redraw{results=false,offset=false} end},
      {text='Done',callback=function() UI:close(widget,'full');o.on_passage() end}}
  else
    local multi=#(test.passages or {})>1
    local pn=o.passage or 1
    local dots={}
    local ns={};for n in pairs(test.byNumber) do ns[#ns+1]=n end;table.sort(ns)
    local Pd=multi and test.passages[pn] or nil
    for _,n in ipairs(ns) do if not Pd or n>=Pd.from and n<=Pd.to then dots[#dots+1]=filled(n) and '■' or '□' end end
    if multi then
      local head={}
      for _,p in ipairs(test.passages) do
        head[#head+1]={text=('Passage %d'):format(p.n),callback=function() redraw{passage=p.n,offset=false} end,selected=p.n==pn}
      end
      choices(head)
    end
    dotsText=table.concat(dots,' ')..('  %d/%d'):format(session:answered(),test.total)
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
        buttons{{text=('%d  %s'):format(n,label),callback=L and function()
          local words=test.byNumber[n].words
          local dialog
          dialog=require('ui/widget/inputdialog'):new{title=('Q%d%s'):format(n,words and (' · up to %d word%s'):format(words,words==1 and '' or 's') or ''),
            input=session:answer(n) or '',buttons={{
              {text='Cancel',callback=function() UI:close(dialog) end},
              {text='Save',callback=function()
                session:setAnswer(n,(dialog:getInputText() or ''):match('^%s*(.-)%s*$'))
                UI:close(dialog);redraw()
              end}}}}
          UI:show(dialog);dialog:onShowKeyboard()
        end or function()
          local off=widget._scroll and widget._scroll:getScrolledOffset()
          UI:close(widget,'full');o.on_pick(n,off)
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
      if L and audio and q.at and session:mode()=='study' then
        buttons{{text=('↺ %d:%02d'):format(math.floor(q.at[1]/60),math.floor(q.at[1]%60)),callback=function() audio:play(q.at[1]) end}}
      end
    end
    gap()
  end
  local Bars,dh,arow=nil,0,0
  if not o.results then
    Bars=require('english_ielts_bars')
    -- 'full': closing with no refresh type repaints the reader but never updates the display (ghosting).
    local function toPassage() UI:close(widget,'full');o.on_passage() end
    local r=exam and (L and o.exam_left and o.exam_left() or session:remaining(now()))
    local function finish() Bars.confirmFinish(function() session:pause(now());session:finish();redraw{results=true,offset=false,refresh='full'} end) end
    if L then
      top=Bars.top(w,{title=test.title or 'Listening',timer=r and mmss(r) or nil},widget)
      bottom=Bars.bottom(w,{view='listening',on_finish=finish},widget)
    else
      top=Bars.top(w,{tab='questions',timer=r and mmss(r) or nil,on_passage=toPassage},widget)
      bottom=Bars.bottom(w,{view='questions',on_passage=toPassage,on_finish=finish},widget)
    end
    dh=Screen:scaleBySize(30)
  end
  if L and Bars then arow=Screen:scaleBySize(48) end
  local sh=Bars and h-2*Bars.height()-dh-arow or h
  local scroll=Scroll:new{dimen=Geom:new{w=w,h=sh},show_parent=widget,FrameContainer:new{padding=pad,bordersize=0,col}}
  widget._scroll=scroll;widget.cropping_widget=scroll
  if o.offset then scroll:setScrolledOffset(o.offset) end
  local body=scroll
  if Bars then
    local audioRow
    if L then
      local at=test.audio.seconds
      local function clock() return mmss(audio:position())..' / '..mmss(at) end
      local g=HGroup:new{align='center'}
      if exam then
        rowText=TextWidget:new{text='▶ '..clock()..' · plays once',face=Font:getFace('cfont',18),max_width=inner}
        g[1]=rowText
      else
        local bw=Screen:scaleBySize(80)
        g[1]=Button:new{text='−10s',width=bw,callback=function() audio:play(math.max(0,audio:position()-10)) end,show_parent=widget}
        g[2]=Button:new{text=audio:isPlaying() and '❚❚' or '▶',width=bw,show_parent=widget,callback=function()
          if audio:isPlaying() then audio:pause() else audio:play(audio:position()) end
          redraw()
        end}
        rowText=TextWidget:new{text=clock(),face=Font:getFace('cfont',18),max_width=inner-2*bw}
        g[3]=rowText
      end
      audioRow=require('ui/widget/container/leftcontainer'):new{dimen=Geom:new{w=w,h=arow},
        FrameContainer:new{padding=0,padding_left=pad,bordersize=0,g}}
      function widget:updateAudio()
        rowText:setText(exam and '▶ '..clock()..' · plays once' or clock())
        if exam and o.exam_left and top.timer_text then top.timer_text:setText(mmss(o.exam_left())) end
        UI:setDirty(widget,'ui',Geom:new{x=0,y=0,w=w,h=Bars.height()+arow}) -- top bar (timer) + audio row only
      end
      local function tick() widget:updateAudio();UI:scheduleIn(10,tick) end
      UI:scheduleIn(10,tick)
      function widget:onCloseWidget() UI:unschedule(tick) end
    end
    body=VerticalGroup:new{align='left',top,
      require('ui/widget/container/leftcontainer'):new{dimen=Geom:new{w=w,h=dh}, -- FrameContainer height is paint-only, not layout
        FrameContainer:new{padding=0,padding_left=pad,bordersize=0,TextBox:new{text=dotsText,face=Font:getFace('cfont',15),width=inner}}},
      scroll,bottom}
    if audioRow then table.insert(body,2,audioRow) end
  end
  widget[1]=FrameContainer:new{padding=0,bordersize=0,background=Blitbuffer.COLOR_WHITE,width=w,height=h,body} -- white to the screen edge
  widget._col=col
  UI:show(widget,o.refresh or 'full')
  return widget
end
return M
