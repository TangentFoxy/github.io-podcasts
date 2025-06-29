math.randomseed(os.time())

local utility

if package.config:sub(1, 1) == "\\" then
  utility = {
    OS = "Windows",
    path_separator = "\\",
    temp_directory = "C:\\Windows\\Temp\\",
    commands = {
      recursive_remove = "rmdir /s /q ",
      list = "dir /w /b ",
      which = "where ",
      move = "move ",
      silence_output = " >nul 2>nul",
      silence_errors = " 2>nul",
    },
  }
else
  utility = {
    OS = "UNIX-like",
    path_separator = "/",
    temp_directory = "/tmp/",
    commands = {
      recursive_remove = "rm -r ",
      list = "ls -1a ",
      which = "which ",
      move = "mv ",
      silence_output = " >/dev/null 2>/dev/null",
      silence_errors = " 2>/dev/null",
    },
  }
end

utility.version = "1.2.1"
-- WARNING: This will return "./" if the original script is called locally instead of with an absolute path!
utility.path = (arg[0]:match("@?(.*/)") or arg[0]:match("@?(.*\\)")) -- inspired by discussion in https://stackoverflow.com/q/6380820

utility.require = function(...)
  -- if libraries adjacent to this one aren't already loadable, make sure they are!
  if not package.path:find(utility.path, 1, true) then
    package.path = utility.path .. "?.lua;" .. package.path
  end
  return require(...)
end

-- errors if specified program isn't in the path
local _required_program_cache = {}
utility.required_program = function(name)
  if _required_program_cache[name] then
    return true
  end
  if os.execute(utility.commands.which .. tostring(name) .. utility.commands.silence_output) == 0 then
    _required_program_cache[name] = true
  else
    error("\n\n" .. tostring(name) .. " must be installed and in the path\n")
  end
end



-- always uses outputting to a temporary file to guarantee safety
function utility.capture_safe(command, get_status)
  local file_name = utility.tmp_file_name()
  command = command .. " > " .. file_name
  if get_status then
    command = command .. "\necho $? >> " .. file_name
  end
  os.execute(command)

  local file = io.open(file_name, "r")
  local output = file:read("*all")
  file:close()
  os.execute("rm " .. file_name)

  if get_status then
    local start, finish = output:find("\n.-\n$")
    return tonumber(output:sub(start + 1, finish - 1)), output:sub(1, start)
  end

  return output
end
utility.capture = utility.capture_safe

-- can hang indefinitely; not always available
function utility.capture_unsafe(command)
  if io.popen then
    local file = assert(io.popen(command, 'r'))
    local output = assert(file:read('*all'))
    file:close()
    return output
  else
    print("WARNING: io.popen not available, using a temporary file to receive output from:\n", command)
    return utility.capture_safe(command)
  end
end



-- trim6 from Lua users wiki (best all-round pure Lua performance)
function string.trim(s)
  return s:match'^()%s*$' and '' or s:match'^%s*(.*%S)'
end

function string.enquote(s)
  return "\"" .. s:gsub("\"", "\\\"") .. "\""
end

function string.gsplit(s, delimiter)
  local function escape_special_characters(s)
    local special_characters = "[()%%.[^$%]*+%-?]"
    if s == nil then return end
    return (s:gsub(special_characters, "%%%1"))
  end

  delimiter = delimiter or ","
  if s:sub(-#delimiter) ~= delimiter then s = s .. delimiter end
  return s:gmatch("(.-)" .. escape_special_characters(delimiter))
end

function string.split(s, delimiter)
  local result = {}
  for item in s:gsplit(delimiter) do
    result[#result + 1] = item
  end
  return result
end



-- modified from my fork of lume
utility.uuid = function()
  local fn = function(x)
    local r = math.random(16) - 1
    r = (x == "x") and (r + 1) or (r % 4) + 9
    return ("0123456789abcdef"):sub(r, r)
  end
  return (("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", fn))
end

utility.tmp_file_name = function()
  return utility.temp_directory .. utility.uuid()
end

-- while I could replace this with a better implementation, I'm used to how it works and I might break existing scripts
utility.make_safe_file_name = function(file_name)
  file_name = file_name:gsub("[%\"%:%\\%!%@%#%$%%%^%*%=%{%}%|%;%<%>%?%/]", "") -- everything except the &
  file_name = file_name:gsub(" %&", ",")   -- replacing & with a comma works for 99% of things
  file_name = file_name:gsub("%&", ",")    -- replacing & with a comma works for 99% of things
  file_name = file_name:gsub("[%s+]", " ") -- more than one space in succession should be a single space
  return file_name
end

utility.split_path_components = function(file_path)
  local path, name, extension = string.match(file_path, "(.-)([^\\/]-%.?([^%.\\/]*))$")
  if name == extension then
    extension = nil
  end
  return path, name, extension
end

-- wrapper around io.open to prevent leaving a file handle open accidentally
-- throws errors instead of returning them
--   usage: utility.open(file_name, mode, function(file) --[[ your code ]] end)
--       or utility.open(file_name, mode)(function(file_handle) --[[ your code ]] end)
function utility.open(file_name, mode, func)
  local file, err = io.open(file_name, mode)
  if not file then error(err) end
  if func then
    local success, result = pcall(function() return func(file) end)
    file:close()
    if not success then error(result) end
    return result
  else
    return function(fn)
      local success, result = pcall(function() return fn(file) end)
      file:close()
      if not success then
        error(result)
      end
      return result
    end
  end
end

-- run a function on each file name in a directory
--   example list items: utility.ls(".")(print)
utility.ls = function(path)
  local command = utility.commands.list
  if path then
    command = command .. " \"" .. path .. "\""
  end

  local output = utility.capture_safe(command)

  return function(fn)
    for line in output:gmatch("[^\r\n]+") do -- thanks to https://stackoverflow.com/a/32847589
      fn(line)
    end
  end
end

utility.path_exists = function(file_name)
  local file = io.open(file_name, "r")
  if file then file:close() return true else return false end
end
function utility.file_exists(file_name)
  print("WARNING: Use utility.path_exists instead, or utility.is_file to check for a file existing.")
  return utility.path_exists(file_name)
end

utility.is_file = function(file_name)
  local file = io.open(file_name, "r")
  if file then
    local _, error_message = file:read(0)
    if error_message then
      return false
    end
    return true
  else
    return false
  end
end

function utility.file_size(file_path)
  return utility.open(file_path, "rb", function(file) return file:seek("end") end)
end

utility.escape_quotes_and_escapes = function(input)
  -- the order of these commands is important and must be preserved
  input = input:gsub("\\", "\\\\")
  input = input:gsub("\"", "\\\"")
  return input
end



-- only use for brief loads/saves, as this will block until a lock can be established
-- returns a UUID that can be checked on release to make sure unforeseen errors did not occur
function utility.get_lock(file_path)
  local lock_obtained, lock_uuid, lock_file_path = false, utility.uuid(), file_path .. ".lock"
  repeat
    if not utility.file_exists(lock_file_path) then
      pcall(function()
        utility.open(lock_file_path, "w")(function(file)
          file:write(lock_uuid)
        end)
        utility.open(lock_file_path, "r")(function(file)
          if file:read("*all") == lock_uuid then
            lock_obtained = true
          end
        end)
      end)
    end
    if not lock_obtained then
      os.execute("sleep 1")
    end
  until lock_obtained
  return lock_uuid
end

-- specifying lock_uuid is optional, to error if a conflict occurred despite the lock (should not be possible)
function utility.release_lock(file_path, lock_uuid)
  local lock_file_path = file_path .. ".lock"
  if lock_uuid then
    utility.open(lock_file_path, "r")(function(file)
      if not file:read("*all") == lock_uuid then
        error("\n\n Lock UUID changed while lock was obtained. Data loss may have occurred. \n\n")
      end
    end)
  end
  os.execute("rm " .. lock_file_path:enquote())
end



local config, config_lock
utility.get_config = function()
  if not config then
    local config_path = utility.path .. "config.json"
    if utility.file_exists(config_path) then
      config_lock = utility.get_lock(config_path)
      utility.open(config_path, "r")(function(config_file)
        local json = utility.require("dkjson")
        config = json.decode(config_file:read("*all"))
      end)
    else
      config = {}
    end
  end
  return config
end

utility.save_config = function()
  if config then
    local config_path = utility.path .. "config.json"
    if not config_lock then
      print("Warning: A config lock file was not established.")
    end
    utility.open(config_path, "w")(function(config_file)
      local json = utility.require("dkjson")
      config_file:write(json.encode(config, { indent = true }))
    end)
    if config_lock then
      utility.release_lock(config_path, config_lock)
    end
  else
    error("utility config not loaded")
  end
end



utility.deepcopy = function(tab)
  local _type = type(tab)
  local copy
  if _type == "table" then
    copy = {}
    for key, value in next, tab, nil do
      copy[utility.deepcopy(key)] = utility.deepcopy(value)
    end
    setmetatable(copy, utility.deepcopy(getmetatable(tab)))
  else
    copy = tab
  end
  return copy
end

utility.enumerate = function(list)
  local result = {}
  for _, value in ipairs(list) do
    result[value] = {}
  end
  return result
end

local _
_, utility.inspect = pcall(function() return utility.require("inspect") end)
if _ then
  function utility.print_table(tab)
    print(utility.inspect(tab))
  end
else
  utility.inspect = nil
end



-- a super common need I'm encountering is wanting content from a URL without side effects
utility.curl_read = function(download_url, curl_options)
  utility.required_program("curl")
  local tmp_file_name = utility.tmp_file_name()
  local command = "curl "
  if curl_options then
    command = command .. curl_options .. " "
  end
  os.execute(command .. download_url:enquote() .. " > " .. tmp_file_name)
  local file_contents
  utility.open(tmp_file_name, "r", "Could not download " .. download_url:enquote())(function(file)
    file_contents = file:read("*all")
  end)
  return file_contents
end

return utility
