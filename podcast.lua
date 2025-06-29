#!/usr/bin/env luajit

package.path = (arg[0]:match("@?(.*/)") or arg[0]:match("@?(.*\\)")) .. "lib" .. package.config:sub(1, 1) .. "?.lua;" .. package.path
local utility = require "utility"
local argparse = require "argparse"
local json = require "dkjson"
local urlencode = require "urlencode"
local markdown = require "markdown"
local etlua = require "etlua"
local date = require "date"

local parser = argparse():help_max_width(80)
local new = parser:command("new", "start adding a new episode")
new:argument("title", "episode title (ideally should match MP3 file and optional JPG file names)"):args(1)
new:argument("file_name", "if the title and file names are different, specify the file name here"):args("?")
new:option("-s --skip"):choices{"mp3tag", "description"}:count("*")
local publish = parser:command("publish", "finish adding an episode and publish it immediately")
publish:argument("title", "episode title (or file name if it is different!)"):args(1)
publish:flag("--no-git", "do not automatically add, commit, and push all changes")
local delete = parser:command("delete", "deletes an episode (regenerate is run as well if the episode had been published), files are moved to a local trash folder in case recovery is necessary")
delete:argument("title", "episode title (or file name if it is different!)"):args(1)
local regenerate = parser:command("regenerate", "regenerates all web pages and RSS feed")
local metadata = parser:command("metadata", "print podcast metadata")
local schedule = parser:command("schedule", "schedule an episode to be published automatically at a later date/time, requires an instance of scheduler running (or \"at\" to be installed on Linux)")
schedule:argument("title", "episode title (or file name if it is different!)"):args(1)
schedule:argument("date_time", "publication date/time (uses LuaDate to parse https://tieske.github.io/date/)"):args(1)
local scheduler = parser:command("scheduler", "eternally loops, publishing episodes as scheduled")
local options = parser:parse()

if options.skip then
  for _, option in ipairs(options.skip) do
    options.skip[option] = true
  end
end



utility.required_program("ffmpeg")
utility.required_program("ffprobe")

local podcast = {}

function podcast.save2json(file_name, tab)
  utility.open(file_name, "w", function(file)
    local encoded_json = json.encode(tab, { indent = true })
    file:write(encoded_json)
    file:write("\n")
  end)
end

function podcast.save_episode(episode)
  podcast.save2json("data/" .. episode.file_name .. ".json", episode)
end

local convert_database

local function load_database()
  -- TODO there should be a way to generate new without requiring it to already exist..
  local database = utility.open("configuration.json", "r")(function(file)
    return json.decode(file:read("*all"))
  end)
  if not database.next_episode_number then
    if database.episodes_list then
      database.next_episode_number = #database.episodes_list + 1
    else
      database.next_episode_number = #database.published_episodes + 1
    end
  end
  if database.episodes_data then
    convert_database(database)
  end
  return database
end

local function save_database(database)
  podcast.save2json("configuration.json", database)
end

convert_database = function(database)
  database.published_episodes = {}
  for i = 1, database.next_episode_number - 1 do
    database.published_episodes[i] = {}
  end

  for _, episode in pairs(database.episodes_data) do
    utility.open("data/" .. episode.file_name .. ".md", "w", function(file)
      file:write(episode.summary)
    end)
    episode.summary = nil
    episode.urlencoded_file_name = episode.urlencoded_title
    episode.urlencoded_title = nil
    podcast.save_episode(episode)
    if episode.episode_number then
      local published_episode = database.published_episodes[episode.episode_number]
      published_episode.title = episode.title
      if episode.title ~= episode.file_name then
        published_episode.file_name = episode.file_name
      end
    end
  end
  database.episodes_data = nil

  database.episodes_list = nil

  save_database(database)
end



-- starts adding a new episode to the database
--   some functions require manual intervention, which is why this STARTS the process
--   MP3 file and JPG file should already exist in the local directory when you run this!
local function new_episode(episode_title, file_name, skip)
  file_name = file_name or episode_title

  assert(not utility.is_file("data/" .. file_name .. ".json"), "An episode with that title or file name already exists.")
  if not utility.is_file(file_name .. ".mp3") then
    local _, _, extension = utility.split_path_components(file_name)
    if extension then
      file_name = file_name:sub(1, -(#extension+2))
    end
  end
  assert(not utility.is_file("data/" .. file_name .. ".json"), "An episode with that title or file name already exists.")
  assert(utility.is_file(file_name .. ".mp3"), "An MP3 must be placed in the same directory as this script first. Its name should be the title or specified manually when different!")

  local episode = {
    title = episode_title,
    file_name = file_name,
    guid = utility.uuid(),
  }
  local duration_seconds = utility.capture("ffprobe -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 " .. (episode.file_name .. ".mp3"):enquote() .. utility.commands.silence_errors)
  episode.duration_seconds = math.floor(tonumber(duration_seconds))
  episode.urlencoded_file_name = urlencode(episode.file_name)

  local summary_file_name = ("data/" .. episode.file_name .. ".md")
  os.execute("echo \"\" > " .. summary_file_name:enquote() .. utility.commands.silence_errors) -- TODO replace with touch

  if not options.skip.description then
    if utility.OS == "Windows" then
      print("Opening notepad to write episode summary!")
      os.execute("notepad " .. summary_file_name:enquote()) -- this is blocking, so we don't need to wait on input
    else
      print("Opening " .. summary_file_name:enquote() .. " to write episode summary!")
      os.execute("open " .. summary_file_name:enquote()) -- NOT blocking, so we need to wait for user to specify to continue
      print("Press enter to continue. ")
      io.read("*line")
    end
  end

  if not utility.is_file(episode.file_name .. ".jpg") then
    os.execute("cp docs/podcast.jpg " .. (episode.file_name .. ".jpg"):enquote())
  end

  if not options.skip.mp3tag then
    print("Adding artwork to MP3 file..")
    os.execute("ffmpeg -i " .. (episode.file_name .. ".mp3"):enquote() .. " -i " .. (episode.file_name .. ".jpg"):enquote() .. " -map_metadata 0 -map 0 -map 1 -acodec copy " .. (utility.temp_directory .. episode.file_name .. ".mp3"):enquote())
    os.execute("mv -f " .. (utility.temp_directory .. episode.file_name .. ".mp3"):enquote() .. " ./")
  end

  podcast.save_episode(episode)
end



local function generate_feed(database)
  local feed_template
  utility.open("templates/feed.etlua", "r")(function(file)
    feed_template = file:read("*all")
  end)

  local index_page_template
  utility.open("templates/index_page.etlua", "r")(function(file)
    index_page_template = file:read("*all")
  end)

  -- WARNING this is super hacky and really should be replaced with something better!
  database.episodes_data = {}
  database.episodes_list = {}
  for _, info in ipairs(database.published_episodes) do
    if info.title then
      local episode = utility.open("data/" .. (info.file_name or info.title) .. ".json", "r", function(file)
        return json.decode(file:read("*all"))
      end)
      episode.summary = utility.open("data/" .. episode.file_name .. ".md", "r", function(file)
        return markdown(file:read("*all"))
      end)
      database.episodes_data[episode.title] = episode
      database.episodes_list[episode.episode_number] = episode.title
    end
  end

  local feed_content = etlua.compile(feed_template)(database)
  feed_content = feed_content:gsub("%s+", " ")
  utility.open("docs/feed.xml", "w")(function(file)
    file:write(feed_content:sub(1, -2))
  end)

  local index_content = etlua.compile(index_page_template)(database)
  index_content = index_content:gsub("%s+", " ")
  utility.open("docs/index.html", "w")(function(file)
    file:write(index_content:sub(1, -2))
  end)

  database.episodes_data = nil
  database.episodes_list = nil

  return true
end

local function generate_page(database, episode)
  local episode_page_template
  utility.open("templates/episode_page.etlua", "r")(function(file)
    episode_page_template = file:read("*all")
  end)

  local summary = utility.open("data/" .. episode.file_name .. ".md", "r", function(file)
    return markdown(file:read("*all"))
  end)

  local episode_page_content = etlua.compile(episode_page_template)({
    podcast_title = database.title,
    episode_title = episode.title,
    urlencoded_file_name = episode.urlencoded_file_name,
    episode_summary = summary,
    base_url = database.base_url,
  })
  episode_page_content = episode_page_content:gsub("%s+", " ")
  utility.open("docs/" .. episode.file_name .. ".html", "w")(function(file)
    file:write(episode_page_content:sub(1, -2))
  end)

  return true
end

local function generate_all_pages(database)
  for _, info in ipairs(database.published_episodes) do
    if info.title then
      utility.open("data/" .. (info.file_name or info.title) .. ".json", "r", function(file)
        generate_page(database, json.decode(file:read("*all")))
      end)
    end
  end

  return true
end

local function generate_everything(database)
  generate_feed(database)
  generate_all_pages(database)
end



local function publish_episode(episode_title_or_file, options)
  local database = load_database()

  local episode = utility.open("data/" .. episode_title_or_file .. ".json", "r", function(file)
    return json.decode(file:read("*all"))
  end)
  assert(not episode.episode_number, "Episode " .. episode.title:enquote() .. " has already been published!")

  local episode_number = database.next_episode_number or 1
  database.next_episode_number = episode_number + 1
  episode.episode_number = episode_number
  episode.file_size = utility.file_size(episode.file_name .. ".mp3")
  episode.published_datetime = os.date("%a, %d %b %Y %H:%M:%S GMT", os.time() - database.timezone_offset * 60 * 60)

  database.published_episodes[episode_number] = {
    title = episode.title
  }
  if episode.title ~= episode.file_name then
    database.published_episodes[episode_number].file_name = episode.file_name
  end

  -- these have to be saved before generators are called or the generators fail
  save_database(database)
  podcast.save_episode(episode)

  -- NOTE I want to allow truncated summaries

  -- TODO in the future, don't recompile the ENTIRE thing just for adding an episode
  generate_feed(database)
  generate_page(database, episode)

  os.execute("mv " .. (episode.file_name .. ".mp3"):enquote() .. " " .. ("docs/" .. episode.file_name .. ".mp3"):enquote())
  os.execute("mv " .. (episode.file_name .. ".jpg"):enquote() .. " " .. ("docs/" .. episode.file_name .. ".jpg"):enquote())

  if database.scheduled_episodes then
    for unix_timestamp, scheduled_episode_title in pairs(database.scheduled_episodes) do
      if scheduled_episode_title == episode_title_or_file then
        database.scheduled_episodes[unix_timestamp] = nil
        break
      end
    end
  end

  save_database(database)

  if not options.no_git then
    os.execute("git add *")
    os.execute("git commit -m " .. ("published episode " .. episode.episode_number):enquote())
    os.execute("git pull origin")
    os.execute("git push origin")
  end
end

local function delete_episode(episode_title_or_file)
  local database = load_database()

  local episode = utility.open("data/" .. episode_title_or_file .. ".json", "r", function(file)
    return json.decode(file:read("*all"))
  end)
  assert(episode, "Episode " .. episode_title_or_file:enquote() .. " does not exist.")

  os.execute("mkdir trash" .. utility.commands.silence_errors)

  if episode.episode_number then
    database.published_episodes[episode.episode_number] = {}
    os.execute("mv " .. ("docs/" .. episode.file_name .. ".mp3"):enquote() .. " trash/")
    os.execute("mv " .. ("docs/" .. episode.file_name .. ".jpg"):enquote() .. " trash/")
    os.execute("mv " .. ("docs/" .. episode.file_name .. ".html"):enquote() .. " trash/")
    generate_everything(database)
  else
    os.execute("mv " .. (episode.file_name .. ".mp3"):enquote() .. " trash/")
    os.execute("mv " .. (episode.file_name .. ".jpg"):enquote() .. " trash/")
  end
  os.execute("mv " .. ("data/" .. episode.file_name .. ".md"):enquote() .. "trash/")
  os.execute("mv " .. ("data/" .. episode.file_name .. ".json"):enquote() .. "trash/")

  -- TODO add a force-deletion argument to delete instead of move
  print("All relevant files have been moved to ./trash as a precaution against accidental data loss.")

  save_database(database)
end

local function schedule(episode_title_or_file, datetime)
  local database = load_database()

  local episode = utility.open("data/" .. episode_title_or_file .. ".json", "r", function(file)
    return json.decode(file:read("*all"))
  end)
  assert(episode, "Episode " .. episode_title_or_file:enquote() .. " does not exist.")
  assert(not episode.episode_number, "Episode " .. episode.title:enquote() .. " has already been published!")

  if not database.scheduled_episodes then database.scheduled_episodes = {} end
  datetime = date(datetime)
  local y, m, d = datetime:getdate()
  local h, s = datetime:gettime()
  local unix_timestamp = os.time({ year = y, month = m, day = d, hour = h, min = m })
  database.scheduled_episodes[tostring(unix_timestamp)] = episode_title_or_file

  save_database(database)
  print("(In order for scheduling to work, an instance of " .. ("podcast.lua scheduler"):enquote() .. " must be running.)")
end

-- Windows' task scheduler is inadequate for my needs, checking every minute for a scheduled task and running it will be more effective
local function infinite_loop()
  while true do
    local now = os.time()
    print(os.date("%H:%M", now) .. " Checking schedule...")
    local database = load_database()
    if database.scheduled_episodes then
      for unix_timestamp, episode_title_or_file in pairs(database.scheduled_episodes) do
        if now >= tonumber(unix_timestamp) then
          publish_episode(episode_title_or_file)
          database.scheduled_episodes[unix_timestamp] = nil
          -- save_database(database) -- publish_episode loads and saves the database itself, we should not save it here
          break
        end
      end
    end
    os.execute("sleep 60")
  end
end



local function print_metadata()
  local database = load_database()
  database.episodes_data = nil
  database.episodes_list = nil
  utility.print_table(database)
end



os.execute("mkdir data" .. utility.commands.silence_errors)

if options.new then
  new_episode(options.title, options.file_name, options.skip)
elseif options.publish then
  publish_episode(options.title, options)
elseif options.delete then
  delete_episode(options.title)
elseif options.regenerate then
  generate_everything(load_database())
elseif options.metadata then
  print_metadata()
elseif options.schedule then
  schedule(options.title, options.date_time)
elseif options.scheduler then
  infinite_loop()
end
