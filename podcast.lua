#!/usr/bin/env luajit

local help = [[Usage:

  podcast.lua <action> <title> [options]

Requirements:
- ffprobe (part of ffmpeg)
- mp3tag (optional, for episode artwork)
- notepad (lol)
]]

local feed_template = [=[<?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"  xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title><%= title %></title>
    <link><%- base_url %></link>
    <description><![CDATA[<%- description %>]]></description>
    <language><%= language %></language>
    <itunes:image href="<%- base_url %>podcast.jpg" />
    <% for category, value in pairs(categories) do %>
      <% if type(value) == "table" then %>
        <itunes:category text="<%= category %>">
        <% for subcategory, _ in pairs(value) do %>
          <itunes:category text="<%= subcategory %>" />
        <% end %>
        </itunes:category>
      <% else %>
        <itunes:category text="<%= category %>" />
      <% end %>
    <% end %>
    <itunes:explicit><%= tostring(explicit) %></itunes:explicit>
    <% if #episodes_list > 0 then %>
      <% for _, episode_title in ipairs(episodes_list) do %>
        <% local episode = episodes_data[episode_title] %>
        <item>
          <title><%= episode.title %></title>
          <link><%- base_url %><%- episode.urlencoded_title %>.html</link>
          <description><![CDATA[<%- episode.summary %>]]></description>
          <enclosure length="<%= episode.file_size %>" type="audio/mpeg" url="<%- base_url %><%- episode.urlencoded_title %>.mp3" />
          <pubDate><%= episode.published_datetime %></pubDate>
          <guid><%= episode.guid %></guid>
          <itunes:duration><%= episode.duration_seconds %></itunes:duration>
          <itunes:episode><%= episode.episode_number %></itunes:episode>
          <itunes:image href="<%- base_url %><%- episode.urlencoded_title %>.jpg" />
        </item>
      <% end %>
    <% end %>
  </channel>
  </rss>
]=]

local index_page_template = [[<html>
  <head>
  <title><%= title %></title>
  <style>
    h1, h2 { text-align: center; }
    audio { display: block; }
    audio, div { margin: auto; }
    div, img { width: 512px; }
    img { height: 256px; object-fit: cover; }
    #podcast { height: 512px; object-fit: fill; }
  </style>
  </head>
  <body>
  <div>
    <p><a href="<%- base_url %>feed.xml">Click here to subscribe!</a></p>
    <h1><%= title %></h1>
    <img id="podcast" src="<%- base_url %>podcast.jpg" />
    <%- description %>
    <hr />
    <% if #episodes_list > 0 then %>
      <% for i = #episodes_list, 1, -1 do %>
        <% local episode = episodes_data[ episodes_list[i] ] %>
        <h2><a href="<%- base_url %><%- episode.urlencoded_title %>.html"><%= episode.title %></a></h2>
        <img src="<%- base_url %><%- episode.urlencoded_title %>.jpg" />
        <%- episode.summary %>
      <% end %>
    <% end %>
  </div>
  </body>
  </html>
]]

local episode_page_template = [[<html>
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
    <p><a href="<%- base_url %>">homepage</a></p>
    <h1><%= episode_title %></h1>
    <img src="<%- base_url %><%- urlencoded_title %>.jpg" />
    <audio controls src="<%- base_url %><%- urlencoded_title %>.mp3"></audio>
    <%- episode_summary %>
  </div>
  </body>
  </html>
]]

local utility = require("utility")

local function load_database()
  local json = require("json")
  local database
  utility.open("configuration.json", "r")(function(file)
    database = json.decode(file:read("*all"))
  end)
  return database
end

local function save_database(database)
  local json = require("json")
  utility.open("configuration.json", "w")(function(file)
    file:write(json.encode(database))
  end)
end

-- starts adding a new episode to the database
--   some functions require manual intervention, which is why this STARTS the process
--   MP3 file and JPG file should already exist in the local directory when you run this!
local function new_episode(episode_title, file_name, skip_mp3tag) -- skip_description option?
  local database = load_database()
  local urlencode = require("urlencode")
  local markdown = require("markdown")

  -- TODO check if the title already exists and error out if it does

  local episode = {
    title = episode_title,
    file_name = file_name or episode_title,
    guid = utility.uuid(),
  }
  local duration_seconds = utility.capture_execute("ffprobe -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 " .. (episode.file_name .. ".mp3"):enquote())
  episode.duration_seconds = math.floor(tonumber(duration_seconds))
  episode.urlencoded_title = urlencode(episode.file_name) -- NOTE misnomer, should be renamed to urlencoded_file_name

  print("Opening notepad to write episode summary!")
  os.execute("echo 0>> new_episode.description > NULL")
  os.execute("rm NULL") -- fuck you Windows; why the fuck are you creating this file?
  os.execute("notepad new_episode.description") -- this is blocking
  utility.open("new_episode.description", "r")(function(file)
    episode.summary = markdown(file:read("*all"))
  end)

  if not skip_mp3tag then
    print("Opening mp3tag to add episode artwork.\n  (This step must be completed manually, and then podcast.lua must be called again to finish this episode!)")
    os.execute("mp3tag /fn:" .. (episode.file_name .. ".mp3"):enquote())
  end

  -- return episode
  database.episodes_data[episode_title] = episode
  save_database(database)
end

local function generate_feed(database)
  local etlua = require("etlua")

  local feed_content = etlua.compile(feed_template)(database)
  utility.open("docs/feed.xml", "w")(function(file)
    file:write(feed_content)
  end)

  local index_content = etlua.compile(index_page_template)(database)
  utility.open("docs/index.html", "w")(function(file)
    file:write(index_content)
  end)

  return true
end

local function generate_page(database, episode)
  local etlua = require("etlua")

  local episode_page_content = etlua.compile(episode_page_template)({
    podcast_title = database.title,
    episode_title = episode.title,
    urlencoded_title = episode.urlencoded_title,
    episode_summary = episode.summary,
    base_url = database.base_url,
  })
  utility.open("docs/" .. episode.file_name .. ".html", "w")(function(file)
    file:write(episode_page_content)
  end)

  return true
end

local function generate_all_pages(database)
  local etlua = require("etlua")

  for _, episode_title in ipairs(database.episodes_list) do
    local episode = database.episodes_data[episode_title]
    generate_page(database, episode)
  end

  return true
end

local function generate_everything(database)
  generate_feed(database)
  generate_all_pages(database)
end

local function publish_episode(episode_title)
  local database = load_database()

  local episode = database.episodes_data[episode_title]
  if not episode then error("Episode " .. episode_title:enquote() .. " does not exist.") end

  if episode.episode_number then error("Episode " .. episode_title:enquote() .. " has already been published!") end

  local episode_number = #database.episodes_list + 1
  episode.episode_number = episode_number
  episode.file_size = utility.file_size(episode.file_name .. ".mp3")
  episode.published_datetime = os.date("%a, %d %b %Y %H:%M:%S GMT", os.time() - database.timezone_offset * 60 * 60)

  database.episodes_list[episode_number] = episode.title

  -- NOTE I want to allow truncated summaries

  -- TODO in the future, don't recompile the ENTIRE thing just for adding an episode
  generate_feed(database)
  generate_page(database, episode)

  os.execute("mv " .. (episode.file_name .. ".mp3"):enquote() .. " " .. ("docs/" .. episode.file_name .. ".mp3"):enquote())
  os.execute("mv " .. (episode.file_name .. ".jpg"):enquote() .. " " .. ("docs/" .. episode.file_name .. ".jpg"):enquote())

  save_database(database)
end

local function delete_episode(episode_title)
  local database = load_database()

  local episode = database.episodes_data[episode_title]
  if not episode then error("Episode " .. episode_title:enquote() .. " does not exist.") end

  os.execute("mkdir .trash")

  if episode.episode_number then
    table.remove(database.episodes_list, episode.episode_number)
    os.execute("mv " .. ("docs/" .. episode.file_name .. ".mp3"):enquote() .. " .trash/")
    os.execute("mv " .. ("docs/" .. episode.file_name .. ".jpg"):enquote() .. " .trash/")
    os.execute("mv " .. ("docs/" .. episode.file_name .. ".html"):enquote() .. " .trash/")
    generate_everything(database)
  else
    os.execute("mv " .. (episode.file_name .. ".mp3"):enquote() .. " .trash/")
    os.execute("mv " .. (episode.file_name .. ".jpg"):enquote() .. " .trash/")
  end
  database.episodes_data[episode_title] = nil

  -- TODO add a force-deletion argument to delete instead of move
  print("Any MP3, JPG, or HTML files have been moved to ./.trash as a precaution against data loss.")

  save_database(database)
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
    publish = publish_episode,
    delete = delete_episode,
    regenerate = function()
      generate_everything(load_database())
    end,
  }
  return actions[arguments.action](arguments.title, arguments.file_name)
end

local arguments = argparse(arg, {"action", "title", "file_name"})
if not arguments then return end
main(arguments)
