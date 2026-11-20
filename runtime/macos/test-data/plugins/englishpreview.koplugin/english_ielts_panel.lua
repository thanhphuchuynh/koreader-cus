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
      local used=test.minutes*60-session:remaining(now())
      text(('Time used %02d:%02d'):format(math.floor(used/60),used%60))
    end
    gap()
    for _,row in ipairs(r.rows) do
      local ans=row.answer~='' and row.answer or '—'
      text(row.ok and ('✓ %d. %s'):format(row.n,ans) or ('✗ %d. %s → %s'):format(row.n,ans,row.correct))
      buttons{{text='Show in passage',callback=function() UI:close(widget);o.on_evidence(test.byNumber[row.n]) end}}
    end
    gap()
    buttons{{text='Try again',callback=function() session:reset();redraw{results=false,offset=false} end},
      {text='Done',callback=function() UI:close(widget);o.on_passage() end}}
  else
    local multi=#test.passages>1
    local pn=o.passage or 1
    local dots={}
    for n=1,test.total do dots[#dots+1]=filled(n) and '■' or '□' end
    local head={{text='← Passage',callback=function() UI:close(widget);o.on_passage() end}}
    if multi then for _,p in ipairs(test.passages) do
      head[#head+1]={text=('Passage %d'):format(p.n),callback=function() redraw{passage=p.n,offset=false} end,selected=p.n==pn}
    end end
    choices(head)
    text(table.concat(dots,' ')..'   '..session:footer(now()),15)
    gap()
    local P=multi and test.passages[pn] or nil
    for _,g in ipairs(test.groups or {}) do
      if not P or g.from>=P.from and g.from<=P.to then
        text(g.title,22,'tfont');text(g.instructions)
        for _,l in ipairs(g.list or {}) do text(l) end
        if g.text then
          text((g.text:gsub('{(%d+)}',function(n)
            n=tonumber(n);local a=session:answer(n)
            if not a or a=='' then return '____' end
            return a..(I.overLimit(test.byNumber[n],a) and ' !' or '')
          end)))
        end
        for _,q in ipairs(test.questions) do
          local n=first(q)
          if n>=g.from and n<=g.to then
            if q.type=='gap' then
              local a=session:answer(n)
              buttons{{text=('%d  %s'):format(n,(a and a~='') and a or '____'),callback=function()
                local off=widget._scroll and widget._scroll:getScrolledOffset()
                UI:close(widget);o.on_pick(n,off)
              end}}
            else
              local sel,row={},{}
              local list=session:answer(n)
              if q.type=='multi' then for _,l in ipairs(list or {}) do sel[l]=true end elseif list then sel[list]=true end
              text(('%s. %s'):format(type(q.n)=='table' and q.n[1]..'-'..q.n[#q.n] or n,q.text or ''))
              for _,opt in ipairs(q.options or {}) do
                row[#row+1]={text=opt,selected=sel[opt],callback=function()
                  if q.type=='multi' then
                    local l,out,had={}, {},false
                    for _,x in ipairs(list or {}) do if x==opt then had=true else out[#out+1]=x end end
                    l=out;if not had and #l<(q.picks or #q.n) then l[#l+1]=opt end
                    session:setAnswer(n,l)
                  else session:setAnswer(n,opt) end
                  redraw()
                end}
              end
              choices(row)
            end
          end
        end
        gap()
      end
    end
    buttons{{text='Finish',callback=function() session:pause(now());session:finish();redraw{results=true,offset=false} end}}
  end
  local scroll=Scroll:new{dimen=Geom:new{w=w,h=h},show_parent=widget,FrameContainer:new{padding=pad,bordersize=0,col}}
  widget._scroll=scroll;widget.cropping_widget=scroll
  if o.offset then scroll:setScrolledOffset(o.offset) end
  widget[1]=FrameContainer:new{padding=0,bordersize=0,background=Blitbuffer.COLOR_WHITE,scroll}
  widget._col=col
  UI:show(widget,'full')
  return widget
end
return M
