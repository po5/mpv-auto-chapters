-- autochapters
-- https://github.com/po5/mpv-auto-chapters
--
-- Automatically finds chapters for your anime files
-- using a local anime database to identify media,
-- and the Aniskip API for community-submitted times

local opts = require "mp.options"
local utils = require "mp.utils"
local msg = require "mp.msg"
local input = require "mp.input"

local options = {
    create_chapters = true,
    on_file_load = true,
    search_only_when_chapters_missing = true,
    allow_loose_matches = true,
    keep_previous_chapters = false,
    pause_on_search = true,
    hook = false
}

local script_name, script_dir = mp.get_script_name(), mp.get_script_directory()
opts.read_options(options, script_name, function() end)

local types = {
    op = "Opening",
    ed = "Ending",
    ["mixed-op"] = "Mixed Opening",
    ["mixed-ed"] = "Mixed Ending",
    recap = "Recap"
}

local api_url = "https://api.aniskip.com/v2"
local db_url = "https://github.com/manami-project/anime-offline-database/raw/master/anime-offline-database-minified.json"
local relations_url = "https://github.com/erengy/anime-relations/raw/master/anime-relations.txt"
local placeholder_title = ""

local anime, relations, borked
local json_path = utils.join_path(script_dir, "anime.json")
local relations_path = utils.join_path(script_dir, "relations.json")

local function log(message)
    mp.osd_message(message)
    msg.error(message)
end

local function guess(path, auto)
    if not path or path == "" then
        return nil, nil
    end

    local guessit = mp.command_native({name = "subprocess", playback_only = false, capture_stdout = true, args = {"guessit", "-jE", "--", path}})
    if not guessit or not guessit.stdout then
        return nil, nil
    end

    local data = utils.parse_json(guessit.stdout)
    if type(data) ~= "table" then
        log("autochapters: couldn't parse media filename, is guessit installed?")
        return nil, nil
    end

    if auto then
        data.input = path
        mp.set_property_native("user-data/guessit", data)
    end

    if not data.title then
        return nil, nil
    end

    if type(data.title) == "table" then
        data.title = data.title[1]
    end

    if type(data.episode) == "table" then
        data.episode = data.episode[1]
    end

    return data.title, data.episode
end

local function time_sort(a, b)
    if a.time == b.time then
        return not a.title
    end
    return a.time < b.time
end

local function extract_mal_id(url)
    local prefix = "https://myanimelist.net/anime/"
    if url:find(prefix) == 1 then
        return url:sub(31) -- #prefix + 1
    end
    return nil
end

local function update_db()
    local anime_relations = mp.command_native({name = "subprocess", playback_only = false, capture_stdout = true, args = {"curl", "-s", "-L", relations_url}})
    if not anime_relations or not anime_relations.stdout then
        return
    end

    relations = {}

    local rules = anime_relations.stdout:match("::rules(.+)")
    if anime_relations.stdout == "" or rules == "" then
        log("autochapters: couldn't download anime-relations database, is curl installed?")
        return
    end

    local in_title, out_title, number_title, number_index = "", "", false, 0
    for rule in rules:gmatch("[^\r\n]+") do
        local in_mal_id, in_ep_start, in_ep_end, out_mal_id, out_ep_start, out_ep_end, self_redirect = string.match(rule, "^%- ([0-9]+)|[0-9?]+|[0-9?]+:([0-9]+)%-?([0-9?]*) %-> ([0-9~]+)|[0-9?~]+|[0-9?~]+:([0-9]+)%-?([0-9?]*)(!?)")
        if in_mal_id then
            local out_mal_id_string = out_mal_id
            in_ep_start, in_ep_end, out_ep_start, self_redirect = tonumber(in_ep_start), tonumber(in_ep_end), tonumber(out_ep_start), self_redirect
            if not relations[in_mal_id] then
                relations[in_mal_id] = {}
            end
            if out_mal_id == "~" then
                out_mal_id = tonumber(in_mal_id)
            else
                out_mal_id = tonumber(out_mal_id)
            end
            local title = out_title
            if number_title then
                number_index = number_index + 1
                local number_list = string.match(title, "~? ?(.+)")
                local numbers = {}
                for num in number_list:gmatch("([^,]+)") do
                    numbers[#numbers + 1] = num
                end
                local number = numbers[number_index]
                if number then
                    local new_title, count = string.gsub(in_title, "%%d", number)
                    title = new_title
                    if count == 0 then
                        title = in_title .. " " .. number
                    end
                end
            end
            title = string.gsub(title, "~", in_title)
            table.insert(relations[in_mal_id], {a=in_ep_start, b=in_ep_end, x=out_ep_start, z=out_mal_id, t=title})
            if self_redirect == "!" then
                if not relations[out_mal_id_string] then
                    relations[out_mal_id_string] = {}
                end
                table.insert(relations[out_mal_id_string], {a=in_ep_start, b=in_ep_end, x=out_ep_start, z=out_mal_id, t=title})
            end
        else
            local _in_title, _out_title = string.match(rule, "^# (.+) %-> (.*)")
            if _in_title then
                number_title = false
                number_index = 0
                in_title, out_title = _in_title, _out_title
                if string.find(out_title, ",[0-9]") or string.find(out_title, "[0-9],") then
                    number_title = true
                    in_title = string.gsub(in_title, "S?%d", "%%d")
                end
            end
        end
    end

    json = utils.format_json(relations)
    local f = io.open(relations_path, "w")
    if f then
        f:write(json)
        f:close()
    end

    local manami = mp.command_native({name = "subprocess", playback_only = false, capture_stdout = true, args = {"curl", "-s", "-L", db_url}})
    if not manami or not manami.stdout then
        return
    end

    local json = utils.parse_json(manami.stdout)
    if type(json) ~= "table" then
        log("autochapters: couldn't download manami database, is curl installed?")
        return
    end

    local result = {}

    for _, item in ipairs(json.data) do
        local mal_id = nil
        for _, source in ipairs(item.sources) do
            mal_id = extract_mal_id(source)
            if mal_id then
                break
            end
        end

        mal_id = tonumber(mal_id)

        if mal_id then
            result[item.title:lower():gsub("%s+", "")] = mal_id
            for _, synonym in ipairs(item.synonyms) do
                result[synonym:lower():gsub("%s+", "")] = mal_id
            end
        end
    end

    anime = result
    json = utils.format_json(result)
    local f = io.open(json_path, "w")
    if f then
        f:write(json)
        f:close()
    end
end

local function resolve_relations(mal_id, episode)
    if not relations[mal_id] then
        return mal_id, episode
    end
    local ep = episode or 0
    for _, r in ipairs(relations[mal_id]) do
        if ep >= r.a and ep <= (r.b or math.huge) then
            local offset = r.a - r.x
            return r.z, ep - offset, r.t
        end
    end
    return mal_id, episode
end

local function read_json(path)
    local f = io.open(path, "r")
    if f then
        local json = f:read("*all")
        f:close()

        data = utils.parse_json(json or "")
        if data and type(data) == "table" then
            return data
        end
    end
end

local function api_lookup(title, episode, duration, auto)
    if borked then return end

    if anime == nil or relations == nil then
        anime = read_json(json_path)
        relations = read_json(relations_path)
        if anime == nil or relations == nil then
            update_db()
        end
    end

    if anime == nil or relations == nil then
        borked = true
        return
    end

    local mal_id = anime[title:lower():gsub("%s+", "")]
    if not mal_id then return end

    local relation_title
    local in_episode = episode
    mal_id = tostring(mal_id)
    mal_id, episode, relation_title = resolve_relations(mal_id, episode)

    local display_episode = relation_title and episode or in_episode

    if not auto then
        mp.osd_message("Searching for " .. (relation_title or title) .. (display_episode and (" Episode " .. display_episode) or "") .. "...")
    end

    local url = api_url .. "/skip-times/" .. mal_id .. "/" .. (episode or 1) .. "?types[]=op&types[]=ed&types[]=mixed-op&types[]=mixed-ed&types[]=recap&episodeLength=" .. duration
    local aniskip = mp.command_native({name = "subprocess", playback_only = false, capture_stdout = true, args = {"curl", "-s", url}})
    if not aniskip or not aniskip.stdout then
        return
    end

    local data = utils.parse_json(aniskip.stdout)
    if type(data) ~= "table" then
        log("autochapters: couldn't download aniskip chapters, is curl installed?")
        return
    end

    if data.error then
        log("autochapters: got an error " .. data.statusCode .. " from aniskip " .. utils.format_json(data.message))
        return
    end

    if not data.found or not data.results then
        return
    end

    local chapters = options.keep_previous_chapters and mp.get_property_native("chapter-list") or {}
    local chapter_count = #chapters
    local times = {}

    for _, skip in ipairs(data.results) do
        times[skip.skipType] = {}
        if skip.interval.startTime then
            table.insert(chapters, {title=types[skip.skipType], time=skip.interval.startTime})
            times[skip.skipType]["start"] = skip.interval.startTime
        end
        if skip.interval.endTime then
            table.insert(chapters, {title=nil, time=skip.interval.endTime})
            times[skip.skipType]["end"] = skip.interval.endTime
        end
    end

    if options.create_chapters and (not options.search_only_when_chapters_missing or chapter_count == 0) then
        table.sort(chapters, time_sort)
        mp.set_property_native("chapter-list", chapters)
    end

    mp.set_property_native("user-data/autochapters", times)

    return true
end

local function find_chapters(media_title, auto)
    local title, episode = guess(media_title, auto)
    if not title then return end

    local duration = mp.get_property_number("duration", 0)

    local found = api_lookup(title, episode, duration, auto)
    if not found and options.allow_loose_matches then
        found = api_lookup(title, episode, 0, auto)
    end

    if not found then
        mp.set_property_native("user-data/autochapters", {})
    end
    return found, title, episode
end

local function file_load()
    placeholder_title = mp.get_property("filename/no-ext")
    if not options.on_file_load then return end

    local path = mp.get_property("path")
    find_chapters(path, true)
end

local function search()
    local pause_and_restore = options.pause_on_search and mp.get_property_bool("pause") == false

    input.get({
        prompt = "Media title to search for:",
        submit = function (media_title)
            placeholder_title = media_title
            if media_title ~= "" then
                mp.add_timeout(0.05, function()
                    local found, title, episode = find_chapters(media_title)
                    if not found then
                        mp.osd_message("No chapters found for " .. (title and (title .. (episode and (" Episode " .. episode) or "")) or media_title))
                    end
                end)
            else
                mp.set_property_native("chapter-list", {})
            end
            input.terminate()
        end,
        closed = function (media_title)
            if pause_and_restore then
                mp.set_property_bool("pause", false)
            end
        end,
        default_text = placeholder_title,
        cursor_position = #placeholder_title + 1
    })

    if pause_and_restore then
        mp.set_property_bool("pause", true)
    end
end

mp.add_key_binding(nil, "search", search)
mp.add_key_binding(nil, "update", update_db)

if options.hook then
    mp.add_hook("on_preloaded", 50, file_load)
else
    mp.register_event("file-loaded", file_load)
end
