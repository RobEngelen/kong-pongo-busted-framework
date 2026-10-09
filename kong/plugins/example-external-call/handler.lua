-- Calls an external HTTP service for every request (or once per `cache_ttl`),
-- takes one field from its JSON response and adds it as a header to the request
-- that goes to the upstream service.
--
-- This is the pattern behind e.g. token plugins: fetch a token from an identity
-- provider, cache it, and inject it as an Authorization header.

local http  = require "resty.http"   -- HTTP client, ships with Kong
local cjson = require "cjson.safe"   -- JSON decoder that returns nil + error instead of throwing

local PLUGIN_NAME = "example-external-call"


local ExampleExternalCallHandler = {
  PRIORITY = 900,    -- below the authentication plugins (e.g. key-auth = 1250), so it runs after them
  VERSION = "0.1.0",
}


-- Calls the external service and extracts `conf.json_field` from the JSON response.
-- Returns the value as a string, or nil + an HTTP status for the client + an error message.
local function fetch_value(conf)
  local httpc = http.new()
  httpc:set_timeout(conf.timeout)

  local res, err = httpc:request_uri(conf.url, {
    method = "GET",
    headers = { ["Accept"] = "application/json" },
    ssl_verify = conf.ssl_verify,
  })

  if not res then
    if err == "timeout" then
      return nil, 504, "call to " .. conf.url .. " timed out"
    end
    return nil, 502, "call to " .. conf.url .. " failed: " .. tostring(err)
  end

  if res.status < 200 or res.status > 299 then
    return nil, 502, conf.url .. " returned status " .. res.status
  end

  local body = cjson.decode(res.body)
  if type(body) ~= "table" then
    return nil, 502, conf.url .. " did not return a JSON object"
  end

  local value = body[conf.json_field]
  local value_type = type(value)
  if value_type ~= "string" and value_type ~= "number" and value_type ~= "boolean" then
    return nil, 502, "no field '" .. conf.json_field .. "' in the response of " .. conf.url
  end

  return tostring(value)
end


-- Returns the value, from Kong's cache when caching is enabled.
-- Same return values as fetch_value().
local function get_value(conf)
  if conf.cache_ttl == 0 then
    return fetch_value(conf)
  end

  -- kong.cache:get() only calls the function on a cache miss. Values are shared
  -- by all nginx workers. When the function returns an error, nothing is cached.
  local status, err
  local cache_key = PLUGIN_NAME .. ":" .. conf.url .. ":" .. conf.json_field
  local value, cache_err = kong.cache:get(cache_key, { ttl = conf.cache_ttl }, function()
    local v
    v, status, err = fetch_value(conf)
    return v, err
  end)

  if not value then
    return nil, status or 502, err or cache_err
  end
  return value
end


function ExampleExternalCallHandler:access(conf)
  local value, status, err = get_value(conf)

  if not value then
    -- details go to the Kong error log, the client only gets a generic error
    kong.log.err(err)
    return kong.response.error(status)
  end

  kong.service.request.set_header(conf.header_name, value)
end


return ExampleExternalCallHandler
