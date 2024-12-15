#!/usr/bin/env luajit

local help = [[Usage:

  podcast.lua <action> <title> [options]

<action>:
  new:        Starts the process of adding a new episode. An MP3 file should be
              placed in the root of the repo, next to this script. The file name
              should match the title. If it doesn't, specify the file name as an
              extra argument WITHOUT EXTENSION. If episode artwork is included,
              it should have the same name as the MP3 file, be in JPEG format,
              and end in ".jpg". Notepad will be opened to write the episode
              description. It will be converted to HTML from Markdown.
  publish:    Finishes adding a new episode and publishes it immediately as the
              next episode. (Does not commit and push YET, you must do so.)
  delete:     Deletes an episode. If it was published, then regenerate is run as
              well. Files are moved to a ".trash" folder locally in case of
              accidental removal.
  regenerate: In case of template changes or unpublished changes to database,
              this regenerates every page (and feed).
  metadata:   Prints podcast metadata.
  schedule:   Schedules an episode to be published automatically. Requires
              "podcast.lua scheduler" running in the background. LuaDate is used
              to handle a variety of datetime formats automatically.
  scheduler:  Checks every minute for when an episode should be published, and
              publishes when necessary.

Requirements:
- ffprobe (part of ffmpeg)
- mp3tag (optional, for episode artwork)
- notepad (lol)
]]

local utility = require("lib.utility")

local function load_database()
  local json = require("lib.json")
  local database
  utility.open("configuration.json", "r")(function(file)
    database = json.decode(file:read("*all"))
  end)
  if not database.next_episode_number then -- addresses #20 episode numbering can have missing items
    database.next_episode_number = #database.episodes_list + 1
  end
  return database
end

local function save_database(database)
  local json = require("lib.json")
  local encoded_json = json.encode(database)
  utility.open("configuration.json", "w")(function(file)
    file:write(encoded_json)
  end)
end

-- starts adding a new episode to the database
--   some functions require manual intervention, which is why this STARTS the process
--   MP3 file and JPG file should already exist in the local directory when you run this!
local function new_episode(episode_title, file_name, skip_mp3tag) -- skip_description option?
  local database = load_database()
  local urlencode = require("lib.urlencode")
  local markdown = require("lib.markdown")

  assert(not database.episodes_data[episode_title], "An episode with that title already exists.")

  local episode = {
    title = episode_title,
    file_name = file_name or episode_title,
    guid = utility.uuid(),
  }
  local duration_seconds = utility.capture_execute("ffprobe -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 " .. (episode.file_name .. ".mp3"):enquote())
  episode.duration_seconds = math.floor(tonumber(duration_seconds))
  episode.urlencoded_title = urlencode(episode.file_name) -- NOTE misnomer, should be renamed to urlencoded_file_name_without_extension

  print("Opening notepad to write episode summary!")
  os.execute("echo 0>> new_episode.description > NUL")
  -- utility.open("new_episode.description", "w")(function(file) file:write("") end) -- the previous description being left in-place is a feature, not a bug
  os.execute("notepad new_episode.description") -- this is blocking
  utility.open("new_episode.description", "r")(function(file)
    episode.summary = markdown(file:read("*all"))  --TODO save markdown, and process only when building pages
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
  local etlua = require("lib.etlua")

  local feed_template
  utility.open("templates/feed.etlua", "r")(function(file)
    feed_template = file:read("*all")
  end)

  local feed_content = etlua.compile(feed_template)(database)
  utility.open("docs/feed.xml", "w")(function(file)
    file:write(feed_content)
  end)

  local index_page_template
  utility.open("templates/index_page.etlua", "r")(function(file)
    index_page_template = file:read("*all")
  end)

  local index_content = etlua.compile(index_page_template)(database)
  utility.open("docs/index.html", "w")(function(file)
    file:write(index_content)
  end)

  return true
end

local function generate_page(database, episode)
  local etlua = require("lib.etlua")

  local episode_page_template
  utility.open("templates/episode_page.etlua", "r")(function(file)
    episode_page_template = file:read("*all")
  end)

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
  local etlua = require("lib.etlua")

  for _, episode_title in pairs(database.episodes_list) do
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
  assert(episode, "Episode " .. episode_title:enquote() .. " does not exist.")
  assert(not episode.episode_number, "Episode" .. episode_title:enquote() .. " has already been published!")

  local episode_number = database.next_episode_number or 1
  database.next_episode_number = episode_number + 1
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

  if database.scheduled_episodes then
    for unix_timestamp, scheduled_episode_title in pairs(database.scheduled_episodes) do
      if scheduled_episode_title == episode_title then
        database.scheduled_episodes[unix_timestamp] = nil
        break
      end
    end
  end

  save_database(database)

  os.execute("git add *")
  os.execute("git commit -m " .. ("published episode " .. episode.episode_number):enquote())
  os.execute("git pull origin")
  os.execute("git push origin")
end

local function delete_episode(episode_title)
  local database = load_database()

  local episode = database.episodes_data[episode_title]
  assert(episode, "Episode " .. episode_title:enquote() .. " does not exist.")

  os.execute("mkdir .trash")

  if episode.episode_number then
    database.episodes_list[episode.episode_number] = nil
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

local function print_metadata()
  local database = load_database()
  database.episodes_data = nil
  database.episodes_list = nil
  utility.print_table(database)
end

local function schedule(episode_title, datetime)
  local date = require("lib.date")
  local database = load_database()

  local episode = database.episodes_data[episode_title]
  assert(episode, "Episode " .. episode_title:enquote() .. " does not exist.")
  assert(not episode.episode_number, "Episode" .. episode_title:enquote() .. " has already been published!")

  if not database.scheduled_episodes then database.scheduled_episodes = {} end
  datetime = date(datetime)
  local y, m, d = datetime:getdate()
  local h, s = datetime:gettime()
  local unix_timestamp = os.time({ year = y, month = m, day = d, hour = h, min = m })
  database.scheduled_episodes[tostring(unix_timestamp)] = episode_title

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
      for unix_timestamp, episode_title in pairs(database.scheduled_episodes) do
        if now >= tonumber(unix_timestamp) then
          publish_episode(episode_title)
          database.scheduled_episodes[unix_timestamp] = nil
          -- save_database(database) -- publish_episode loads and saves the database itself, we should not save it here
          break
        end
      end
    end
    os.execute("sleep 60")
  end
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
    metadata = print_metadata,
    schedule = schedule,
    scheduler = infinite_loop,
  }
  if actions[arguments.action] then
    return actions[arguments.action](arguments.title, arguments.file_name)
  else
    error("Invalid <action>.")
  end
end

local arguments = argparse(arg, {"action", "title", "file_name"})
if not arguments then return end
main(arguments)
