local WidgetContainer = require('ui/widget/container/widgetcontainer')
local UIManager = require('ui/uimanager')
local TextViewer = require('ui/widget/textviewer')
local DictQuickLookup = require('ui/widget/dictquicklookup')
local Screen = require('device').screen
local Preview = WidgetContainer:extend{ name = 'englishpreview' }

local samples = {
    reluctantly = {
        base = 'reluctant', formation = 'reluctant + -ly → adverb',
        family = 'reluctant · adjective\nreluctance · noun\nreluctantly · adverb',
        sentence = 'Mara reluctantly agreed to leave the familiar village behind.',
        translation = 'Mara miễn cưỡng đồng ý rời ngôi làng quen thuộc lại phía sau.',
        analysis = 'MEANING\nMara agreed, but she did not really want to leave.\n\nSTRUCTURE\nMara — subject\nreluctantly — adverb: how she agreed\nagreed — past-tense verb\nto leave… — what she agreed to do\n\nEXPRESSION\nLeave something behind: move away from it or depart without taking it.',
    },
    unfamiliar = {
        base = 'unfamiliar', formation = 'un- (not) + familiar → adjective',
        family = 'familiar · adjective\nfamiliarity · noun\nunfamiliar · adjective',
        sentence = 'Beyond the bridge, every path looked unfamiliar.',
        translation = 'Bên kia cây cầu, mọi lối đi đều có vẻ xa lạ.',
        analysis = 'MEANING\nMara has not seen these paths before.\n\nSTRUCTURE\nBeyond the bridge — location\nevery path — subject\nlooked — linking verb, past tense\nunfamiliar — adjective describing the paths\n\nPATTERN\nLook + adjective describes how something appears.',
    },
    threshold = {
        base = 'threshold', formation = 'No simple productive prefix or suffix breakdown.',
        family = 'threshold · noun\nthresholds · plural noun',
        sentence = 'She paused at the threshold and took one last look inside.',
        translation = 'Cô dừng lại ở ngưỡng cửa và nhìn vào trong lần cuối.',
        analysis = 'MEANING\nShe stops at the entrance to her home before leaving.\n\nSTRUCTURE\nShe — subject\npaused … and took … — two past-tense actions\nat the threshold — location\none last look — object of took\n\nEXPRESSION\nTake one last look: look once more before leaving.',
    },
}

local function viewer(title, text, buttons)
    local dialog
    local rows = buttons or {}
    rows[#rows + 1] = {{text = "Back", callback = function() UIManager:close(dialog) end}}
    dialog = TextViewer:new{
        title = title, text = text, text_type = 'lookup', show_menu = false,
        width = Screen:getWidth(), height = Screen:getHeight(),
        buttons_table = rows,
    }
    UIManager:show(dialog)
    return dialog
end

-- Real lookup + real book context only; say so plainly when something is missing.
function Preview:bookSource()
    local title = self.ui.doc_props and self.ui.doc_props.display_title
    local ok, chapter = pcall(function() return self.ui.toc:getTocTitleOfCurrentPage() end)
    chapter = ok and type(chapter) == 'string' and chapter:find('%S') and chapter or nil
    if title and chapter then return title .. ' · ' .. chapter end
    return title or chapter
end

-- ctx: {definition, dictionary, is_html, highlight}; from the native popup or the small popup.
function Preview:showDetails(word, ctx)
    ctx = ctx or {}
    local definition = ctx.definition
    if definition and ctx.is_html then definition = require('util').htmlToPlainText(definition) end
    if not definition or not definition:find('%S') then definition = 'No dictionary meaning available.' end
    local highlight = ctx.highlight
    if highlight == nil then highlight = self.ui.highlight end
    local sentence = highlight and highlight.selected_text and self:selectedSentence(word, highlight)
    local book = sentence
        and ('“' .. sentence .. '”' .. (self:bookSource() and ('\n— ' .. self:bookSource()) or ''))
        or 'No book sentence. Tap the word in your book to see it in context.'
    local buttons = {}
    if sentence then
        buttons[1] = {{text='Sentence help', callback=function() self:getAI():showSentence(sentence, word, 'context') end}}
    end
    viewer(word .. ' · Word details',
        'MEANING · ' .. (ctx.dictionary or 'Offline dictionary') .. '\n' .. definition ..
        '\n\nIN YOUR BOOK\n' .. book, buttons)
end

function Preview:getAI()
    if not self._ai then self._ai=require('english_ai').new(self,viewer) end
    return self._ai
end

-- {sentence=, paragraph=} around a single tapped word (EPUB), or nil.
function Preview:wordContext(highlight)
    highlight=highlight or self.ui.highlight
    local selection=highlight and highlight.selected_text
    if not (self.ui.rolling and selection and selection.pos0 and type(selection.text)=='string')
        or selection.text:find('%s%S') then return nil end
    local ok,context=pcall(require('english_context').around,self.ui.document,selection.pos0)
    return ok and context or nil
end

function Preview:selectedSentence(word, highlight)
    highlight=highlight or self.ui.highlight
    local selection=highlight and highlight.selected_text
    local context=self:wordContext(highlight)
    if context then return context.sentence end
    if selection and selection.text then
        if self.ui.rolling and selection.pos0 and selection.pos1 then
            local ok,extended=pcall(self.ui.document.extendXPointersToSentenceSegment,self.ui.document,selection.pos0,selection.pos1)
            if ok and extended and extended.text then return extended.text end
        end
        return selection.text
    end
end

function Preview:showSentence(word)
    self:getAI():showSentence(self:selectedSentence(word))
end

function Preview:getVocabulary()
    if not self._vocabulary then self._vocabulary=require('english_vocab').new() end
    return self._vocabulary
end

-- Offline voca voice first; Kindle's built-in speech if voca is missing or fails.
function Preview:getSpeech()
    if self._speech then return self._speech end
    local native=require('english_speech').new()
    local voca=require('english_voca').new(self.path or '.')
    self._speech={
        available=function() return voca:available() or native:available() end,
        isSpeaking=function() return voca:isSpeaking() or native:isSpeaking() end,
        stop=function() voca:stop(); native:stop() end,
        -- started(): audio is playing (voca reports it after generating the voice).
        speak=function(_, text, done, started)
            local function native_speak()
                local ok, err = native:speak(text, done)
                if ok and started then started() end
                return ok, err
            end
            if not voca:available() then return native_speak() end
            return voca:speak(text, function(err)
                if err and native:available() then
                    local ok, native_err = native_speak()
                    if ok then return end
                    err = native_err or err
                end
                if done then done(err) end
            end, started)
        end,
    }
    return self._speech
end

function Preview:showSpeechTest()
    return require('english_popup').show{
        title='English speech test',
        text='Pair Bluetooth audio in Kindle Settings first. Tap Listen to test the built-in English voice. No online request is made.',
        speech=self:getSpeech(),speech_text='This is an English speech test. You can listen while reading the translation.',
        buttons=function(close)return {{{text='Close',callback=close}}}end,
    }
end

function Preview:onCloseDocument()
    if self._speech then self._speech:stop() end
end

function Preview:onSuspend()
    if self._speech then self._speech:stop() end
end

function Preview:isWordSaved(word)
    local ok,saved=pcall(function()return self:getVocabulary():isSaved(word)end)
    return ok and saved
end

function Preview:saveWord(word, entry, options)
    local ok=pcall(function()
        local highlight=options and options.highlight
        if highlight==nil then highlight=self.ui.highlight end
        local snapshot={definition=entry.text,dictionary=entry.dictionary or entry.ipa,
            book_title=self.ui.doc_props and self.ui.doc_props.display_title or 'Dictionary lookup'}
        if highlight and highlight.selected_text then
            snapshot.sentence=self:selectedSentence(word,highlight)
            if highlight.getSelectedWordContext then
                snapshot.prev_context,snapshot.next_context=highlight:getSelectedWordContext(15)
            end
            if highlight.selected_text.text~=word then snapshot.highlight=highlight.selected_text.text end
        end
        self:getVocabulary():save(word,snapshot)
    end)
    if not ok then
        UIManager:show(require('ui/widget/infomessage'):new{text='Could not save this word. Try again.'})
    end
    return ok
end

-- A separate native study screen: context and help occupy their own space.
-- This prototype uses sample context; it does not resize or repaginate the book.
function Preview:showStudy(word, tab)
    local sample = samples[word]
    if not sample then return end
    tab = tab or 'meaning'
    local InputContainer = require('ui/widget/container/inputcontainer')
    local FrameContainer = require('ui/widget/container/framecontainer')
    local VerticalGroup = require('ui/widget/verticalgroup')
    local VerticalSpan = require('ui/widget/verticalspan')
    local TitleBar = require('ui/widget/titlebar')
    local ScrollTextWidget = require('ui/widget/scrolltextwidget')
    local TextWidget = require('ui/widget/textwidget')
    local ButtonTable = require('ui/widget/buttontable')
    local LineWidget = require('ui/widget/linewidget')
    local Font = require('ui/font')
    local Blitbuffer = require('ffi/blitbuffer')
    local Event = require('ui/event')
    local w, h = Screen:getWidth(), Screen:getHeight()
    local pad = Screen:scaleBySize(20)
    local gap = Screen:scaleBySize(12)
    local dialog = InputContainer:new{
        name='english_study', modal=true, covers_fullscreen=true,
        dimen=require('ui/geometry'):new{x=0,y=0,w=w,h=h},
    }
    local function close() UIManager:close(dialog) end
    local function switch(next_tab) close(); self:showStudy(word, next_tab) end
    dialog.key_events = { Close = {{'Back'}} }
    dialog.onClose = function() close(); return true end
    local title = TitleBar:new{
        width = w, title = 'Study · ' .. word, align = 'left',
        with_bottom_line = true, close_callback = close,
    }
    local context_label = TextWidget:new{
        text = 'The Other Side of the Bridge · Sample passage',
        face = Font:getFace('smallinfofont', 14),
    }
    local passage = sample.sentence
    if word == 'reluctantly' then passage = passage .. '\n\nHer bag waited by the door. Beyond the bridge, every path looked unfamiliar.' end
    local context_height = math.floor(h * 0.27)
    local context = ScrollTextWidget:new{
        text = passage, face = Font:getFace('cfont', 22),
        width = w - 2*pad, height = context_height,
    }
    local tabs = ButtonTable:new{ width = w - 2*pad, buttons = {{
        {text='Meaning', font_bold=tab=='meaning', callback=function() switch('meaning') end},
        {text='Word family', font_bold=tab=='family', callback=function() switch('family') end},
        {text='Sentence', font_bold=tab=='sentence', callback=function() switch('sentence') end},
    }} }
    local actions = ButtonTable:new{ width = w - 2*pad, buttons = {{
        {text=self._study_saved and self._study_saved[word] and 'Saved' or 'Save word',
         enabled=not (self._study_saved and self._study_saved[word]),
         callback=function()
            self.ui:handleEvent(Event:new('WordLookedUp', word,
                self.ui.doc_props and self.ui.doc_props.display_title or 'English preview', true))
            self._study_saved = self._study_saved or {}; self._study_saved[word] = true
            switch(tab)
         end},
        {text='Return to book', callback=close},
    }} }
    local meaning = {
        reluctantly='/rɪˈlʌk.tənt.li/ · adverb\n\nIn an unwilling or hesitant way.\nMột cách miễn cưỡng, ngần ngại.\n\nBase word: reluctant',
        unfamiliar='/ˌʌn.fəˈmɪl.i.ər/ · adjective\n\nNot known or recognized.\nXa lạ, không quen thuộc.\n\nBase word: unfamiliar',
        threshold='/ˈθreʃ.həʊld/ · noun\n\nThe entrance to a room or building.\nNgưỡng cửa.\n\nBase word: threshold',
    }
    local text = tab=='family' and (sample.formation .. '\n\n' .. sample.family)
        or tab=='sentence' and ('SAMPLE ANALYSIS · NO ONLINE REQUEST\n\n' .. sample.translation .. '\n\n' .. sample.analysis)
        or meaning[word]
    local help_height = h - title:getSize().h - context_label:getSize().h - context_height
        - tabs:getSize().h - actions:getSize().h - gap*6 - 2
    local help = ScrollTextWidget:new{
        text=text, face=Font:getFace('cfont', 20), width=w-2*pad,
        height=math.max(Screen:scaleBySize(80), help_height),
    }
    local content = VerticalGroup:new{align='left',
        VerticalSpan:new{width=gap}, context_label, VerticalSpan:new{width=gap},
        context, VerticalSpan:new{width=gap},
        LineWidget:new{dimen={w=w-2*pad,h=1}},
        VerticalSpan:new{width=gap}, tabs, VerticalSpan:new{width=gap},
        help, VerticalSpan:new{width=gap}, actions,
    }
    dialog[1] = FrameContainer:new{ width=w, height=h, padding=0, bordersize=0, background=Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{align='left', title,
            FrameContainer:new{padding=0,padding_left=pad,padding_right=pad,bordersize=0,content},
        },
    }
    UIManager:show(dialog, 'full')
end

-- Idiom/phrasal verb around the tapped word (offline index), with a one-line dictionary gloss.
-- Returns {text=as written, headword=, gloss=} or nil. Any failure just means "no idiom".
function Preview:idiomFor(highlight)
    local ok, idiom = pcall(function()
        local context = self:wordContext(highlight)
        if not context or not context.text then return nil end
        if self._phrases == nil then
            self._phrases = require('english_phrases').new((self.path or '.')..'/english_phrases.tsv') or false
        end
        local found = self._phrases and self._phrases:find(context.text, context.at)
        if not found then return nil end
        pcall(function() -- no gloss is fine; the idiom still shows
            local results = self.ui.dictionary:startSdcv(found.headword, nil, false)
            local first = results and results[1]
            if first and not first.no_result and first.definition then
                -- startSdcv results don't carry is_html yet (set later by ReaderDictionary): sniff tags.
                local html = first.is_html or first.definition:find('<%a') ~= nil
                local plain = html and require('util').htmlToPlainText(first.definition) or first.definition
                found.gloss = require('english_phrases').gloss(plain)
            end
        end)
        return found
    end)
    return ok and idiom or nil
end

-- Compact sample lookup; deeper help stays behind More.
function Preview:showSmallPopup(word, options)
    options=options or {}
    local short = {
        reluctantly = {ipa='/rɪˈlʌk.tənt.li/ · adverb', text='In an unwilling or hesitant way.\nMột cách miễn cưỡng, ngần ngại.'},
        unfamiliar = {ipa='/ˌʌn.fəˈmɪl.i.ər/ · adjective', text='Not known or recognized.\nXa lạ, không quen thuộc.'},
        threshold = {ipa='/ˈθreʃ.həʊld/ · noun', text='The entrance to a room or building.\nNgưỡng cửa.'},
    }
    local result=options.results and options.results[1]
    local entry
    if result and result.no_result then
        entry={ipa='Offline dictionary',text='No offline definition found.\nTry another spelling or check your dictionary settings.'}
    else
        entry=(not result or result.dict=='Sample English-Vietnamese') and short[word] or nil
    end
    if not entry then
        if not result then return end
        entry={ipa=result.dict or 'Offline dictionary', text=result.is_html and require('util').htmlToPlainText(result.definition or '') or result.definition or ''}
    end
    entry.dictionary=result and result.dict or 'Sample English-Vietnamese'
    local saved=self:isWordSaved(word)
    local context_highlight=options.highlight
    if context_highlight==nil then context_highlight=self.ui.highlight end
    -- Computed once per tap; reused when the popup redraws (e.g. after Save word).
    if options.idiom==nil then options.idiom=context_highlight and self:idiomFor(context_highlight) or false end
    local idiom=options.idiom
    local text=entry.text
    if idiom then
        text='IDIOM · '..idiom.text..(idiom.headword~=idiom.form and (' → '..idiom.headword) or '')
            ..(idiom.gloss and ('\n'..idiom.gloss) or '')..'\n\n'..text
    end
    return require('english_popup').show{
        title=word,subtitle=entry.ipa,text=text,on_close=options.on_close,
        speech=self:getSpeech(),speech_text=word,
        buttons=function(close)return {{
            {text=saved and 'Saved' or 'Save word',
             enabled=not saved and not (result and result.no_result),font_bold=false,
             callback=function()
                if self:saveWord(word,entry,options) then
                    close(true);self:showSmallPopup(word,options)
                end
             end},
            -- Tap word -> Sentence: no dragging. Google first; Paragraph/Use AI on the result.
            {text='Sentence',font_bold=false,enabled=context_highlight and context_highlight.selected_text~=nil or false,
             callback=function()
                local context=self:wordContext(context_highlight)
                    or {sentence=self:selectedSentence(word,context_highlight)}
                close();self:getAI():translateContext(context,word)
             end},
            {text='More',font_bold=false,callback=function()
                close(true)
                if options.on_more then options.on_more() else
                    self:showDetails(word,{definition=entry.text,dictionary=entry.dictionary,highlight=context_highlight})
                end
             end},
        }}end,
    }
end

function Preview:installTapLookup()
    local highlight = self.ui.highlight
    local dictionary = self.ui.dictionary
    if not highlight or not dictionary then return end
    local originalRelease = highlight.onHoldRelease
    highlight.onHoldRelease = function(owner, ...)
        local selection = owner.selected_text
        if not owner.clear_id and not owner.select_mode and owner.hold_pos
            and not owner.is_word_selection and selection and type(selection.text) == 'string' then
            -- Count English words, ignoring isolated punctuation and trailing whitespace.
            -- Apostrophes and hyphens within one token still belong to a single word.
            local words = 0
            for token in selection.text:gmatch('%S+') do
                if token:find('%w') then words = words + 1 end
                if words > 1 then
                    local text = selection.text
                    owner:_resetHoldTimer(true)
                    owner:clear() -- Also cleans up if the user cancels the Wi-Fi prompt.
                    self:getAI():translateSelection(text)
                    return true
                end
            end
        end
        return originalRelease(owner, ...)
    end
    local originalTap = highlight.onTap
    highlight.onTap = function(owner, arg, ges)
        local handled = originalTap(owner, arg, ges)
        if handled then return handled end
        -- EPUB text only. Reserve edges/top/footer for ordinary reading controls.
        if not self.ui.rolling or owner.select_mode or owner.hold_pos or not ges or not ges.pos then return end
        local p = ges.pos
        local w,h = Screen:getWidth(),Screen:getHeight()
        if p.x < w*0.08 or p.x > w*0.92 or p.y < h*0.08 or p.y > h*0.94 then return end
        local pos = owner.view:screenToPageTransform(p)
        if not pos then return end
        local ok, word = pcall(self.ui.document.getWordFromPosition,self.ui.document,pos,true)
        local box = ok and word and word.sbox
        if not box or pos.x < box.x or pos.x > box.x+box.w or pos.y < box.y or pos.y > box.y+box.h then return end
        -- Native selection owns word boxes, language support and vocabulary context.
        if owner:onHold(arg,ges) and owner.selected_text then
            owner:_resetHoldTimer(true)
            owner:lookupDictWord()
            return true
        end
    end
    local originalShow = dictionary.showDict
    dictionary.showDict = function(owner, word, results, boxes, link, callback)
        if owner.is_wiki or not results or not results[1] or results.lookup_cancelled then
            return originalShow(owner,word,results,boxes,link,callback)
        end
        if owner.dismissLookupInfo then owner:dismissLookupInfo() end
        self:showSmallPopup(word,{
            results=results, boxes=boxes, highlight=owner.highlight or false,
            on_close=function()
                if owner.highlight then owner.highlight:clear() end
                if callback then callback() end
            end,
            on_more=function() originalShow(owner,word,results,boxes,link,callback) end,
        })
    end
end

function Preview:init()
    self.ui.menu:registerToMainMenu(self)
    local dictionary = self.ui.dictionary
    if not dictionary or not self.ui.document then return end
    self:installTapLookup()
    if self.ui.highlight and self.ui.highlight.addToHighlightDialog then
        self.ui.highlight:addToHighlightDialog('14_english_ai',function(highlight)
            return {text='Sentence help',callback=function()
                local text=self:selectedSentence()
                if highlight.highlight_dialog then UIManager:close(highlight.highlight_dialog) end
                self:getAI():showSentence(text)
            end}
        end)
    end
    dictionary:addToDictButtons{
        id = 'english_details', text = 'Word details', font_bold = false, menu_text = 'English word details',
        callback = function(popup)
            self:showDetails(popup.lookupword or popup.word, {definition=popup.definition,
                dictionary=popup.dictionary, is_html=popup.is_html, highlight=popup.highlight or false})
        end,
        show_func = function(popup) return not popup.is_wiki end,
    }
    dictionary:addToDictButtons{
        id = 'english_sentence', text = 'Sentence help', font_bold = false, menu_text = 'English sentence help',
        callback = function(popup) self:showSentence(popup.word) end,
        show_func = function(popup) return self:selectedSentence(popup.word) ~= nil end,
    }
    -- Keep the native popup and callbacks; compact only the local sample dictionary.
    if not DictQuickLookup._english_preview_layout then
        DictQuickLookup._english_preview_layout = true
        local build = DictQuickLookup.buildButtonLayout
        function DictQuickLookup:buildButtonLayout()
            local rows = build(self)
            if self.is_wiki or not self.results or not self.results[1]
                or self.results[1].dict ~= 'Sample English-Vietnamese' then return rows end
            local pool = {}
            for _, row in ipairs(rows) do
                for _, button in ipairs(row) do pool[button.id] = button end
            end
            if not pool.english_details or not pool.english_sentence or not pool.close then return rows end
            if pool.vocabulary then pool.vocabulary.text = 'Save word' end
            return {
                pool.vocabulary and {pool.vocabulary, pool.english_details} or {pool.english_details},
                {pool.english_sentence, pool.close},
            }
        end
    end
end

function Preview:addToMainMenu(items)
    items.english_ai_settings={text='AI settings',sorting_hint='setting',callback=function()
        self:onShowEnglishAISettings()
    end}
    local review={text='Review 5 words',callback=function()
        local ok=pcall(function()self:getVocabulary():showReview()end)
        if not ok then UIManager:show(require('ui/widget/infomessage'):new{text='Could not open saved words. Try again.'}) end
    end}
    items.english_tools = {
        text = 'English tools', sorting_hint = 'more_tools',
        sub_item_table = {
            review,
            {text='Translation history',callback=function()self:getAI():history()end},
            {text='Test English speech',callback=function()self:showSpeechTest()end},
            {text='Sentence help',enabled=self.ui.highlight and self.ui.highlight.selected_text~=nil or false,
             callback=function()self:showSentence()end},
            {text='Performance checks',sub_item_table={
                {text='Check dictionary and popup',callback=function()self:getPerformance():checkLookup()end},
                {text='Measure next page turn',callback=function()self:getPerformance():armPageTurn()end},
                {text='View last measurements',callback=function()self:getPerformance():show()end},
            }},
        },
    }
end

function Preview:onShowEnglishAISettings()
    self:getAI():settings()
    return true
end

function Preview:getPerformance()
    if not self._performance then self._performance=require('english_perf').new(self) end
    return self._performance
end

function Preview:onReaderReady()
    local scene = os.getenv('KINDLE_ENGLISH_PREVIEW')
    if not scene then return end
    UIManager:scheduleIn(0.5, function()
        if scene == 'google-demo' then self:getAI():run(samples.reluctantly.sentence,'translate')
        elseif scene == 'ai-settings' then self:getAI():settings()
        elseif scene == 'read' then return
        elseif scene == 'review' then self:getVocabulary():showReview()
        elseif scene == 'small' then self:showSmallPopup('reluctantly')
        elseif scene == 'study' then self:showStudy('reluctantly')
        elseif scene == 'details' then self:showDetails('reluctantly')
        elseif scene == 'sentence' then self:showSentence('reluctantly')
        else self.ui.dictionary:onLookupWord(os.getenv('KINDLE_ENGLISH_WORD') or 'reluctantly', true) end
    end)
end
return Preview
