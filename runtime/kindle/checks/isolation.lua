local root=assert(arg[1])
local profile='/mnt/us/koreadercus/profile'
local function inside(path)
 assert(path:sub(1,#profile+1)==profile..'/', 'Access outside custom profile: '..path)
end
local settings={extend=function(self,t)return setmetatable(t,{__index=self})end,
 backup=function(_,path)inside(path)end}
local fs={attributes=function(path)inside(path);return nil end}
package.loaded['datastorage']={
 getHistoryDir=function()return profile..'/history'end,
 getDocSettingsDir=function()return profile..'/docsettings'end,
 getDocSettingsHashDir=function()return profile..'/hashdocsettings'end,
 getDataDir=function()return profile end,
}
package.loaded['luasettings']=settings
package.loaded['dump']=function()return 'return {}'end
package.loaded['ffi/util']={basename=function(path)return path:match('[^/]+$')end}
package.loaded['libs/libkoreader-lfs']=fs
package.loaded['logger']={dbg=function()end}
package.loaded['util']={makePath=inside,writeToFile=function(_,path)inside(path);return true end}
G_reader_settings={readSetting=function(_,name,default)return default end}
local Doc=dofile(root..'/frontend/docsettings.lua')
local book='/mnt/us/documents/Book.epub'
for _,location in ipairs({'doc','dir','hash'}) do
 assert(Doc:getSidecarDir(book,location)==profile..'/docsettings/mnt/us/documents/Book.sdr')
end
assert(Doc:getSidecarDir(nil)=='')
local document=Doc:open(book)
assert(document:flush(nil,true)==profile..'/docsettings/mnt/us/documents/Book.sdr')
for _,path in ipairs(Doc:getCustomLocationCandidates(book)) do inside(path)end
-- Load the actual OTA module; all public update entry points must be disabled.
for _,name in ipairs({'ui/bidi','ui/widget/confirmbox','device','ui/widget/infomessage',
 'ui/widget/multiconfirmbox','ui/network/manager','ui/widget/progressbardialog',
 'ui/uimanager','ui/trapper','version'}) do package.loaded[name]={} end
package.loaded['gettext']=setmetatable({pgettext=function(_,t)return t end},{__call=function(_,t)return t end})
package.loaded['ui/widget/infomessage'].new=function(_,t)return t end
local message
package.loaded['ui/uimanager'].show=function(_,v)message=v.text end
local OTA=dofile(root..'/frontend/ui/otamanager.lua')
assert(OTA:getOTAType()=='none' and OTA:checkUpdate()==nil)
assert(OTA:getOTAMenuTable().enabled==false)
OTA:fetchAndProcessUpdate()
assert(message=='Update KOReaderCus from your computer.')
print('PASS: actual document open/flush stays in custom profile; native OTA disabled')
