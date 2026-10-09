-- Unit tests: call the handler functions directly, with a fake `kong` PDK.
-- No Kong, no database, very fast. Good for testing your plugin logic in
-- isolation. Run only this file with:
--   pongo run ./spec/example-header/02-unit_spec.lua

local PLUGIN_NAME = "example-header"


describe(PLUGIN_NAME .. ": (unit)", function()

  local handler
  local request_headers, response_headers

  setup(function()
    -- Replace the global `kong` PDK with a minimal fake that records what the
    -- plugin does. Only the PDK functions the plugin uses need to exist.
    -- Busted restores globals after this file, so other spec files are not affected.
    _G.kong = {
      log = {
        debug = function() end,
      },
      service = {
        request = {
          set_header = function(name, value)
            request_headers[name] = value
          end,
        },
      },
      response = {
        set_header = function(name, value)
          response_headers[name] = value
        end,
      },
    }

    -- load the plugin code *after* the fake PDK is in place
    handler = require("kong.plugins." .. PLUGIN_NAME .. ".handler")
  end)


  before_each(function()
    -- start every test with a clean slate
    request_headers = {}
    response_headers = {}
  end)


  it("sets the request header in the access phase", function()
    handler:access({ request_header = "X-Req", response_header = "X-Resp", value = "v1" })

    assert.same({ ["X-Req"] = "v1" }, request_headers)
    assert.same({}, response_headers)
  end)


  it("sets the response header in the header_filter phase", function()
    handler:header_filter({ request_header = "X-Req", response_header = "X-Resp", value = "v2" })

    assert.same({}, request_headers)
    assert.same({ ["X-Resp"] = "v2" }, response_headers)
  end)


  it("declares a priority and a version", function()
    assert.is_number(handler.PRIORITY)
    assert.matches("^%d+%.%d+%.%d+", handler.VERSION)
  end)

end)
