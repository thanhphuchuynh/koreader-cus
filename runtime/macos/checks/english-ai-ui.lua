local directory=assert(arg[1])
local cached_entries={}
package.loaded.english_cache={new=function()return {
 get=function(_,key)return cached_entries[key] end,
 put=function(_,key,value)cached_entries[key]=value end,
 list=function()local items={};for _,item in pairs(cached_entries)do items[#items+1]=item end;return items end,
 clear=function()cached_entries={} end,
}end}

local metadata,shown,inputs,requests={}, {}, {}, {}
local kindle=false
package.loaded.device={isKindle=function()return kindle end}
package.loaded['ui/widget/buttondialog']={new=function(_,t)return t end}
local paints=0
local UI={show=function(_,v)shown[#shown+1]=v end,close=function()end,forceRePaint=function()paints=paints+1 end}
package.loaded['ui/uimanager']=UI
package.loaded['ui/widget/infomessage']={new=function(_,t)return t end}
package.loaded['datastorage']={getSettingsDir=function()return directory end}
package.loaded['luasettings']={open=function()
 local snapshot={};for k,v in pairs(metadata)do snapshot[k]=v end
 return {
 readSetting=function(_,k,d)return snapshot[k] or d end,
 saveSetting=function(_,k,v)metadata[k]=v;snapshot[k]=v end,flush=function()end,
 }end}
package.loaded['ui/widget/multiinputdialog']={new=function(_,t)
 t.getFields=function()return inputs end;t.onShowKeyboard=function()end;return t
end}
for _,name in ipairs({'socketutil','socket.http','ssl.https','ltn12'}) do
 package.loaded[name]=nil;package.preload[name]=function()return {}end
end
local google={}
package.loaded['ui/translator']={translate=function(_,text,target,source)google[#google+1]={text=text,source=source,target=target};return 'Bản dịch mẫu từ Google.' end}
local runs=0
package.loaded['ui/network/manager']={runWhenOnline=function(_,fn)runs=runs+1;fn()end}
local cancel=false
package.loaded['ui/trapper']={wrap=function(_,fn)fn()end,dismissableRunInSubprocess=function(_,fn,loading)
 assert(type(loading)=='table' and loading.kind=='compact','API calls must show a compact loading popup')
 assert(loading.buttons[1][1].text=='Cancel' and paints>0,'loading must be painted with a Cancel action before the worker')
 assert(package.loaded['socket.http'] and package.loaded['ssl.https'],'network modules must be loaded before the worker')
 if cancel then
  local dismissed=false
  loading.dismiss_callback=function()dismissed=true end
  loading.buttons[1][1].callback()
  assert(dismissed,'Cancel must invoke the worker dismiss callback')
  return false
 end
 return true,fn()
end}
local client=require('english_ai_client')
client.request=function(cfg,key,text,mode)
 requests[#requests+1]={config=cfg,key=key,text=text,mode=mode};return {text='Translated sentence'}
end
local views={}
package.loaded['english_popup']={show=function(options)
 local view={title=options.title,text=options.text,subtitle=options.subtitle,kind='compact',speech_text=options.speech_text}
 local function close(transfer)
  if view.closed then return end
  view.closed=true
  if not transfer and options.on_close then options.on_close() end
 end
 view.close_popup=function(_,transfer)close(transfer)end
 view.buttons=options.buttons(close)
 views[#views+1]=view
 return view
end}
local ai=require('english_ai').new({},function(title,text,buttons)
 local view={title=title,text=text,buttons=buttons};views[#views+1]=view;return view
end)
ai:showSentence('By noon, the road had narrowed.')
assert(#requests==0 and #google==0,'preview must not send')
assert(views[#views].kind=='compact','sentence preview must use the shared dictionary-sized popup')
assert(views[#views].subtitle:find('Google Translate',1,true),'unconfigured translation must identify Google')
assert(views[#views].buttons[1][2].enabled==false,'sentence explanation still requires AI')
views[#views].buttons[1][2].callback()
assert(#requests==0 and #google==0,'disabled AI explanation must not send')
views[#views].buttons[1][1].callback()
assert(#requests==0 and #google==1 and runs==1,'without AI setup, Translate must use the native Google translator')
assert(views[#views].kind=='compact' and views[#views].text=='By noon, the road had narrowed.\n\nBản dịch mẫu từ Google.','Google results must use compact popup')
assert(views[#views].speech_text=='By noon, the road had narrowed.','speech must read the original English, not the Vietnamese result')
assert(google[1].source=='en' and google[1].target=='vi' and google[1].text=='By noon, the road had narrowed.')
ai:settings();local settings=shown[#shown]
assert(settings.fields[3].text=='' and settings.fields[3].text_type=='password')
assert(settings.fields[1].text=='https://openrouter.ai/api/v1' and settings.fields[2].text=='google/gemma-4-26b-a4b-it:free','empty config should offer OpenRouter defaults without saving')
inputs={settings.fields[1].text,settings.fields[2].text,'draft-test-key'}
settings.buttons[2][1].callback()
local picker=shown[#shown]
assert(picker.title=='OpenRouter free models')
picker.buttons[2][1].callback()
local selected=shown[#shown]
assert(selected.fields[2].text=='google/gemma-4-31b-it:free' and selected.fields[3].text=='draft-test-key')
assert(not metadata.base_url,'choosing a model must not persist settings or send requests')
selected.buttons[1][1].callback()

inputs={'https://provider.example/v1','model','test-key-not-a-real-secret'}
settings.buttons[1][2].callback()
assert(metadata.base_url==inputs[1] and metadata.model==inputs[2])
for _,value in pairs(metadata)do assert(value~=inputs[3],'secret must not enter normal preferences')end
local key=assert(io.open(directory..'/english-ai.key'))
assert(key:read('*a')==inputs[3]);key:close()
ai:showSentence('By noon, the road had narrowed.')
local preview=views[#views];assert(preview.subtitle:find('Google Translate',1,true) and not preview.text:find(inputs[3],1,true),'default preview must identify Google even with AI configured')
preview.buttons[1][1].callback()
assert(#requests==0 and #google==1 and views[#views].subtitle:find('Offline saved',1,true),'configured default Translate must reuse Google cache without AI')
assert(views[#views].buttons[1][2].text=='Use AI','Google result must offer explicit AI action')
views[#views].buttons[1][2].callback()
assert(#requests==0 and views[#views].subtitle:find('provider.example',1,true),'Use AI must preview the destination before sending')
views[#views].buttons[1][1].callback()
assert(#requests==1 and requests[1].mode=='translate' and requests[1].text=='By noon, the road had narrowed.')
assert(views[#views].title=='Translation' and views[#views].kind=='compact' and #google==1,'configured AI translation must not also call Google')
-- Changing provider requires a fresh preview and clears an old key when no new one is entered.
ai:showSentence('Another sentence.');local stale=views[#views]
ai:settings();inputs={'https://other.example/v1','model',''};shown[#shown].buttons[1][2].callback()
assert(not io.open(directory..'/english-ai.key'),'changing provider must not reuse its secret')
stale.buttons[1][2].callback();assert(#requests==1)
ai:settings();inputs={'https://other.example/v1','model','test-key-not-a-real-secret'};shown[#shown].buttons[1][2].callback()
ai:showSentence('Cancellation check.');cancel=true;views[#views].buttons[1][2].callback()
assert(#requests==1 and shown[#shown].text=='Request cancelled.')
assert(not ai.busy)
metadata.base_url='https://file-config.example/v1';metadata.model='file-model'
ai:showSentence('File configuration reload.')
ai:showSentence('File configuration reload.',nil,'ai_translate')
assert(views[#views].subtitle:find('file%-config.example') and views[#views].subtitle:find('file%-model'),'file edits must be read without restarting')
print('PASS: masked settings, separate key file, explicit-send only, destination changes, missing-key guard and cancellation; no network')

cancel=false
client.request=function()return {error='Provider unavailable'}end
ai:showSentence('Configured provider failure.',nil,'ai_translate')
views[#views].buttons[1][1].callback()
assert(views[#views].title=='Translation' and views[#views].text:find('\n\nBản dịch mẫu từ Google.$') and #google==2,'AI failure must fall back to Google translation')
assert(views[#views].subtitle:find('Google Translate',1,true) and views[#views].subtitle:find('AI unavailable',1,true),'fallback must identify Google and AI failure')
print('PASS: Google fallback after configured AI failure, explicit provider and translation label')

for _,view in ipairs(views)do
 if view.title=='Translating…' or view.title=='Analysing sentence…' then
  assert(view.closed,'loading must close after success, error or cancellation')
 end
end
print('PASS: loading shown before worker, compact Cancel action, loading closed on all outcomes')

local automatic
client.request=function(cfg,key,text,mode)automatic={cfg=cfg,key=key,text=text,mode=mode};return {text='Automatic translation'}end
ai:translateSelection('Only these selected words')
assert(not automatic and #google==3 and google[3].text=='Only these selected words','auto selection must use Google even with AI configured')
assert(views[#views].title=='Translation' and #google==3,'auto translation must skip preview and use Google')
os.remove(directory..'/english-ai.key')
ai:translateSelection('Selected phrase')
assert(#google==4 and google[4].text=='Selected phrase','unconfigured auto selection uses Google')
local before=runs
ai:translateSelection('   ');ai:translateSelection(string.rep('x',16001))
assert(runs==before,'invalid and oversized selections must not send')
print('PASS: automatic selection always uses Google, with text limits and compact loading; AI is explicit')

local online_before=runs
ai:translateSelection('Offline cache test.')
assert(runs==online_before+1)
local sent_before=runs
ai:translateSelection('Offline cache test.')
assert(runs==sent_before and views[#views].subtitle:find('Offline saved',1,true),'cached translations must bypass Wi-Fi and worker')
local last=views[#views]
assert(last.buttons[1][2].text=='Use AI')
last.buttons[1][2].callback()
assert(views[#views].title=='AI translation' and views[#views].buttons[1][1].enabled==false and views[#views].buttons[1][3].text=='Phrase help','explicit AI options require setup and retain phrase help')
ai:settings();inputs={'https://context.example/v1','context-model','test-key-not-a-real-secret'};shown[#shown].buttons[1][2].callback()
local contextual
client.request=function(cfg,key,text,mode,focus)contextual={text=text,mode=mode,focus=focus};return {text='Meaning in context'}end
local before_context=runs
ai:showSentence('She gave up.','gave','context')
assert(runs==before_context,'context preview must not send')
views[#views].buttons[1][1].callback()
assert(contextual and contextual.mode=='context' and contextual.focus=='gave' and contextual.text=='She gave up.')
assert(views[#views].title=='Meaning in context')
ai:showSentence('She gave up.','gave','context');views[#views].buttons[1][1].callback()
assert(runs==before_context+1,'same word, context, provider and mode must reuse the cached response')
print('PASS: offline cache bypasses network; phrase and context are explicit AI-only actions; contextual identity cached separately')
for _,entry in pairs(cached_entries)do
 assert(entry.text~='Both providers failed.' and entry.text~='Cancellation check.','errors and cancelled requests must not be cached')
end
print('PASS: errors and cancelled requests do not enter offline history')

ai:settings();local existing=shown[#shown]
assert(existing.fields[1].text=='https://context.example/v1' and existing.fields[2].text=='context-model','existing custom providers must remain editable and unchanged')
inputs={'https://custom.example/v1','custom-model','draft-for-custom-provider'}
existing.buttons[2][1].callback();shown[#shown].buttons[1][1].callback()
assert(shown[#shown].fields[3].text=='','switching provider must clear an unsaved key for the previous provider')
print('PASS: OpenRouter defaults, free model picker, custom models, unsaved draft and provider key separation')

-- Emulate FAT32 permission failure without opening or writing any real key file.
local nativeffi=require('ffi');local nativeRename,nativeRemove=os.rename,os.remove
local settingsDir=package.loaded.datastorage.getSettingsDir
local written
package.loaded.ffi={os='Linux',cast=function(_,v)return v end,C={O_WRONLY=1,O_CREAT=64,
 open=function()return 20 end,fchmod=function()return -1 end,
 write=function(_,key,length)written=key;return length end,close=function()return 0 end,
}}
os.rename=function()return true end;os.remove=function()return true end
package.loaded.datastorage.getSettingsDir=function()return '/mnt/us/koreadercus/profile/settings' end
kindle=true
local fat=require('english_ai').new({},function()end)
fat:settings();local form=shown[#shown]
assert(form.fields[3].description:find('plaintext',1,true),'Kindle UI must disclose USB key storage')
inputs={'https://openrouter.ai/api/v1','google/gemma-4-26b-a4b-it:free','fake-fat32-test-key'}
form.buttons[1][2].callback()
assert(written=='fake-fat32-test-key','approved Kindle USB storage must allow saving when FAT32 cannot apply Unix modes')
kindle=false;written=nil
fat:settings();shown[#shown].buttons[1][2].callback()
assert(not written,'permission failure must remain fatal outside Kindle USB storage')
kindle=true;written=nil
package.loaded.datastorage.getSettingsDir=function()return '/private/tmp/kindle-key-boundary-test' end
local outside=require('english_ai').new({},function()end)
outside:settings();shown[#shown].buttons[1][2].callback()
assert(not written,'Kindle permission fallback must be restricted to /mnt/us USB storage')
package.loaded.ffi=nativeffi;os.rename=nativeRename;os.remove=nativeRemove
package.loaded.datastorage.getSettingsDir=settingsDir
print('PASS: approved Kindle USB key save; private permissions required elsewhere; fake I/O only')

-- Failed AI explanations may return a translation, never a fabricated analysis.
local translator=package.loaded['ui/translator']
local normalGoogle=translator.translate
local originalClient=client.request
local ai_attempts=0
client.request=function()ai_attempts=ai_attempts+1;return {error='Provider rate limit reached.'}end
for _,mode in ipairs({'translate','phrase','explain','context'}) do
 local text='Fallback sample for '..mode
 local google_before=#google
 ai:run(text,mode,{base_url='https://context.example/v1',host='context.example',model='context-model'},'fake-key',mode=='context' and 'sample' or nil)
 assert(#google==google_before+1 and google[#google].text==text,'fallback must translate exactly the requested text')
 assert(views[#views].title=='Translation' and views[#views].subtitle:find('Google Translate',1,true),'fallback must not impersonate an AI explanation')
 for _,entry in pairs(cached_entries) do
  if entry.text==text then
   assert(entry.mode=='translate' and entry.provider:find('Google Translate',1,true),'cache must retain actual source and action')
  end
 end
end
-- A failed AI attempt can reuse the Google cache without another Google request.
local google_before=#google
ai:run('Fallback sample for phrase','phrase',{base_url='https://context.example/v1',host='context.example',model='context-model'},'fake-key')
assert(#google==google_before and views[#views].subtitle:find('Offline saved',1,true),'Google fallback cache must be reusable')
-- Google fallback must never be cached under the AI identity.
client.request=function()return {text='Recovered AI explanation'}end
ai:run('Fallback sample for phrase','phrase',{base_url='https://context.example/v1',host='context.example',model='context-model'},'fake-key')
assert(views[#views].title=='Phrase help' and views[#views].text=='Recovered AI explanation','Google result must not suppress recovered AI analysis')
-- Exceptions and empty worker output also trigger fallback.
for _,failure in ipairs({'exception','empty'}) do
 client.request=function()if failure=='exception' then error('private transport detail')end end
 local count=#google
 ai:run('Worker failure '..failure,'translate',{base_url='https://context.example/v1',host='context.example',model='context-model'},'fake-key')
 assert(#google==count+1 and views[#views].title=='Translation' and not ai.busy)
end
client.request=function()return {error='Provider unavailable'}end
for _,failure in ipairs({'empty','exception'})do
 translator.translate=function()if failure=='exception' then error('private Google detail')end;return '   'end
 ai:run('Both providers failed.','explain',{base_url='https://context.example/v1',host='context.example',model='context-model'},'fake-key')
 assert(shown[#shown].text=='AI and Google translation failed. Check Wi-Fi and try again.' and not ai.busy)
end
translator.translate=normalGoogle
local count=#google
cancel=true
ai:run('Cancelled fallback.','translate',{base_url='https://context.example/v1',host='context.example',model='context-model'},'fake-key')
assert(#google==count and shown[#shown].text=='Request cancelled.','cancelled AI must never start fallback')
cancel=false
-- Cancellation of Google's worker must also close loading and leave history untouched.
local trapper=package.loaded['ui/trapper']
local normalWorker=trapper.dismissableRunInSubprocess
local workers=0
trapper.dismissableRunInSubprocess=function(self,fn,loading)
 workers=workers+1
 if workers==2 then cancel=true end
 return normalWorker(self,fn,loading)
end
ai:run('Cancelled Google worker.','explain',{base_url='https://context.example/v1',host='context.example',model='context-model'},'fake-key')
assert(workers==2 and #google==count and shown[#shown].text=='Request cancelled.' and not ai.busy)
cancel=false;trapper.dismissableRunInSubprocess=normalWorker
for _,entry in pairs(cached_entries)do assert(entry.text~='Both providers failed.' and entry.text~='Cancelled fallback.' and entry.text~='Cancelled Google worker.')end
for _,view in ipairs(views)do
 if view.title=='Translating…' or view.title=='Analysing sentence…' then assert(view.closed,'fallback loading must close')end
end
client.request=originalClient
print('PASS: Google fallback for all failed AI actions, correct cache ownership, recovery, exceptions, double failure and cancellation; no network')

-- A failed default Google request must not spend API credits automatically.
local attempts=0
client.request=function()attempts=attempts+1;return {text='Unexpected AI'}end
translator.translate=function()return nil end
ai:translateSelection('Google default failure never calls AI.')
assert(attempts==0 and shown[#shown].text:find('Translation failed',1,true) and not ai.busy)
translator.translate=normalGoogle
print('PASS: Google failure never calls AI automatically')

-- Tap word -> Sentence -> Paragraph: Google only, EN/VI pairs, switch both ways (cached on return).
local calls={}
translator.translate=function(_,text)calls[#calls+1]=text;return (text:gsub('[^\n]+',function(l)return 'VI('..l..')' end))end
local context={sentence='Every path looked unfamiliar.',paragraph='He stopped.\nEvery path looked unfamiliar.\nNight came.'}
attempts=0
ai:translateContext(context,'unfamiliar')
local sentenceView=views[#views]
assert(attempts==0 and calls[#calls]==context.sentence,'Sentence uses Google, never AI')
assert(sentenceView.text=='Every path looked unfamiliar.\n\nVI(Every path looked unfamiliar.)')
local function button(view,label)for _,row in ipairs(view.buttons)do for _,b in ipairs(row)do if b.text==label then return b end end end end
assert(button(sentenceView,'Sentence').font_bold and not button(sentenceView,'Paragraph').font_bold)
assert(button(sentenceView,'Use AI'),'AI stays one explicit tap away')
button(sentenceView,'Paragraph').callback()
local paragraphView=views[#views]
assert(sentenceView.closed and calls[#calls]==context.paragraph,'Paragraph translates the whole paragraph in one request')
assert(paragraphView.text=='He stopped.\nVI(He stopped.)\n\nEvery path looked unfamiliar.\nVI(Every path looked unfamiliar.)\n\nNight came.\nVI(Night came.)','paragraph shows sentence pairs')
assert(paragraphView.speech_text=='He stopped. Every path looked unfamiliar. Night came.')
assert(button(paragraphView,'Paragraph').font_bold)
local before=#calls
button(paragraphView,'Sentence').callback()
assert(#calls==before and views[#views].text==sentenceView.text,'switching back reuses the saved translation')
assert(button(views[#views],'Paragraph'),'the switch survives a cached result')
translator.translate=function(_,text)return 'Một đoạn gộp.' end
ai:translateContext({sentence='A.',paragraph='A.\nB.',current='paragraph'},'a')
assert(views[#views].text=='A. B.\n\nMột đoạn gộp.','mismatched lines fall back to two blocks')
ai:translateContext({sentence='Only one sentence.'},'one')
assert(not button(views[#views],'Paragraph'),'no Paragraph switch when the paragraph is one sentence')
translator.translate=normalGoogle
print('PASS: Sentence/Paragraph without dragging: Google only, EN/VI pairs, cached switch-back, safe fallback')
