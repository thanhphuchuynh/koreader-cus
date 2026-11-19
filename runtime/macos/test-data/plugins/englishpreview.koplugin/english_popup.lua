-- Shared compact bottom popup for word lookup, sentence help and results.
local M={}
function M.show(options)
 local UI=require('ui/uimanager')
 local Screen=require('device').screen
 local InputContainer=require('ui/widget/container/inputcontainer')
 local WidgetContainer=require('ui/widget/container/widgetcontainer')
 local FrameContainer=require('ui/widget/container/framecontainer')
 local VerticalGroup=require('ui/widget/verticalgroup')
 local VerticalSpan=require('ui/widget/verticalspan')
 local TitleBar=require('ui/widget/titlebar')
 local TextBoxWidget=require('ui/widget/textboxwidget')
 local ButtonTable=require('ui/widget/buttontable')
 local Font=require('ui/font')
 local Geom=require('ui/geometry')
 local Blitbuffer=require('ffi/blitbuffer')
 local w,h=Screen:getWidth(),Screen:getHeight()
 local pad=Screen:scaleBySize(12)
 local width=w-Screen:scaleBySize(32)
 local dialog=InputContainer:new{name='english_small_lookup',modal=true,dimen=Geom:new{x=0,y=0,w=w,h=h}}
 local frame,buttons
 local speech_started=false
 local closed=false
 local function close(transfer)
  if closed then return end
  closed=true;UI:close(dialog,'ui',frame and frame.dimen)
  if speech_started and options.speech then options.speech:stop();speech_started=false end
  if not transfer and options.on_close then options.on_close() end
 end
 dialog.key_events={Close={{'Back'}}}
 dialog.onClose=function()close();return true end
 -- Tap outside the popup closes it (buttons inside get the tap first).
 dialog.ges_events={TapClose={require('ui/gesturerange'):new{ges='tap',range=dialog.dimen}}}
 dialog.onTapClose=function(_,_,ges)
  if frame and frame.dimen and ges and ges.pos and ges.pos:notIntersectWith(frame.dimen) then close() end
  return true
 end
 dialog.close_popup=function(_,transfer)close(transfer)end
 local title=TitleBar:new{
  width=width-2,title=options.title,subtitle=options.subtitle,align='left',
  title_face=Font:getFace('tfont',22),subtitle_face=Font:getFace('cfont',15),
  with_bottom_line=false,close_callback=function()close()end,
 }
 local definition=TextBoxWidget:new{text=options.text,face=Font:getFace('cfont',18),width=width-2*pad-2}
 local max_height=Screen:scaleBySize(options.tall and 300 or 125) -- tall: paragraph translations
 if definition:getSize().h>max_height then
  definition:free()
  definition=require('ui/widget/scrolltextwidget'):new{
   text=options.text,face=Font:getFace('cfont',18),width=width-2*pad-2,height=max_height,dialog=dialog,
  }
 end
 local rows=options.buttons(close)
 if options.speech and options.speech_text then
  local listen={id='english_speech',text='Listen',font_bold=false,enabled=options.speech:available()}
  -- Listen -> Loading… (voice being generated) -> Stop (audio playing). Tap cancels either.
  local audible=false
  local function update()
   listen.text=not speech_started and 'Listen' or audible and 'Stop' or 'Loading…'
   local button=buttons and buttons.button_by_id and buttons.button_by_id.english_speech
   if not closed and button then
    button:setText(listen.text,button.width)
    UI:setDirty(dialog,'ui',frame and frame.dimen)
   end
  end
  listen.callback=function()
   if closed then return end
   if speech_started then options.speech:stop();return end
   audible=false
   local started,err=options.speech:speak(options.speech_text,function(failure)
    speech_started=false;audible=false
    if closed then return end
    update()
    if failure then UI:show(require('ui/widget/infomessage'):new{text=failure})end
   end,function()
    audible=true
    if not closed and speech_started then update() end
   end)
   speech_started=started==true;update()
   if not started then UI:show(require('ui/widget/infomessage'):new{text=err or 'Speech is unavailable.'})end
  end
  rows[1]=rows[1] or {}
  table.insert(rows[1],math.max(1,#rows[1]),listen)
 end
 buttons=ButtonTable:new{width=width-2*pad-2,buttons=rows}
 local body=VerticalGroup:new{align='left',definition,VerticalSpan:new{width=pad},buttons}
 frame=FrameContainer:new{padding=0,bordersize=1,radius=0,background=Blitbuffer.COLOR_WHITE,
  VerticalGroup:new{align='left',title,FrameContainer:new{padding=pad,padding_top=0,bordersize=0,body}},
 }
 dialog[1]=WidgetContainer:new{dimen=Geom:new{x=0,y=0,w=w,h=h-Screen:scaleBySize(20)},align='bottom',frame}
 UI:show(dialog,'ui')
 return dialog
end
return M
