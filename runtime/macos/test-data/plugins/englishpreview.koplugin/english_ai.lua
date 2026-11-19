local M={}
function M.new(plugin,viewer)
 local UI=require('ui/uimanager')
 local Info=require('ui/widget/infomessage')
 local DataStorage=require('datastorage')
 local LuaSettings=require('luasettings')
 local Client=require('english_ai_client')
 local Device=require('device')
 local openrouter='https://openrouter.ai/api/v1'
 local free_models={
  {name='Gemma 4 26B A4B · Free',id='google/gemma-4-26b-a4b-it:free'},
  {name='Gemma 4 31B · Free',id='google/gemma-4-31b-it:free'},
  {name='Automatic free model',id='openrouter/free'},
 }
 local base=DataStorage:getSettingsDir()..'/english-ai'
 local store=LuaSettings:open(base..'.lua')
 local self={}
 local function info(text) UI:show(Info:new{text=text}) end
 local function readKey()
  local f=io.open(base..'.key','r');if not f then return '' end
  local key=f:read(4097) or '';f:close();return key:match('^%s*(.-)%s*$')
 end
 local function writeKey(key)
  if key=='' or #key>4096 or key:find('%c') then return nil,'Enter a valid API key.' end
  local ffi=require('ffi');require('ffi/posix_h')
  local C=ffi.C;local temp=base..'.key.new'
  -- Exclusive create refuses pre-existing files and symlinks; rename is atomic.
  local exclusive=ffi.os=='OSX' and 0x800 or ffi.os=='Linux' and 0x80
  if not exclusive then return nil,'Private key storage is supported on Linux and macOS.' end
  local fd=C.open(temp,bit.bor(C.O_WRONLY,C.O_CREAT,exclusive),ffi.cast('mode_t',384))
  if fd<0 then return nil,'Could not save the API key.' end
  local private=C.fchmod(fd,384)==0
  -- User-approved plaintext storage on Kindle USB/FAT32; disclosed in settings.
  local kindle_usb=Device:isKindle() and base:match('^/mnt/us/')~=nil
  local written=(private or kindle_usb) and C.write(fd,key,#key)==#key
  C.close(fd)
  if not written then os.remove(temp);return nil,'Could not save the API key privately.' end
  if not os.rename(temp,base..'.key') then os.remove(temp);return nil,'Could not finish saving the API key.' end
  return true
 end
 local function config()
  -- Reload on explicit AI actions so editing the local file needs no app restart.
  store=LuaSettings:open(base..'.lua')
  return {base_url=store:readSetting('base_url',''),model=store:readSetting('model','')}
 end
 function self:settings(draft)
  local MultiInput=require('ui/widget/multiinputdialog')
  local old=config();local dialog
  local initial=draft or {old.base_url,old.model,''}
  if not draft and old.base_url=='' and old.model=='' then initial={openrouter,free_models[1].id,''} end
  local function chooseModel()
   local fields=dialog:getFields()
   UI:close(dialog)
   local picker,rows
   rows={}
   for _,preset in ipairs(free_models)do
    local chosen=preset
    rows[#rows+1]={{text=chosen.name,callback=function()
     local current=(fields[1] or ''):match('^%s*(.-)%s*$'):gsub('/+$','')
     if current~=openrouter then fields[3]='' end
     fields[1]=openrouter;fields[2]=chosen.id
     UI:close(picker);self:settings(fields)
    end}}
   end
   rows[#rows+1]={{text='Back',callback=function()UI:close(picker);self:settings(fields)end}}
   picker=require('ui/widget/buttondialog'):new{title='OpenRouter free models',buttons=rows}
   UI:show(picker)
  end
  dialog=MultiInput:new{
   title='AI settings',
   fields={
    {text=initial[1],description='API base URL',hint='HTTPS API prefix'},
    {text=initial[2],description='Model ID',hint='Choose a free model or enter a model ID'},
    {text=initial[3] or '',text_type='password',
     description=Device:isKindle() and 'API key · stored as plaintext on USB' or 'API key',
     hint=readKey()~='' and 'Key stored · blank keeps it for the same URL' or 'OpenRouter or provider API key'},
   },
   buttons={{
    {text='Cancel',callback=function()UI:close(dialog)end},
    {text='Save',callback=function()
     local fields=dialog:getFields()
     local valid,err=Client.validate{base_url=fields[1],model=fields[2]}
     if not valid then info(err);return end
     local key=(fields[3] or ''):match('^%s*(.-)%s*$')
     if key~='' then local ok,keyerr=writeKey(key);if not ok then info(keyerr);return end
     elseif valid.base_url~=old.base_url then os.remove(base..'.key') end
     store:saveSetting('base_url',valid.base_url);store:saveSetting('model',valid.model);store:flush()
     UI:close(dialog)
     info(readKey()=='' and 'Settings saved. Add an API key before requesting AI help.' or 'AI settings saved locally. Nothing was sent.')
    end},
   },{{text='Choose OpenRouter free model',callback=chooseModel}}},
  }
  UI:show(dialog);dialog:onShowKeyboard()
  return dialog
 end
 local Popup=require('english_popup')
 local function validText(text)
  if type(text)~='string' or not text:find('%S') then info('Select a sentence or passage first.');return end
  if #text>16000 then info('Select a shorter passage (up to 16 KB).');return end
  return true
 end
 local titles={translate='Translation',explain='Sentence analysis',context='Meaning in context',phrase='Phrase help'}
 local function cache(action,...)
  local args={...}
  local ok,result=pcall(function()
   self._cache=self._cache or require('english_cache').new()
   return self._cache[action](self._cache,unpack(args))
  end)
  return ok and result or nil,ok
 end
 -- Original above translation; a paragraph (one sentence per line) shows as EN/VI pairs
 -- when the line counts match, otherwise as two blocks.
 local function bilingual(source,result)
  local a,b={},{}
  for line in source:gmatch('[^\n]+')do a[#a+1]=line end
  for line in result:gmatch('[^\n]+')do b[#b+1]=line end
  if #a<2 then return source..'\n\n'..result end
  if #a~=#b then return (source:gsub('\n',' '))..'\n\n'..(result:gsub('\n',' ')) end
  local pairs_={}
  for i=1,#a do pairs_[i]=a[i]..'\n'..b[i] end
  return table.concat(pairs_,'\n\n')
 end
 function self:showResult(entry,offline,fallback,scope)
  local title=titles[entry.mode] or 'Saved translation'
  local paragraph=scope and scope.current=='paragraph'
  return Popup.show{title=title,subtitle=entry.provider..(fallback and ' · AI unavailable' or '')..(offline and ' · Offline saved' or ''),
   text=entry.mode=='translate' and bilingual(entry.text,entry.result) or entry.result,tall=paragraph,
   speech=plugin.getSpeech and plugin:getSpeech(),speech_text=(entry.text:gsub('\n',' ')),
   buttons=function(close)
    local rows={{
     {text='Back',font_bold=false,callback=function()
      close();self:showSentence(entry.text,entry.focus,entry.mode=='context' and 'context' or entry.mode=='phrase' and 'phrase' or nil)
     end},
     {text='More',font_bold=false,callback=function()
      close();viewer(title,entry.text..'\n\n'..entry.result)
     end},
    }}
    if entry.mode=='translate' then
     local google=entry.provider:find('Google Translate',1,true)
     table.insert(rows[1],2,{text=google and 'Use AI' or 'Phrase help',font_bold=false,callback=function()
      close();self:showSentence(entry.text,nil,google and 'ai_translate' or 'phrase')
     end})
    end
    -- Sentence | Paragraph: widen or narrow what was translated without selecting text.
    if scope and scope.paragraph then
     local function switch(to)
      if scope.current==to then return end
      close();self:translateContext({sentence=scope.sentence,paragraph=scope.paragraph,current=to},scope.focus)
     end
     table.insert(rows,{
      {text='Sentence',font_bold=not paragraph,callback=function()switch('sentence')end},
      {text='Paragraph',font_bold=paragraph,callback=function()switch('paragraph')end},
     })
    end
    return rows
   end}
 end
 function self:history()
  local entries,ok=cache('list')
  if not ok then info('Could not open translation history.');return end
  if #entries==0 then info('No saved translations yet. Successful results are kept offline automatically.');return end
  local Menu=require('ui/widget/menu')
  local Screen=require('device').screen
  local menu,items
  items={{text='Clear saved translations',callback=function()
   UI:show(require('ui/widget/confirmbox'):new{text='Delete locally saved translations and explanations?',ok_text='Clear',ok_callback=function()
    local _,cleared=cache('clear')
    if cleared then UI:close(menu);info('Translation history cleared.')else info('Could not clear translation history.')end
   end})
  end}}
  for _,entry in ipairs(entries)do
   local saved=entry
   local chars=require('util').splitToChars(entry.text:gsub('%s+',' '))
   items[#items+1]={text=(titles[entry.mode] or 'Translation')..' · '..table.concat(chars,'',1,math.min(80,#chars)),
    callback=function()UI:close(menu);self:showResult(saved,true)end}
  end
  menu=Menu:new{title='Translation history · offline',item_table=items,width=Screen:getWidth(),height=Screen:getHeight()}
  UI:show(menu)
 end
 function self:run(text,mode,checked,key,focus,scope)
  if not validText(text) then return end
  if not titles[mode] then info('Unknown English action.');return end
  if self.busy then info('A request is already running.');return end
  if not checked and mode~='translate' then info('Set up AI for this explanation.');return end
  local provider=checked and (checked.host..' · AI') or 'Google Translate · English → Vietnamese'
  -- Prompt version and destination are part of the identity; keys are never cached.
  local identity=require('json').encode{1,text,mode,focus or '',checked and checked.base_url or 'google-en-vi',checked and checked.model or ''}
  local previous=cache('get',identity)
  if previous then return self:showResult(previous,true,nil,scope) end
  require('socketutil');require('socket.http');require('ssl.https');require('ltn12')
  -- Preload before either worker; fallback must not initialize UI modules in a child.
  local translator=require('ui/translator')
  local googleProvider='Google Translate · English → Vietnamese'
  local function googleTranslation()
   local ok,translation=pcall(translator.translate,translator,text,'vi','en')
   if ok and type(translation)=='string' and translation:find('%S') then return {text=translation} end
   return {error='Translation failed. Check Wi-Fi and try again.'}
  end
  local function successful(result)
   return type(result)=='table' and not result.error and type(result.text)=='string' and result.text:find('%S')
  end
  require('ui/network/manager'):runWhenOnline(function()
   require('ui/trapper'):wrap(function()
    if self.busy then return end
    self.busy=true
    local loading
    local function cancel()
     if loading and loading.dismiss_callback then loading.dismiss_callback() end
    end
    loading=Popup.show{
     title=mode=='translate' and 'Translating…' or 'Analysing sentence…',
     subtitle=provider,text=checked and 'Waiting for AI… Google translation will be used if AI fails.' or 'Waiting for a response…',on_close=cancel,
     buttons=function()return {{{text='Cancel',font_bold=false,callback=cancel}}}end,
    }
    UI:forceRePaint()
    -- ponytail: macOS kills forked children that touch DNS (multi-threaded fork); the Mac preview
    -- runs requests in-process (UI blocks, no Cancel). Kindle/Linux keeps the cancellable subprocess.
    local function worker(fn)
     if Device.isSDL and Device:isSDL() and require('ffi').os=='OSX' then return true,fn() end
     return require('ui/trapper'):dismissableRunInSubprocess(fn,loading)
    end
    local completed,result=worker(function()
     if checked then
      local ok,response=pcall(Client.request,checked,key,text,mode,focus)
      return ok and response or {error='AI request failed.'}
     end
     return googleTranslation()
    end)
    local fallback,offline=false,false
    if completed and checked and not successful(result) then
     fallback=true
     -- A translation belongs to Google's translation identity, never an AI explanation.
     identity=require('json').encode{1,text,'translate','','google-en-vi',''}
     local saved=cache('get',identity)
     if type(saved)=='table' and type(saved.result)=='string' and saved.result:find('%S') then
      result={text=saved.result};offline=true
     else
      completed,result=worker(googleTranslation)
     end
     provider=googleProvider;mode='translate';focus=nil
     if completed and not successful(result) then
      result={error='AI and Google translation failed. Check Wi-Fi and try again.'}
     end
    end
    loading:close_popup(true)
    self.busy=false
    if not completed then info('Request cancelled.');return end
    if not successful(result) then
     info(type(result)=='table' and result.error or 'Request failed. Try again.');return
    end
    local entry={text=text,mode=mode,focus=focus,provider=provider,result=result.text}
    if not offline then cache('put',identity,entry) end
    self:showResult(entry,offline,fallback,scope)
   end)
  end)
 end
 -- context: {sentence=, paragraph=(one sentence per line, optional), current=}
 function self:translateContext(context,focus)
  if not context or not validText(context.sentence) then return end
  local scope={sentence=context.sentence,paragraph=context.paragraph,current=context.current or 'sentence',focus=focus}
  self:run(scope.current=='paragraph' and scope.paragraph or scope.sentence,'translate',nil,nil,nil,scope)
 end
 function self:translateSelection(text)
  if not validText(text) then return end
  -- Everyday translation never spends AI credits or reads a provider key.
  self:run(text,'translate')
 end
 function self:showSentence(text,focus,action)
  if not validText(text) then return end
  local cfg=config();local valid=Client.validate(cfg)
  local ready=valid and readKey()~='' or false
  local destination=action and (ready and (valid.host..' · '..valid.model) or 'AI setup required') or 'Google Translate · online'
  return Popup.show{title=action=='ai_translate' and 'AI translation' or titles[action] or 'Sentence help',subtitle=destination,
   speech=plugin.getSpeech and plugin:getSpeech(),speech_text=text,
   text=(focus and focus~='' and ('Word: '..focus..'\n\n') or '')..text..'\n\nTranslate uses Google. AI runs only when you choose an AI action.'..(action and ready and '\nIf AI fails, Google translates this text instead.' or ''),
   buttons=function(close)
    local function send(mode)
     if mode=='translate' and action~='ai_translate' then close();self:run(text,'translate');return end
     local checked=Client.validate(config())
     local now_ready=checked and readKey()~='' or false
     if not now_ready then info('Set up AI to explain sentences. Google translation is available.');return end
     if ready~=now_ready or (ready and (checked.base_url~=valid.base_url or checked.model~=valid.model)) then
      close();self:showSentence(text,focus,action);return
     end
     local key=now_ready and readKey() or nil
     close();self:run(text,mode,now_ready and checked or nil,key,focus)
    end
    if action=='context' or action=='phrase' then return {{
     {text=action=='context' and 'Explain here' or 'Explain phrase',enabled=ready,callback=function()send(action)end},
     {text='AI settings',callback=function()close();self:settings()end},
    }} end
    local rows={{
     {text=action=='ai_translate' and 'AI translate' or 'Translate',enabled=action~='ai_translate' or ready,font_bold=false,callback=function()send('translate')end},
     {text='AI analysis',enabled=ready,font_bold=false,callback=function()send('explain')end},
    }}
    if action=='ai_translate' then table.insert(rows[1],{text='Phrase help',enabled=ready,font_bold=false,callback=function()send('phrase')end}) end
    if action=='ai_translate' and not ready then rows[2]={{text='AI settings',callback=function()close();self:settings()end}} end
    return rows
   end,
  }
 end

 return self
end
return M
