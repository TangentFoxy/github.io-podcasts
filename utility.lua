-- NOTE this assumes there are not quotes in the string
function string.enquote(s)
  return "\"" .. s .. "\""
end

math.randomseed(os.time())
local utility = {}

-- io.open, but errors are immediately thrown, and the file is closed for you
utility.open = function(file_name, mode, custom_error_message)
  local file, err = io.open(file_name, mode)
  if not file then error(custom_error_message or err) end
  return function(fn)
    local success, result_or_error = pcall(function() return fn(file) end)
    file:close()
    if not success then
      error(result_or_error) -- custom_error_message is only for when the file doesn't exist, this function should not hide *your* errors
    end
    return result_or_error
  end
end

utility.file_size = function(file_path)
  local file, err = io.open(file_path, "rb")
  if err then error(err) end
  local size = file:seek("end")
  file:close()
  return size
end

-- always uses outputting to a temporary file to guarantee safety
utility.capture_execute = function(command, tmp_file_name)
  local file_name = tmp_file_name or utility.tmp_file_name()
  os.execute(command .. " > " .. file_name .. " 2> NULL") -- NOTE redirecting errors might break things I've used this for in the past..

  local file = io.open(file_name, "r")
  local output = file:read("*all")
  file:close()
  os.execute("rm " .. file_name:enquote()) -- NOTE may not work on all systems, I have a version somewhere that always does
  return output
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
  return "." .. utility.uuid() .. ".tmp"
end

return utility
