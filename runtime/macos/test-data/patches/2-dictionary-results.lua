-- Local development overlay from fork commit 44da9a6; official native bundle stays intact.
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local Utf8Proc = require("ffi/utf8proc")
local util = require("util")
local logger = require("logger")
local _ = require("gettext")
function ReaderDictionary:startSdcv(word, dict_names, fuzzy_search)
    local words = {word}
    -- If a word starts with a capital letter, add lowercase version to words array.
    if not fuzzy_search then
        local lowercased = Utf8Proc.lowercase(word, false)
        if word ~= lowercased then
            table.insert(words, lowercased)
        end
    end

    if self.ui.languagesupport and self.ui.languagesupport:hasActiveLanguagePlugins() then
        -- Get any other candidates from any language-specific plugins we have.
        -- We prefer the originally selected word first (in case there is a
        -- dictionary entry for whatever text the user selected).
        local candidates = self.ui.languagesupport:extraDictionaryFormCandidates(word)
        if candidates then
            util.arrayAppend(words, candidates)
        end
    end

    -- If every word contains a CJK character, every word candidate is
    -- (probably) a CJK word. We don't want fuzzy searching in this case
    -- because sdcv cannot handle CJK text properly when fuzzy searching (with
    -- Japanese, it returns hundreds of useless results).
    local shouldnt_fuzzy_search = true
    for _, w in ipairs(words) do
        if not util.hasCJKChar(w) then
            shouldnt_fuzzy_search = false
            break
        end
    end
    if shouldnt_fuzzy_search then
        logger.dbg("disabling fuzzy searching for all-CJK word search:", words)
        fuzzy_search = false
    end

    local lookup_cancelled, results = self:rawSdcv(words, dict_names, fuzzy_search, self.lookup_progress_msg or false)
    if results == nil then -- no dictionaries found
        return {
            {
                dict = "",
                word = word,
                definition = _([[No dictionaries installed. Please search for "Dictionary support" in the KOReader Wiki to get more information about installing new dictionaries.]]),
            }
        }
    else -- flatten any possible results
        local flat_results = {}
        local seen_results = {}
        -- Flatten the array, removing any duplicates we may have gotten (sdcv
        -- may do multiple queries, in fixed mode then in fuzzy mode, and the
        -- language-specific plugin may have also returned multiple equivalent
        -- results).
        for _, term_results in ipairs(results) do
            for _, r in ipairs(term_results) do
                -- Key each field separately: concatenating copies the entire
                -- definition and can collide across field boundaries.
                local dict_results = seen_results[r.dict]
                if not dict_results then
                    dict_results = {}
                    seen_results[r.dict] = dict_results
                end
                local word_results = dict_results[r.word]
                if not word_results then
                    word_results = {}
                    dict_results[r.word] = word_results
                end
                if not word_results[r.definition] then
                    table.insert(flat_results, r)
                    word_results[r.definition] = true
                end
            end
        end
        results = flat_results
    end
    if #results == 0 then -- no results found
        -- dummy results
        results = {
            {
                dict = _("Not available"),
                word = word,
                definition = lookup_cancelled and _("Dictionary lookup interrupted.") or _("No results."),
                no_result = true,
                lookup_cancelled = lookup_cancelled,
            }
        }
    end
    if lookup_cancelled then
        -- Also put this as a k/v into the results array: when using dict_ext,
        -- we may get results from the 1st lookup, and have interrupted the 2nd.
        results.lookup_cancelled = true
    end
    return results
end

logger.info("Workspace dictionary result optimization loaded")
