-- modified from https://gist.github.com/liukun/f9ce7d6d14fa45fe9b924a3eed5c3d99
-- modified again to fix an issue with that version, and packaged for require()

local char_to_hex = function(c)
  return string.format("%%%02X", string.byte(c))
end

local function urlencode(url)
  if url == nil then
    return
  end
  url = url:gsub("\n", "\r\n")
  -- url = url:gsub("([^%w ])", char_to_hex) -- escapes extra characters
  url = url:gsub("([^%w _%%%-%.~])", char_to_hex) -- ignores safe characters according to RFC 3986
  url = url:gsub(" ", "%%20")
  return url
end

local hex_to_char = function(x)
  return string.char(tonumber(x, 16))
end

local urldecode = function(url)
  if url == nil then
    return
  end
  url = url:gsub("%%20", " ")
  url = url:gsub("%%(%x%x)", hex_to_char)
  return url
end

-- ref: https://gist.github.com/ignisdesign/4323051
-- ref: http://stackoverflow.com/questions/20282054/how-to-urldecode-a-request-uri-string-in-lua
-- to encode table as parameters, see https://github.com/stuartpb/tvtropes-lua/blob/master/urlencode.lua

return setmetatable({
  encode = urlencode,
  decode = urldecode,
}, {
  __call = function(tab, ...) return urlencode(...) end,
})
