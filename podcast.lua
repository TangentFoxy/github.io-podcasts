#!/usr/bin/env luajit

local help = [[Usage:

  to be written

Requirements:
- ffprobe (part of ffmpeg)
- mp3tag (optional, for episode artwork)
]]

local utility = require("utility")

local function load_database()
  local json = require("json")
  local database
  utility.open("episodes.json", "r", function(file)
    database = json.decode(file:read("*all"))
  end)
  return database
end

local function save_database(database)
  local json = require("json")
  utility.open("episodes.json", "w", function(file)
    file:write(json.encode(database))
  end)
end

-- local function add_episode(title)
-- end

-- starts adding a new episode to the database
--   some functions require manual intervention, which is why this STARTS the process
local function new_episode(episode_title, file_name)
  -- needed: episode_title, episode_summary
  -- should already exist: MP3 file named (file_name).mp3 OR (episode_title).mp3, (optional) square JPG image with the same name scheme
  -- will generate: urlencoded_title, duration_seconds, episode_number, publish date, file_size

  -- ffprobe -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "FILEPATH"
  -- mp3tag open specific file: Mp3tag.exe /fn:"<full-qualified file name>"
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

local arguments = argparse(arg, {})
for k,v in pairs(arg) do
  print(k,v)
end

-- local date = require("date")
-- print(date():fmt("%a, %d %b %Y %H:%M MST")) -- Wed, 27 Nov 2024 00:00 MST
print(os.date("%a, %d %b %Y %H:%M MST", os.time()))
