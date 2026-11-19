-- Opt-in instrumentation for disposable performance profiles only.
io.stdout:setvbuf('line')
local UIManager=require('ui/uimanager')
local ReaderUI=require('apps/reader/readerui')
local time=require('ui/time')
local json=require('json')
local Trapper=require('ui/trapper')
local function timed(fn)
    local start=time.now()
    local value=fn()
    return time.to_ms(time.now()-start),value
end
local original=ReaderUI.init
function ReaderUI:init()
    original(self)
    print('PERF_READY')
    UIManager:scheduleIn(0.1,function()
        Trapper:wrap(function()
            local metrics={lookups={},popups={},page_turns={},scroll_errors={}}
            local ok,err=pcall(function()
                metrics.page_count=self.document:getPageCount()
                local dict=self.dictionary
                if not os.getenv("PERF_PAGING_ONLY") then
                local result_cache={}
                for round=1,5 do
                    for _,word in ipairs({'noon','reluctantly','unfamiliar','threshold','qzxqzxmissing'}) do
                        local raw_ms,raw=timed(function() local _,r=dict:rawSdcv({word},dict.enabled_dict_names,false);return r end)
                        local total_ms,results=timed(function() return dict:startSdcv(word,dict.enabled_dict_names,false) end)
                        metrics.lookups[#metrics.lookups+1]={word=word,round=round,raw_ms=raw_ms,processed_ms=total_ms}
                        result_cache[word]=results
                    end
                end
                for i=1,12 do
                    local word=i%2==0 and 'noon' or 'reluctantly'
                    local create_ms=timed(function() dict:showDict(word,result_cache[word]) end)
                    local paint_ms=timed(function() UIManager:forceRePaint() end)
                    local popup=UIManager._window_stack[#UIManager._window_stack].widget
                    if popup.name=='english_small_lookup' and #metrics.scroll_errors==0 then
                        local definition=popup[1][1][1][2][1][1]
                        if definition.scrollText then
                            local scroll_ok,scroll_err=pcall(function() definition:scrollText(1) end)
                            if not scroll_ok then metrics.scroll_errors[#metrics.scroll_errors+1]=tostring(scroll_err) end
                        end
                    end
                    metrics.popups[#metrics.popups+1]={word=word,create_ms=create_ms,paint_ms=paint_ms}
                    if popup.onClose then popup:onClose() else UIManager:close(popup) end
                    UIManager:forceRePaint()
                end
                end
                for i=1,10 do
                    local page_before=self.document:getCurrentPage()
                    local turn_ms=timed(function()
                        self.rolling:onGotoViewRel(i%2==1 and 1 or -1)
                        UIManager:forceRePaint()
                    end)
                    metrics.page_turns[#metrics.page_turns+1]={ms=turn_ms,before=page_before,after=self.document:getCurrentPage()}
                end
                collectgarbage('collect')
                metrics.lua_heap_kb=collectgarbage('count')
            end)
            if not ok then metrics.error=tostring(err) end
            print('PERF_RESULT '..json.encode(metrics))
            UIManager:quit(0)
        end)
    end)
end
