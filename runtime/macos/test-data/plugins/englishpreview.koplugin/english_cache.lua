-- Local, bounded result history. Never stores credentials or makes requests.
local M={}
function M.new()
 local SQL=require('lua-ljsqlite3/init')
 local path=require('datastorage'):getSettingsDir()..'/english-translations.sqlite3'
 local function connection(fn)
  local conn=SQL.open(path)
  local ok,result=pcall(fn,conn);conn:close()
  if not ok then error(result) end
  return result
 end
 connection(function(conn)conn:exec([[CREATE TABLE IF NOT EXISTS results (
  id INTEGER PRIMARY KEY AUTOINCREMENT, cache_key TEXT NOT NULL UNIQUE,
  text TEXT NOT NULL, mode TEXT NOT NULL, focus TEXT NOT NULL,
  provider TEXT NOT NULL, result TEXT NOT NULL
 );]])end)
 local self={}
 local function entry(row)
  if not row then return end
  return {key=row[1],text=row[2],mode=row[3],focus=row[4],provider=row[5],result=row[6]}
 end
 function self:get(key)
  return connection(function(conn)
   local stmt=conn:prepare('SELECT cache_key,text,mode,focus,provider,result FROM results WHERE cache_key=?;')
   stmt:bind(key);local result=entry(stmt:step());stmt:close();return result
  end)
 end
 function self:put(key,value)
  assert(type(value.result)=='string' and value.result:find('%S'))
  -- At most 100 passages, each at most 16 KB input and 64 KB output.
  if #value.text>16000 or #value.result>65536 then return end
  connection(function(conn)
   local stmt=conn:prepare('INSERT OR REPLACE INTO results (cache_key,text,mode,focus,provider,result) VALUES (?,?,?,?,?,?);')
   stmt:bind(key,value.text,value.mode,value.focus or '',value.provider,value.result)
   stmt:step();stmt:close()
   conn:exec('DELETE FROM results WHERE id NOT IN (SELECT id FROM results ORDER BY id DESC LIMIT 100);')
  end)
 end
 function self:list()
  return connection(function(conn)
   local stmt=conn:prepare('SELECT cache_key,text,mode,focus,provider,result FROM results ORDER BY id DESC LIMIT 100;')
   local result={}
   while true do local row=stmt:step();if not row then break end;result[#result+1]=entry(row) end
   stmt:close();return result
  end)
 end
 function self:clear()
  connection(function(conn)conn:exec('DELETE FROM results; VACUUM;')end)
 end
 return self
end
return M
