-- Exercise the actual SimpleUI root builder with its native row constructors stubbed.
local path=assert(arg[1]);local f=assert(io.open(path));local source=f:read('*a');f:close()
local start=assert(source:find('    local function buildRoot(ctx)',1,true))
local finish=assert(source:find('\n    -- Stats menu screen.',start,true))
local snippet=source:sub(start,finish-1)
local closed,opened=false,0
local english={onShowEnglishAISettings=function()assert(closed);opened=opened+1 end}
local plugin={ui={englishpreview=english}}
local env=setmetatable({st={},SUI={ListRow=function(t)return t end},_ =function(t)return t end,getPlugin=function()return plugin end},{__index=_G})
local fn=assert(loadstring(snippet..'\nreturn buildRoot'));setfenv(fn,env)
local build=fn()
local ctx={inner_w=550,close=function()closed=true end}
local found
for _,row in ipairs(build(ctx))do if row.title=='AI settings' then found=row end end
assert(found and found.subtitle=='Provider, model and API key','Settings tab must include AI configuration')
found.on_tap();assert(opened==1,'row must close settings and open the existing AI form')
plugin.ui.englishpreview=nil
for _,row in ipairs(build(ctx))do assert(row.title~='AI settings','disabled English plugin must not leave a dead settings row')end
print('PASS: SimpleUI Settings row opens shared AI form and disappears when unavailable')
