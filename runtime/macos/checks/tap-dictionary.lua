local handlers, specs, tapped, fallback = {}, {}, nil, 0
local dictionary={addToDictButtons=function(_,spec) specs[spec.id]=spec end,showDict=function() fallback=fallback+1 end}
local releases,clears,translations=0,0,{}
local highlight={
    onHoldRelease=function() releases=releases+1;return 'native release' end,
    clear=function(self) clears=clears+1;self.hold_pos=nil;self.selected_text=nil end,
    view={highlight={visible_boxes={}},screenToPageTransform=function(_,p)return p end},
    onTap=function(_,_,ges) return ges.handled end,
    onHold=function(self) self.selected_text={text='reluctantly'};return true end,
    _resetHoldTimer=function()end,
    lookupDictWord=function(self) tapped=self.selected_text.text end,
}
local ui={menu={registerToMainMenu=function()end},dictionary=dictionary,highlight=highlight,
    rolling=true,document={getWordFromPosition=function(_,p)
        if p.x==300 then return {word='reluctantly',sbox={x=280,y=200,w=100,h=40}} end
    end},
}
package.preload['ui/widget/container/widgetcontainer']=function()return {extend=function(_,t)return t end}end
package.preload['ui/uimanager']=function()return {}end
package.preload['ui/widget/textviewer']=function()return {}end
package.preload['ui/widget/dictquicklookup']=function()return {buildButtonLayout=function()return {}end}end
package.preload['device']=function()return {screen={getWidth=function()return 600 end,getHeight=function()return 800 end}}end
local Preview=assert(loadfile(arg[1]))()
local plugin=setmetatable({ui=ui},{__index=Preview})
plugin.showSmallPopup=function(_,word,options)tapped=word;handlers.options=options end
plugin:init()
assert(highlight:onTap(nil,{pos={x=300,y=220}})==true and tapped=='reluctantly','text tap must lookup')
tapped=nil
assert(highlight:onTap(nil,{handled=true,pos={x=300,y=220}})==true and not tapped,'existing highlights take priority')
assert(not highlight:onTap(nil,{pos={x=10,y=220}}) and not tapped,'edge taps must fall through')
assert(not highlight:onTap(nil,{pos={x=200,y=300}}) and not tapped,'whitespace must fall through')
assert(not highlight:onTap(nil,{pos={x=300,y=350}}) and not tapped,'nearest word outside its box must not lookup')
ui.rolling=false
assert(not highlight:onTap(nil,{pos={x=300,y=220}}) and not tapped,'PDF retains native gestures')
ui.rolling=true
local results={{word='reluctantly',dict='Sample English-Vietnamese',definition='actual'}}
dictionary:showDict('reluctantly',results)
assert(tapped=='reluctantly' and handlers.options.results==results,'real lookup results feed compact popup')
handlers.options.on_more()
assert(fallback==1,'More opens native complete result')
dictionary:showDict('noon',{{no_result=true}})
assert(fallback==1 and tapped=='noon' and handlers.options.results[1].no_result,'missing words must use compact popup too')
dictionary.is_wiki=true
dictionary:showDict('x',{{no_result=true}})
assert(fallback==2,'Wikipedia must retain native handling')
print('PASS: real word tap, existing highlights, edge/whitespace/PDF fallthrough, compact lookup and More')

plugin.getAI=function()return {translateSelection=function(_,text)
    assert(not highlight.selected_text and not highlight.hold_pos,'selection must clear before Wi-Fi prompt')
    translations[#translations+1]=text
end}end
local function select(text,word)
    highlight.selected_text={text=text};highlight.hold_pos={page=1};highlight.is_word_selection=word
end
select('By noon, the road had narrowed.',false)
assert(highlight:onHoldRelease()==true and translations[1]=='By noon, the road had narrowed.',
    'multiword drag must immediately translate exactly the selection')
assert(clears==1 and releases==0,'auto translation must bypass the native highlight menu')
highlight:onHoldRelease()
assert(#translations==1,'repeated release must not translate twice')
for _,text in ipairs({"don't",'reluctantly  ','word ,','   '}) do
    select(text,false);local before=releases
    assert(highlight:onHoldRelease()=='native release' and releases==before+1,'single words and punctuation retain native handling')
end
select('two words',true)
assert(highlight:onHoldRelease()=='native release','native single-word selection remains dictionary-owned')
select('two words',false);highlight.select_mode=true
assert(highlight:onHoldRelease()=='native release','extended selection mode must stay native')
highlight.select_mode=false;highlight.clear_id=1
assert(highlight:onHoldRelease()=='native release','pending delayed clear must not send')
highlight.clear_id=nil
select('two\nwords',false)
assert(highlight:onHoldRelease()==true and translations[2]=='two\nwords','line-spanning selection translates')
print('PASS: drag/release translates exact multiword text once; single words and native selection modes preserved')
