-- Check the actual installed cache wrapper preserves KOReader's readability result.
local file = assert(io.open(arg[1], 'r'))
local source = file:read('*a'); file:close()
local start = assert(source:find('    FileChooser.genItemTableFromPath = function(fc, path)', 1, true))
local finish = assert(source:find('\n    end\nend\n', start, true))
local wrapper = source:sub(start, finish + #'\n    end')
local prelude = [[
local _itc
local _itc_key = function(path) return path end
local G_reader_settings = { readSetting = function() return 'strcoll' end }
local calls = 0
local _orig_genItemTableFromPath = function(_, path)
    calls = calls + 1
    return {path}, path ~= '/unreadable'
end
local FileChooser = {}
]]
local checks = [[
local fc = { name = 'filemanager' }
for _, path in ipairs({'/readable', '/unreadable'}) do
    for attempt = 1, 2 do
        local items, readable = FileChooser.genItemTableFromPath(fc, path)
        assert(items[1] == path)
        assert(readable == (path ~= '/unreadable'), 'readability lost on attempt ' .. attempt)
    end
end
assert(calls == 2, 'cache should avoid repeat listing')
local _, readable = FileChooser.genItemTableFromPath({name='other'}, '/readable')
assert(readable == true, 'bypass must preserve readability')
print('PASS: readable/unreadable cold and cached results; bypass')
]]
assert(loadstring(prelude .. wrapper .. checks))()
