local WidgetContainer = require('ui/widget/container/widgetcontainer')
local UIManager = require('ui/uimanager')
local TextViewer = require('ui/widget/textviewer')
local DictQuickLookup = require('ui/widget/dictquicklookup')
local Screen = require('device').screen
local logger = require('logger')
local Preview = WidgetContainer:extend{ name = 'englishpreview' }

-- Tests tab (SimpleUI). Process-wide: the file manager's Preview is gone by the time the test opens.
local tests_registered,pending_review=false,nil
local function openTest(path) require('apps/reader/readerui'):showReader(path) end
local test_actions={
    open=openTest,
    review=function(path) pending_review=path;openTest(path) end,
    retry=function(path)
        UIManager:show(require('ui/widget/confirmbox'):new{text='Clear your answers for this test and start again?',
            ok_text='Retry',cancel_text='Cancel',ok_callback=function()
                local ds=require('docsettings'):open(path)
                local rec=ds:readSetting('leaf_ielts')
                rec=type(rec)=='table' and rec or {}
                ds:saveSetting('leaf_ielts',{mode=rec.mode,margins_added=rec.margins_added,answers={},elapsed=0}) -- as Session:reset
                ds:flush()
                logger.info('Leaf: tests retry',path)
                openTest(path)
            end})
    end,
}

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
        -- progress(pct): estimated Loading % while voca generates (built-in speech has none).
        speak=function(_, text, done, started, progress)
            local a=self._ielts and self._ielts.audio
            if a and a:isPlaying() then a:stop() end -- one sound at a time
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
            end, started, progress)
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
    self:closeIelts()
end

function Preview:onSuspend()
    if self._speech then self._speech:stop() end
    local st=self._ielts
    if st and st.audio then st.audio:stop();self:ieltsDisarm() end
    if st then st.session:pause(os.time()) end -- bars stay, under the screensaver
end

function Preview:onResume()
    local st=self._ielts
    if not st then return end
    if not st.session:finished() then st.session:start(os.time()) end
    -- Refresh in place only: the screensaver may still be up (tap/delay to close), bars must not cover it.
    if st.bars then self:showIeltsBars() end
    local a=st.audio
    if a and not st.session:finished() then
        if st.session:mode()=='practice' then self:ieltsPlayOn() end
        if st.panel then st.panel:updateAudio() end -- ▶/❚❚ and clock, in place
    end
end

-- IELTS Reading: a test EPUB carries META-INF/leaf-ielts.json. Any failure leaves the book as a normal book.
function Preview:loadIelts()
    local review=pending_review -- taken on every open, so it can never apply to a later one
    pending_review=nil
    if not self.ui.rolling or not self.ui.document or not self.ui.document.getDocumentFileContent then return end
    local ok,err=pcall(function()
        local raw=self.ui.document:getDocumentFileContent('META-INF/leaf-ielts.json')
        if not raw then return end
        local test,why=require('english_ielts').parse(raw)
        if not test then logger.info('Leaf: ielts not a test',why);return end
        local session=require('english_ielts_session').new(test,self.ui.doc_settings)
        local st={test=test,session=session}
        st.tick=function() self:ieltsTick() end
        self._ielts=st
        if not session:finished() then session:start(os.time()) end
        UIManager:scheduleIn(60,st.tick)
        logger.info('Leaf: ielts test',test.total,'questions, mode',session:mode() or 'unset')
        -- onReaderReady runs before the reader is shown; bars shown now would end up under it.
        if test.skill=='listening' then
            st.audio=self:ieltsAudio(session:finished())
            if not session:finished() then
                UIManager:nextTick(function() if self._ielts==st then self:startListening() end end)
            else UIManager:nextTick(function() if self._ielts==st then self:showIeltsBars() end end) end
        elseif session:mode() then UIManager:nextTick(function() if self._ielts==st then self:showIeltsBars() end end)
        else self:askIeltsMode() end
        -- Review: after the reader is on screen, or its first paint covers the panel.
        if review and review==self.ui.document.file and session:finished() then
            UIManager:scheduleIn(0.5,function() if self._ielts==st then self:showQuestions() end end)
        end
    end)
    if not ok then logger.info('Leaf: ielts error',err);self:closeIelts() end
end

function Preview:closeIelts()
    local st=self._ielts
    if not st then return end
    pcall(function()
        self:hideIeltsBars()
        if st.audio then st.audio:stop();self:ieltsDisarm() end
        st.session:pause(os.time())
        UIManager:unschedule(st.tick)
    end)
    self._ielts=nil
end

-- Test bars over the reader page: tabs + timer (or the pick form) on top, Questions →/Finish below.
function Preview:ieltsBarOptions()
    local st=self._ielts
    local o={forward=function(event)
        local ok,res=pcall(self.ui.handleEvent,self.ui,event)
        if not ok then logger.info('Leaf: ielts error',res) end
        return ok and res
    end,
    on_questions=function() if st.picking then self:ieltsPickDone() else self:showQuestions() end end,
    on_finish=function() self:ieltsFinish() end}
    if st.picking then
        o.pick=st.picking
        o.on_done=function() self:ieltsPickDone() end
        o.on_cancel=function() self:ieltsPickCancel() end
    else
        o.tab='passage'
        if st.test.skill=='listening' then o.passage_label='Transcript' end
        local left=st.test.skill~='listening' and st.session:remaining(os.time()) -- listening time is the audio's
        if left then o.timer=('%02d:%02d'):format(math.floor(left/60),left%60) end
    end
    return o
end

function Preview:showIeltsBars()
    local st=self._ielts
    if not st then return end
    local ok,err=pcall(function()
        if st.bars then st.bars:update(self:ieltsBarOptions());return end
        st.bars=require('english_ielts_bars').overlay(self:ieltsBarOptions())
        self:ieltsMargins(st.bars:heights())
    end)
    if not ok then logger.info('Leaf: ielts error',err) end
end

function Preview:hideIeltsBars()
    local st=self._ielts
    if st and st.bars then st.bars:close();st.bars=nil end
end

-- Once per book: make room for the bars by adding their height to the book's top/bottom margins.
-- ReaderTypeset keeps margins unscaled (it applies scaleBySize), and saves them from `configurable`.
function Preview:ieltsMargins(top_h,bottom_h)
    local st,ts=self._ielts,self.ui.typeset
    if st.session:marginsAdded() or not ts or not ts.unscaled_margins then return end
    local Event=require('ui/event')
    local function unscaled(px) return math.ceil(px*100/Screen:scaleBySize(100)) end
    local t=ts.unscaled_margins[2]+unscaled(top_h)
    local b=ts.unscaled_margins[4]+unscaled(bottom_h)
    self.ui:handleEvent(Event:new('SetPageTopAndBottomMargin',{t,b}))
    if ts.configurable then ts.configurable.t_page_margin,ts.configurable.b_page_margin=t,b end
    st.session:setMarginsAdded()
    logger.info('Leaf: ielts margins',t,b)
end

function Preview:ieltsFinish()
    local st=self._ielts
    require('english_ielts_bars').confirmFinish(function()
        if self._ielts~=st then return end
        self:ieltsPickEnd()
        st.session:pause(os.time());st.session:finish()
        self:showQuestions()
    end)
end

-- IELTS Listening: audio beside the book (nil without it). Its play/pause/stop hooks keep one sound at a
-- time and the saved position; the audio ending hands over to ieltsAudioEnd.
function Preview:ieltsAudio(quiet)
    local st=self._ielts
    local file=st.test.audio.file
    local path=(self.ui.document.file:match('^(.*)/') or '.')..'/'..file
    local f=io.open(path,'rb')
    if not f then
        if not quiet then UIManager:show(require('ui/widget/infomessage'):new{text='Audio file not found: '..file}) end
        return nil
    end
    f:close()
    local Device=require('device')
    local a=require('english_ielts_audio').new{path=path,rate=st.test.audio.rate,seconds=st.test.audio.seconds,kindle=Device:isKindle()}
    a:seek(st.session:audioPos())
    local play=a.play
    a.play=function(s,...) if self._speech then self._speech:stop() end;return play(s,...) end
    for _,k in ipairs{'pause','stop'} do
        local f=a[k]
        a[k]=function(s) local r=f(s);st.session:setAudioPos(s:position());return r end
    end
    a.on_end=function() self:ieltsAudioEnd() end
    st.autofinish=function() self:ieltsAutoFinish() end
    return a
end

-- Exam check time (after the audio ended): counts down by wall time while the test is open, saved as check_left.
function Preview:ieltsArm(left)
    local st=self._ielts
    UIManager:unschedule(st.autofinish)
    st.check_end=os.time()+left
    UIManager:scheduleIn(left,st.autofinish)
end

function Preview:ieltsDisarm(clear)
    local st=self._ielts
    UIManager:unschedule(st.autofinish)
    if st.check_end and not clear then st.session:setCheckLeft(math.max(0,st.check_end-os.time())) end
    st.check_end=nil
end

-- Exam: play on from the saved position; past the end, wait out the saved (or full) check time.
function Preview:ieltsPlayOn()
    local st=self._ielts
    local pos=st.session:audioPos()
    if pos<st.test.audio.seconds then st.audio:play(pos)
    else self:ieltsArm(st.session:checkLeft() or 120) end
end

function Preview:ieltsRetry()
    local st=self._ielts
    if not st.audio then return end
    st.audio:stop();st.audio:seek(0)
    self:ieltsDisarm(true)
    st.session:setAudioPos(0) -- stop() saved the old position after the reset
    if st.session:mode()=='practice' then self:ieltsPlayOn() end
end

function Preview:startListening()
    local st=self._ielts
    local session=st.session
    local function go(first)
        if not session:mode() then session:setMode('study') end -- prompt dismissed without a choice: no clock
        if st.panel and not st.panel._closed then UIManager:close(st.panel) end -- redrawn in the chosen mode
        self:showQuestions()
        if st.audio and (first or session:mode()=='practice') then self:ieltsPlayOn() end -- Study reopen: paused until play
    end
    if session:mode() then return go() end
    local done=false
    local function once() if not done then done=true;go(true) end end
    self:showQuestions() -- the prompt sits over the questions: the transcript holds the answers
    require('english_popup').show{title='IELTS Listening',
        text='Exam: the audio plays once, timed.\nStudy: pause, go back 10 s, replay a question.',
        on_close=once,
        buttons=function(close) return {{
            {text='Exam',callback=function() session:setMode('practice');close() end},
            {text='Study',callback=function() session:setMode('study');close() end},
        }} end}
end

-- The audio finished by itself: remember it, redraw the open panel, and (exam) finish 2:00 later.
function Preview:ieltsAudioEnd()
    local st=self._ielts
    if not st then return end
    st.session:setAudioPos(st.test.audio.seconds)
    if st.session:finished() then return end -- a "Hear it" clip ended
    if st.session:mode()=='practice' then self:ieltsArm(120) end
    if st.panel then st.panel:updateAudio() end
end

function Preview:ieltsAutoFinish()
    local st=self._ielts
    if not st or st.session:finished() then return end
    if st.audio then st.audio:stop() end
    self:ieltsDisarm(true)
    if st.panel and not st.panel._closed then
        st.panel:closeDialog() -- no answer may change after scoring
        UIManager:close(st.panel,'full')
    end
    st.session:pause(os.time());st.session:finish()
    self:showQuestions()
end

function Preview:askIeltsMode()
    local session=self._ielts.session
    local function pick(mode,close) session:setMode(mode);close() end
    -- Bars come up however the prompt closes (a button or a tap outside).
    require('english_popup').show{title='IELTS Reading',
        text='Practice: timed, like the real test.\nStudy: no timer.\nTap Questions at the top to open the questions.',
        on_close=function() self:showIeltsBars() end,
        buttons=function(close) return {{
            {text='Practice',callback=function() pick('practice',close) end},
            {text='Study',callback=function() pick('study',close) end},
        }} end}
end

-- Once a minute: refresh the countdown, and say once when time is up (answering stays open).
function Preview:ieltsTick()
    local st=self._ielts
    if not st then return end
    local left=st.session:remaining(os.time())
    if left and st.bars then self:showIeltsBars() end
    if left==0 and st.test.skill~='listening' and not st.session:timeUpNoticed() then
        st.session:noteTimeUp()
        logger.info('Leaf: ielts time up')
        UIManager:show(require('ui/widget/infomessage'):new{text='Time is up — you can keep answering.'})
    end
    UIManager:scheduleIn(60,st.tick)
end

-- Passage k is spine item k (OEBPS/passage<k>.xhtml), so DocFragment[k] of the current position.
function Preview:ieltsChapter()
    local ok,xp=pcall(self.ui.document.getXPointer,self.ui.document)
    local k=ok and tonumber(tostring(xp):match('DocFragment%[(%d+)%]')) or 1
    return math.max(1,math.min(k,#(self._ielts.test.passages or {})))
end

-- The panel draws its own bars, so the reader's close while it is open.
function Preview:showQuestions(n,offset)
    local st=self._ielts
    if not st then return end
    local I=require('english_ielts')
    local ok,p=pcall(function() return n and I.passageOf(st.test,n) end)
    local passage=ok and p and p.n or self:ieltsChapter()
    logger.info('Leaf: ielts panel passage',passage)
    self:ieltsPickEnd() -- English tools → Questions mid-pick
    self:hideIeltsBars()
    -- Bars, English tools and returns from pick/evidence all land here: a bad test file must not crash the reader.
    local ok,e=pcall(require('english_ielts_panel').show,{test=st.test,session=st.session,passage=passage,offset=offset,
        results=st.session:finished(),now=os.time,
        on_pick=function(q,off) self:ieltsPick(q,off) end,
        on_passage=function() self:showIeltsBars() end,
        on_evidence=function(q) self:showIeltsBars();self:showEvidence(q) end,
        audio=st.audio,on_open=function(w) st.panel=w end,
        exam_left=st.audio and function()
            if st.check_end then return math.max(0,st.check_end-os.time()) end
            return st.test.audio.seconds-st.audio:position()+120
        end,
        on_hear=function(q) if st.audio then st.audio:play(q.at[1],q.at[2]+1) end end,
        on_finish=function() if st.audio then st.audio:stop();self:ieltsDisarm(true) end end,
        on_retry=function() self:ieltsRetry() end})
    if not ok then logger.info('Leaf: ielts error',e);self:showIeltsBars() end
end

function Preview:ieltsPick(n,offset)
    local st=self._ielts
    st.picking,st.offset,st.pick_before=n,offset,st.session:answer(n)
    logger.info('Leaf: ielts pick start',n)
    self:showIeltsBars()
end

-- Leave pick mode: drop the picked-word highlight.
function Preview:ieltsPickEnd()
    local st=self._ielts
    if not st.picking then return end
    st.picking,st.pick_before=nil,nil
    if st.pick_drawn then st.pick_drawn=nil;pcall(self.ui.document.clearSelection,self.ui.document);UIManager:setDirty(nil,'ui') end
end

function Preview:ieltsPickDone()
    local st=self._ielts
    local n=st.picking
    self:ieltsPickEnd()
    logger.info('Leaf: ielts pick done',n,st.session:answer(n))
    self:showQuestions(n,st.offset)
end

function Preview:ieltsPickCancel()
    local st=self._ielts
    local n=st.picking
    st.session:setAnswer(n,st.pick_before)
    self:ieltsPickEnd()
    logger.info('Leaf: ielts pick cancelled',n)
    self:showQuestions(n,st.offset)
end

-- Bare word: quotes folded (’ becomes '), edges trimmed like answer matching (apostrophes kept).
local function bareWord(s)
    local I=require('english_ielts')
    return I.trim(I.fold(s))
end

function Preview:ieltsPickWord(text,pos0,pos1)
    local st=self._ielts
    local n,word=st.picking,bareWord(text)
    if word=='' then return end
    local a=st.session:answer(n)
    st.session:setAnswer(n,(a and a~='') and a..' '..word or word)
    logger.info('Leaf: ielts picked',n,word)
    if pos0 and pos1 then -- the last picked word stays highlighted, as evidence is drawn
        self.ui.document:getTextFromXPointers(pos0,pos1,true)
        st.pick_drawn=true
        UIManager:setDirty(nil,'ui')
    end
    if st.test.byNumber[n].words==1 then self:ieltsPickDone() end
end

-- Jump to a question's evidence inside its passage chapter. findAllText searches the whole book
-- (findText only searches near the current page); the hit is drawn with getTextFromXPointers
-- and stays until the next page turn or tap.
local MIN_FALLBACK=20 -- the quote-free fallback must be long enough not to match a stray fragment
function Preview:showEvidence(q)
    local st=self._ielts
    if not st or not q then return end
    local I=require('english_ielts')
    local doc=self.ui.document
    local n=type(q.n)=='table' and q.n[1] or q.n
    local p=I.passageOf(st.test,n)
    local ev=q.evidence or ''
    -- Straight vs curly quotes: try as-is, folded, then the longest quote/dash-free run of it.
    local folded,longest=I.fold(ev),''
    for part in folded:gmatch('[^\'"%-]+') do
        part=part:match('^%s*(.-)%s*$')
        if #part>#longest then longest=part end
    end
    if #longest<MIN_FALLBACK then longest='' end
    for _,pattern in ipairs({ev,folded,longest}) do
        if pattern~='' then
            local ok,hits=pcall(doc.findAllText,doc,pattern,true,0,100,false)
            for _,hit in ipairs(ok and type(hits)=='table' and hits or {}) do
                local k=tonumber(tostring(hit.start):match('DocFragment%[(%d+)%]'))
                if not p or k==p.n then
                    logger.info('Leaf: ielts evidence found',n,pattern)
                    st.evidence_page=nil -- the jump fires PageUpdate; it must not clear the new hit
                    -- As ReaderSearch (rolling): keep Go back, jump, draw the selection, repaint.
                    if self.ui.link and self.ui.link.addCurrentLocationToStack then self.ui.link:addCurrentLocationToStack() end
                    self.ui.rolling:onGotoXPointer(hit.start)
                    doc:getTextFromXPointers(hit.start,hit['end'],true)
                    st.evidence_page=doc:getCurrentPage()
                    UIManager:setDirty(nil,'ui')
                    return true
                end
            end
        end
    end
    logger.info('Leaf: ielts evidence not found',n,ev)
    pcall(doc.clearSelection,doc)
    UIManager:show(require('ui/widget/infomessage'):new{text='Could not find this in the passage.'})
    self:showQuestions(n)
end

function Preview:clearIeltsEvidence()
    local st=self._ielts
    if not st or not st.evidence_page then return end
    st.evidence_page=nil
    pcall(self.ui.document.clearSelection,self.ui.document)
    UIManager:setDirty(nil,'ui')
end

function Preview:onPageUpdate(page)
    if self._ielts and self._ielts.evidence_page and page~=self._ielts.evidence_page then self:clearIeltsEvidence() end
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
        logger.info('Leaf: idiom', found and found.headword or 'none')
        if not found then return nil end
        pcall(function() -- no gloss is fine; the idiom still shows
            local time = require('ui/time')
            local started = time.now()
            local results = self.ui.dictionary:startSdcv(found.headword, nil, false)
            logger.info('Leaf: idiom gloss lookup', time.to_ms(time.now()-started), 'ms')
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
    -- sdcv returns near matches too ("nerves" -> nerf, nerve, nerves): prefer the exact word.
    local result=options.results and options.results[1]
    for _,r in ipairs(options.results or {}) do
        if type(r.word)=='string' and r.word:lower()==word:lower() then result=r;break end
    end
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
    logger.info('Leaf: word popup', word, idiom and idiom.headword or '')
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
        self:clearIeltsEvidence()
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
            if self._ielts and self._ielts.picking then -- filling a gap: the word is the answer, not a lookup
                local sel = owner.selected_text
                owner:clear()
                local ok, err = pcall(self.ieltsPickWord, self, sel.text, sel.pos0, sel.pos1)
                if not ok then logger.info('Leaf: ielts error', err) end
                return true
            end
            logger.info('Leaf: tap lookup', owner.selected_text.text)
            owner:lookupDictWord()
            return true
        end
    end
    local originalShow = dictionary.showDict
    dictionary.showDict = function(owner, word, results, boxes, link, callback)
        logger.info('Leaf: showDict', word, results and #results or 'nil', results and results.lookup_cancelled and 'cancelled' or '')
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

-- Once ever (Leaf's own flag): a "Tests" custom screen with the module, its tab right after Home.
-- A tab the user removes later stays removed.
function Preview:installTestsTab()
    if G_reader_settings:isTrue('leaf_tests_tab_done') then return end
    local Screens=require('infra/sui_custom_screens')
    local Store,Config=require('infra/sui_store'),require('infra/sui_config')
    -- A run that failed half-way left its screen behind: reuse it.
    local id=G_reader_settings:readSetting('leaf_tests_screen')
    local screen=id and Screens.get(id)
    if not screen then
        screen=Screens.create('Tests')
        G_reader_settings:saveSetting('leaf_tests_screen',screen.id)
        G_reader_settings:flush()
    end
    Store:saveSetting(screen.pfx..'leaf_tests_enabled',true)
    Store:saveSetting(screen.layout_key,{pages={{id=1,modules={'leaf_tests'}}}})
    Store:flush()
    -- Raw tabs, not loadTabConfig(): before SimpleUI's boot registers the other Custom Screens'
    -- Quick Actions, loadTabConfig() drops their tabs, and saving that would delete them.
    local raw=Store:readSetting('simpleui_bar_tabs')
    local tabs={unpack(type(raw)=='table' and raw or Config.loadTabConfig())}
    local qa=Screens.qaId(screen.id)
    local present=false
    for _,t in ipairs(tabs) do if t==qa then present=true end end
    if present then
        logger.info('Leaf: tests tab already there')
    elseif #tabs<Config.effectiveMaxTabs() then
        local at=1
        for i,t in ipairs(tabs) do if t=='homescreen' then at=i+1;break end end
        table.insert(tabs,at,qa)
        Config.saveTabConfig(tabs)
        logger.info('Leaf: tests tab added at',at)
    else
        logger.info('Leaf: tests tab bar full')
        UIManager:show(require('ui/widget/infomessage'):new{text='The tab bar is full. Add "Tests" from SimpleUI → Tab bar.'})
    end
    G_reader_settings:saveSetting('leaf_tests_tab_done',true)
    G_reader_settings:flush()
end

function Preview:init()
    -- Before the no-document return: the Tests tab lives in the file manager.
    local ok,err=pcall(function()
        local has_sui,Registry=pcall(require,'modules/moduleregistry')
        if not has_sui then return end
        if not tests_registered then
            local mod=require('english_tests_module')
            mod.actions=test_actions
            Registry.register(mod)
            tests_registered=true
        end
        self:installTestsTab()
    end)
    if not ok then logger.info('Leaf: tests tab error',err) end
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
            {text='Questions',enabled_func=function()return self._ielts~=nil end,callback=function()self:showQuestions()end},
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
    self:loadIelts()
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
