-- Request/response handling of the plugin.
--
-- Kong calls the functions below in the matching nginx phase, passing the plugin
-- configuration (validated against schema.lua, defaults filled in) as `conf`.
-- All interaction with Kong goes through the PDK (the global `kong` table):
-- https://developer.konghq.com/gateway/pdk/reference/

local ExampleHeaderHandler = {
  PRIORITY = 1000,   -- plugins with a higher priority run first
  VERSION = "0.1.0", -- keep in sync with the rockspec
}


-- access: runs for every request, before it is proxied to the upstream service
function ExampleHeaderHandler:access(conf)
  kong.log.debug("adding request header ", conf.request_header)
  kong.service.request.set_header(conf.request_header, conf.value)
end


-- header_filter: runs when the response headers are received from the upstream service
function ExampleHeaderHandler:header_filter(conf)
  kong.response.set_header(conf.response_header, conf.value)
end


return ExampleHeaderHandler
