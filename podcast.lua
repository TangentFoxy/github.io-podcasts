#!/usr/bin/env luajit

local help = [[Usage:

  to be written

Requirements:
- ffprobe (part of ffmpeg)
- mp3tag (optional, for episode artwork)
]]

local feed_template = [[
  <?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"  xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title><%= podcast_title %></title>
    <language><%= podcast_language %></language>
    <% for _, episode in ipairs(episodes) do %>
      TODO
    <% end %>
  </channel>
  </rss>
]]

local episode_page_template = [[
  <html>
  <head>
  <title><%= podcast_title .. " - " .. episode_title %></title>
  <style>
    h1 { text-align: center; }
    audio { display: block; }
    audio, div { margin: auto; }
    div, img { width: 512px; }
  </style>
  </head>
  <body>
  <div>
    <p><a href="/">homepage</a></p>
    <h1><%= episode_title %></h1>
    <br />
    <img src="/<%= urlencoded_title %>.jpg" />
    <audio controls src="/<%= urlencoded_title %>.mp3"></audio>
    <% if escaped_summary then %>
      <%- escaped_summary %>
    <% else %>
      <%= episode_summary %>
    <% end %>
  </div>
  </body>
  </html>
]]

-- local etlua = require("etlua")
-- local page = etlua.compile(episode_page_template)({
--   podcast_title = "",
--   episode_title = "",
--   urlencoded_title = "",
--   escaped_summary = "",
--   episode_summary = "",
-- })



local utility = require("utility")

local function load_database()
  local json = require("json")
  local database
  utility.open("configuration.json", "r", function(file)
    database = json.decode(file:read("*all"))
  end)
  return database
end

local function save_database(database)
  local json = require("json")
  utility.open("configuration.json", "w", function(file)
    file:write(json.encode(database))
  end)
end

-- local function add_episode(title)
-- end

-- starts adding a new episode to the database
--   some functions require manual intervention, which is why this STARTS the process
--   MP3 file and JPG file should already exist in the local directory when you run this!
local function new_episode(episode_title, file_name, skip_mp3tag) -- skip_description option?
  local database = load_database()
  local urlencode = require("urlencode")

  local episode = {
    title = episode_title,
    file_name = file_name or episode_title,
    urlencoded_title = urlencode(episode_title),
    guid = utility.uuid(),
  }
  local duration_seconds = utility.capture_execute("ffprobe -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 " .. (episode.file_name .. ".mp3"):enquote())
  episode.duration_seconds = math.floor(tonumber(duration_seconds))

  print("Opening notepad to write episode summary!")
  os.execute("echo 0>> new_episode.description 1> NULL")
  os.execute("notepad new_episode.description") -- this is blocking
  utility.open("new_episode.description", "r", function(file)
    episode.summary = file:read("*all")
  end)

  if not skip_mp3tag then
    print("Opening mp3tag to add episode artwork.\n  (This step must be completed manually, and then podcast.lua must be called again to finish this episode!)")
    os.execute("mp3tag /fn:" .. (episode.file_name .. ".mp3"):enquote())
  end

  -- return episode
  database.episodes[episode_title] = episode
  save_database(database)
  -- TODO a list of titles will be used for identifying which episode we're on and what was published in what order

  -- NOTE I want to allow truncated summaries
  -- defer to finishing/publishing: publish_datetime, file_size, episode_number
end

local function argparse(arguments, positional_arguments)
  local recognized_arguments = {}
  for index, argument in ipairs(arguments) do
    for _, help_command in ipairs({"-h", "--help", "/?", "/help", "help"}) do
      if argument == help_command then
        print(help)
        return nil
      end
    end
    if positional_arguments[index] then
      recognized_arguments[positional_arguments[index]] = argument
    end
  end
  return recognized_arguments
end

local function main(arguments)
  local actions = {
    new = new_episode,
  }
  return actions[arguments.action](arguments.title, arguments.file_name)
end

local arguments = argparse(arg, {"action", "title", "file_name"})
if not arguments then return end
main(arguments)

-- local timezone_offset = -7 * 60 * 60 -- for me this is the correct value
-- print(os.date("%a, %d %b %Y %H:%M:%S GMT", os.time() + timezone_offset))
