package.path=arg[1]:match('(.+)/[^/]+$')..'/?.lua;'..package.path
local shown, specs = {}, {}
local saved_words={}
package.preload.english_vocab=function()return {new=function()return {
 isSaved=function(_,word)return saved_words[word]~=nil end,
 save=function(_,word,entry)saved_words[word]=entry;return true end,
 showReview=function()end,
}end}end
local UI = {show = function(_, widget) shown[#shown+1] = widget end, close = function() end}
local nativeSave = function() return 'native save' end
local nativeRows = {{ {id='vocabulary', callback=nativeSave}, {id='close'} }, {{id='english_details'}, {id='english_sentence'}}}
local Dict = {buildButtonLayout = function() return nativeRows end}
package.preload['ui/widget/container/widgetcontainer'] = function() return {extend=function(_, t) return t end} end
package.preload['ui/uimanager'] = function() return UI end
package.preload['ui/widget/textviewer'] = function() return {new=function(_, t) return t end} end
package.preload['ui/widget/dictquicklookup'] = function() return Dict end
package.preload['device'] = function() return {screen={getWidth=function() return 600 end,getHeight=function() return 800 end}} end
local Preview = assert(loadfile(arg[1]))()
local instance = setmetatable({ui={document={},menu={registerToMainMenu=function() end},dictionary={addToDictButtons=function(_, spec) specs[spec.id]=spec end}}},{__index=Preview})
instance:init()
local sentenceRequest
instance.getAI=function()return {showSentence=function(_,text)sentenceRequest=text end}end
local other={results={{dict='Other dictionary'}}}
assert(Dict.buildButtonLayout(other)==nativeRows, 'other dictionaries must retain native layout')
local popup={results={{dict='Sample English-Vietnamese'}}}
local rows=Dict.buildButtonLayout(popup)
assert(#rows==2 and #rows[1]==2 and #rows[2]==2)
assert(rows[1][1].callback==nativeSave, 'must preserve native vocabulary callback')
package.loaded.util={htmlToPlainText=function(s)return (s:gsub('<[^>]+>',''))end}
-- Word details: real dictionary meaning + the actual book sentence, never sample content.
assert(specs.english_details.show_func({word='anyword'}),'details must be available for every real word')
assert(not specs.english_details.show_func({word='x',is_wiki=true}))
instance.ui.doc_props={display_title='Educated'}
instance.ui.toc={getTocTitleOfCurrentPage=function()return 'Chapter 3' end}
local live={selected_text={text='weary'}}
specs.english_details.callback({word='weary',lookupword='weary',dictionary='Real Dict',
    definition='<b>tired</b>',is_html=true,highlight=live})
local details=shown[#shown].text
assert(details:find('tired',1,true) and not details:find('<b>',1,true),'details must show the real, plain-text meaning')
assert(details:find('Real Dict',1,true))
assert(details:find('“weary”',1,true) and details:find('Educated · Chapter 3',1,true),'details must show the book sentence and source')
for _,bad in ipairs({'SAMPLE','WORD FAMILY','Other Side of the Bridge','Mara'}) do
    assert(not details:find(bad,1,true),'details must not contain sample content: '..bad)
end
local detail_buttons=shown[#shown].buttons_table
assert(detail_buttons[1][1].text=='Sentence help' and detail_buttons[#detail_buttons][1].text=='Back')
detail_buttons[1][1].callback()
assert(sentenceRequest=='weary','sentence help must use the live book sentence')
specs.english_details.callback({word='weary',definition='tired',highlight=false})
details=shown[#shown].text
assert(details:find('No book sentence',1,true) and not details:find('“',1,true),'no selection must say so, not invent one')
assert(#shown[#shown].buttons_table==1,'no sentence means no Sentence help button')
sentenceRequest=nil;specs.english_sentence.callback({word='reluctantly'})
assert(sentenceRequest==nil,'sentence help without a selection must not fall back to sample text')
instance.ui.doc_props=nil;instance.ui.toc=nil
print('PASS: native save callback; word details use real meaning, book sentence and source, never samples')
-- Check the alternative study view owns the screen and keeps context across tabs.
local closed, saved_event
UI.close=function(_, widget) closed=widget end
local Widget={}
function Widget:new(t)
    t=t or {}
    t.getSize=function(self)
        if self.dimen then return self.dimen end
        local total=0
        for _,child in ipairs(self) do total=total+child:getSize().h end
        return {w=self.width or 600,h=self.height or (total>0 and total or 24)}
    end
    return t
end
for _, name in ipairs({'container/inputcontainer','container/framecontainer','verticalgroup','verticalspan','titlebar','scrolltextwidget','textwidget','buttontable','linewidget'}) do
    package.preload['ui/widget/'..name]=function() return Widget end
end
package.preload['ui/font']=function() return {getFace=function() return {} end} end
package.preload['ffi/blitbuffer']=function() return {COLOR_WHITE=255} end
package.preload['ui/event']=function() return {new=function(_,...) return {...} end} end
package.preload['ui/geometry']=function() return Widget end
require('device').screen.scaleBySize=function(_, size) return size end
instance.ui.doc_props={display_title='Sample book'}
instance.ui.handleEvent=function(_, event) saved_event=event end
local function find(root, label)
    if root.text==label then return root end
    for _,child in ipairs(root) do
        if type(child)=='table' then local match=find(child,label);if match then return match end end
    end
    for _,row in ipairs(root.buttons or {}) do
        for _,button in ipairs(row) do if button.text==label then return button end end
    end
end
instance:showStudy('reluctantly')
local study=shown[#shown]
assert(study.modal and study.covers_fullscreen and study.dimen.h==800)
assert(study[1].background==255 and study[1].height==800)
local passage=find(study,'Mara reluctantly agreed to leave the familiar village behind.\n\nHer bag waited by the door. Beyond the bridge, every path looked unfamiliar.')
assert(passage, 'context must be visible in its own pane')
find(study,'Word family').callback()
assert(closed==study)
local family=shown[#shown]
assert(find(family,passage.text),'changing help tabs must preserve the passage')
find(family,'Save word').callback()
assert(saved_event[1]=='WordLookedUp' and saved_event[2]=='reluctantly' and saved_event[4]==true)
assert(find(shown[#shown],'Saved').enabled==false)
local last=shown[#shown]
find(last,'Return to book').callback()
assert(closed==last,'return must close the study view')
print('PASS: full-screen study, persistent context, tab switch, native save event and return')

-- The default lookup is compact and leaves the reader visible.
package.preload['ui/widget/textboxwidget']=function() return Widget end
require('ui/widget/container/widgetcontainer').new=Widget.new
instance._study_saved=nil
instance:showSmallPopup('reluctantly')
local small=shown[#shown]
assert(small.modal and not small.covers_fullscreen)
assert(small[1].align=='bottom')
assert(find(small,'More') and find(small,'Save word'))
assert(not find(small,'Word family'),'details must stay out of the first lookup')
find(small,'Save word').callback()
assert(saved_words.reluctantly and saved_words.reluctantly.definition:find('unwilling',1,true),'Save must persist the dictionary meaning')
assert(find(shown[#shown],'Saved').enabled==false)
find(shown[#shown],'More').callback()
assert(shown[#shown].text:find('unwilling',1,true) and not shown[#shown].text:find('WORD FAMILY',1,true))
print('PASS: small popup, persistent save, More opens deeper details')
local dismissals, transfers=0,0
instance:showSmallPopup('reluctantly',{
    on_close=function()dismissals=dismissals+1 end,
    on_more=function()transfers=transfers+1 end,
})
find(shown[#shown],'More').callback()
assert(transfers==1 and dismissals==0,'More must preserve selection until native result closes')
instance:showSmallPopup('reluctantly',{on_close=function()dismissals=dismissals+1 end})
shown[#shown]:onClose()
assert(dismissals==1,'closing lookup must clean up the native selection')
local function at(x,y)return {pos={notIntersectWith=function(_,r)return y<r.y or y>r.y+r.h end}}end
local tapped=instance:showSmallPopup('reluctantly',{on_close=function()dismissals=dismissals+1 end})
tapped[1][1].dimen={x=0,y=600,w=600,h=180}
tapped:onTapClose(nil,at(300,700))
assert(dismissals==1,'tap inside the popup must not close it')
tapped:onTapClose(nil,at(300,100))
assert(dismissals==2,'tap outside the popup must close it and clean up the selection')
print('PASS: popup dismissal cleans selection; More transfers ownership')

instance:showSmallPopup('reluctantly',{results={{no_result=true}}})
assert(find(shown[#shown],'No offline definition found.\nTry another spelling or check your dictionary settings.'),'a missing result must never show a hard-coded sample definition')
instance:showSmallPopup('noon',{results={{no_result=true}}})
assert(shown[#shown].name=='english_small_lookup','unknown word uses the same compact popup')
print('PASS: missing words stay compact and never fabricate a definition')
instance:showSmallPopup('nerves',{results={{dict='en-en',word='nerf',definition='slang: weakening'},{dict='en-en',word='nerves',definition='nervousness'}}})
assert(find(shown[#shown],'nervousness') and not find(shown[#shown],'slang: weakening'),'the exact headword beats near matches returned first by sdcv')
print('PASS: exact headword shown before sdcv near matches')
instance.ui.highlight={selected_text={text='A sentence from the actual selection.'}}
assert(instance:selectedSentence('reluctantly')=='A sentence from the actual selection.','live text must replace sample text')
instance.ui.highlight.selected_text.pos0='start';instance.ui.highlight.selected_text.pos1='end'
instance.ui.rolling=true
instance.ui.document={extendXPointersToSentenceSegment=function()return {text='The full selected sentence, with punctuation.'}end}
assert(instance:selectedSentence('reluctantly')=='The full selected sentence, with punctuation.')
print('PASS: AI sentence preview uses live selection and native sentence extension')

-- Long content shares the same capped viewport and owns its scroll dialog.
local longText=string.rep('Long translation. ',100)
package.loaded['ui/widget/textboxwidget']={new=function(_,options)
 local widget=Widget:new(options)
 if #options.text>500 then widget.height=300 end
 widget.free=function()end
 return widget
end}
package.loaded['ui/widget/scrolltextwidget']={new=function(_,options)
 local widget=Widget:new(options)
 widget.scrollText=function(self)assert(self.dialog,'scrolling must have a dialog owner')end
 return widget
end}
local compact=require('english_popup').show{title='Translation',text=longText,buttons=function()return {{{text='More'}}}end}
local scroll=find(compact,longText)
assert(scroll and scroll.height==125 and scroll.dialog==compact)
scroll:scrollText(1)
assert(not compact.covers_fullscreen)
print('PASS: long translation stays capped and scroll widget has a dialog owner')
local closes,refreshes=0,{}
UI.close=function(_,widget,refresh)closes=closes+1;refreshes[#refreshes+1]=refresh end
local pending=require('english_popup').show{title='Translating…',text='Waiting for a response…',buttons=function()return {{{text='Cancel'}}}end}
pending:close_popup(true);pending:close_popup(true)
assert(closes==1 and refreshes[1]=='ui','closing the popup must redraw its region exactly once')
print('PASS: closing compact loading popup requests a redraw and is idempotent')

instance.ui.highlight={selected_text={text='unfamiliar',pos0='start',pos1='end'},getSelectedWordContext=function()return 'looked ',' to her'end}
instance.ui.document={extendXPointersToSentenceSegment=function()return {text='Every path looked unfamiliar to her.'}end}
instance.ui.rolling=true
instance:showSmallPopup('unfamiliar')
find(shown[#shown],'Save word').callback()
assert(saved_words.unfamiliar.sentence=='Every path looked unfamiliar to her.' and saved_words.unfamiliar.book_title=='Sample book','save must capture the actual sentence and book')
assert(saved_words.unfamiliar.prev_context=='looked ' and saved_words.unfamiliar.next_context==' to her','native vocabulary context must be preserved')
local menu={};instance:addToMainMenu(menu)
assert(menu.english_tools and menu.english_tools.text=='English tools','learning features belong in one menu')
assert(not menu.english_preview and not menu.english_vocabulary_review,'demo and duplicate learning entries must go')
local labels={};for _,item in ipairs(menu.english_tools.sub_item_table)do labels[item.text]=true end
assert(labels['Review 5 words'] and labels['Translation history'] and labels['Performance checks'])
print('PASS: word save captures live sentence and native context; review menu is reachable')
local contextual
instance.getAI=function()return {translateContext=function(_,context,focus)contextual={context=context,focus=focus}end}end
-- Tapped word inside <i> in a paragraph: Sentence finds the sentence and paragraph without dragging.
local paragraph_xp='/body/DocFragment[2]/body/div/p[3]'
instance.ui.highlight={selected_text={text='unfamiliar',pos0=paragraph_xp..'/i/text().4',pos1=paragraph_xp..'/i/text().14'}}
instance.ui.document={
 getTextFromXPointer=function(_,xp)assert(xp==paragraph_xp,'must climb out of inline <i> to the paragraph');return 'He stopped. Every path looked unfamiliar to her. Night came.'end,
 getTextFromXPointers=function(_,a,b)assert(a==paragraph_xp and b:find('/i/text',1,true));return 'He stopped. Every path looked 'end,
}
instance:showSmallPopup('unfamiliar')
assert(not find(shown[#shown],'Explain here'),'Sentence replaces Explain here')
local action=find(shown[#shown],'Sentence')
assert(action and action.enabled,'a tapped word must offer its sentence')
action.callback()
assert(contextual.focus=='unfamiliar' and contextual.context.sentence=='Every path looked unfamiliar to her.')
assert(contextual.context.paragraph=='He stopped.\nEvery path looked unfamiliar to her.\nNight came.')
print('PASS: tap word -> Sentence sends the real sentence and paragraph (one sentence per line); no dragging')
-- Idiom detection: the tapped word inside "gave up" shows the phrase and its gloss above the word meaning.
instance.path=arg[1]:match('(.+)/[^/]+$')
instance._phrases=nil
local idiom_xp='/body/DocFragment[2]/body/div/p[9]'
instance.ui.highlight={selected_text={text='gave',pos0=idiom_xp..'/text().21',pos1=idiom_xp..'/text().25'}}
instance.ui.document={
 getTextFromXPointer=function()return 'In the end, the challenger gave up.'end,
 getTextFromXPointers=function()return 'In the end, the challenger 'end,
}
local looked
-- Real sdcv results arrive as HTML without is_html set (ReaderDictionary sets it later).
instance.ui.dictionary.startSdcv=function(_,word)looked=word;return {{dict='en-en',definition='<div><i>v.</i> <span>1.</span> <b>quit</b> <span>— give up in the face of defeat</span></div>'}}end
local timed=0;package.loaded['ui/time']={now=function() timed=timed+1;return 0 end,to_ms=function(t) return t end}
instance:showSmallPopup('gave',{results={{dict='en-en',definition='past of give',word='gave'}}})
package.loaded['ui/time']=nil
assert(timed>=2,'gloss lookup is timed with ui/time (ms), not os.time')
local popup=shown[#shown]
assert(looked=='give up','the idiom meaning comes from the dictionary headword')
local function has(root,needle)
 if type(root.text)=='string' and root.text:find(needle,1,true) then return true end
 for _,child in ipairs(root)do if type(child)=='table' and has(child,needle) then return true end end
end
assert(has(popup,'IDIOM · gave up → give up\ngive up in the face of defeat\n\npast of give'),'idiom line sits above the word meaning')
looked=nil
find(popup,'Save word').callback()
assert(looked==nil,'redrawing after Save reuses the detected idiom (no second lookup)')
instance.ui.dictionary.startSdcv=function()error('dictionary unavailable')end
instance:showSmallPopup('gave',{results={{dict='en-en',definition='past of give',word='gave'}}})
assert(has(shown[#shown],'IDIOM · gave up → give up\n\npast of give'),'idiom still shows when its gloss lookup fails')
instance.ui.dictionary.startSdcv=nil
print('PASS: tapped word inside an idiom shows the phrase, its base form and gloss; computed once per tap')
assert(not Preview.is_doc_only,'AI settings must be available without an open book')
local registrations=0
local library=setmetatable({ui={dictionary={addToDictButtons=function()error('Library must not install reading hooks')end},menu={registerToMainMenu=function()registrations=registrations+1 end}}},{__index=Preview})
local opened=0
library.getAI=function()return {settings=function()opened=opened+1 end}end
library:init()
local settings_menu={};library:addToMainMenu(settings_menu)
assert(registrations==1 and settings_menu.english_ai_settings.sorting_hint=='setting')
settings_menu.english_ai_settings.callback()
assert(opened==1,'Library Settings must open the same AI configuration form')
print('PASS: AI settings registered in native Settings with no book or dictionary required')
local spoken,done,stops=nil,nil,0
local audible,progress
local speaker={available=function()return true end,speak=function(_,text,callback,started,prog)spoken=text;done=callback;audible=started;progress=prog;return true end,
 stop=function()stops=stops+1;if done then local cb=done;done=nil;cb()end end}
local listening=require('english_popup').show{title='Translation',text='Bản dịch',speech=speaker,speech_text='Read the original English.',buttons=function()return {{{text='More'}}}end}
local listen=find(listening,'Listen')
assert(listen,'translation popup must expose Listen')
listen.callback()
assert(spoken=='Read the original English.' and listen.text=='Loading…','while the voice is generated, Listen shows Loading…')
progress(42);assert(listen.text=='Loading 42%','estimated progress shows on the button')
listen.callback()
assert(stops==1 and listen.text=='Listen','tapping Loading… cancels')
listen.callback();audible()
assert(listen.text=='Stop','once audio plays, the button switches to Stop')
stops=0
listening:close_popup(true)
assert(stops==1,'closing or transferring the popup must stop its speech')
print('PASS: compact Listen/Stop speaks original English and stops when the popup closes')
spoken=nil;listen.callback()
assert(not spoken,'a closed popup must never start speech')
