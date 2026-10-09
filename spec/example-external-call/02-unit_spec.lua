-- Unit tests: run the handler with a fake `kong` PDK and a fake HTTP client.
-- No Kong, no network: every response of the "external service" is scripted
-- per test, which makes error cases (timeouts, bad JSON, ...) easy to test.

local PLUGIN_NAME = "example-external-call"


describe(PLUGIN_NAME .. ": (unit)", function()

  local handler
  local http_calls      -- requests the plugin made: { { uri = ..., params = ..., timeout = ... }, ... }
  local http_response   -- what the fake HTTP client returns: { res, err }
  local upstream_headers, error_status, cache_store

  setup(function()
    -- Fake `resty.http`. Putting it in package.loaded makes `require "resty.http"`
    -- in the handler return this table instead of the real library.
    package.loaded["resty.http"] = {
      new = function()
        local timeout
        return {
          set_timeout = function(_, ms) timeout = ms end,
          request_uri = function(_, uri, params)
            table.insert(http_calls, { uri = uri, params = params, timeout = timeout })
            return http_response[1], http_response[2]
          end,
        }
      end,
    }

    -- Fake PDK with only the functions the plugin uses.
    _G.kong = {
      log = {
        err = function() end,
      },
      service = {
        request = {
          set_header = function(name, value) upstream_headers[name] = value end,
        },
      },
      response = {
        error = function(status) error_status = status end,
      },
      -- simple in-memory stand-in for Kong's cache (kong.cache:get)
      cache = {
        get = function(_, key, _, callback)
          if cache_store[key] == nil then
            local value, err = callback()
            if err then return nil, err end
            cache_store[key] = value
          end
          return cache_store[key]
        end,
      },
    }

    -- load the handler after the fakes are in place
    handler = require("kong.plugins." .. PLUGIN_NAME .. ".handler")
  end)

  teardown(function()
    package.loaded["resty.http"] = nil
  end)

  before_each(function()
    http_calls = {}
    http_response = { { status = 200, body = '{"token":"abc123","count":42}' } }
    upstream_headers = {}
    error_status = nil
    cache_store = {}
  end)

  local function config(overrides)
    local conf = {
      url = "http://external.test/token",
      json_field = "token",
      header_name = "X-External-Value",
      timeout = 1000,
      cache_ttl = 0,
      ssl_verify = true,
    }
    for k, v in pairs(overrides or {}) do conf[k] = v end
    return conf
  end


  it("calls the external service and sets the upstream header", function()
    handler:access(config())

    assert.equal(1, #http_calls)
    assert.equal("http://external.test/token", http_calls[1].uri)
    assert.equal("GET", http_calls[1].params.method)
    assert.equal(1000, http_calls[1].timeout)
    assert.same({ ["X-External-Value"] = "abc123" }, upstream_headers)
    assert.is_nil(error_status)
  end)


  it("converts non-string values to strings", function()
    handler:access(config({ json_field = "count" }))
    assert.same({ ["X-External-Value"] = "42" }, upstream_headers)
  end)


  it("returns 504 when the external service times out", function()
    http_response = { nil, "timeout" }
    handler:access(config())
    assert.equal(504, error_status)
    assert.same({}, upstream_headers)
  end)


  it("returns 502 when the external service can't be reached", function()
    http_response = { nil, "connection refused" }
    handler:access(config())
    assert.equal(502, error_status)
  end)


  it("returns 502 when the external service returns an error status", function()
    http_response = { { status = 500, body = "oops" } }
    handler:access(config())
    assert.equal(502, error_status)
  end)


  it("returns 502 when the response is not JSON", function()
    http_response = { { status = 200, body = "<html></html>" } }
    handler:access(config())
    assert.equal(502, error_status)
  end)


  it("returns 502 when the JSON field is missing", function()
    handler:access(config({ json_field = "missing" }))
    assert.equal(502, error_status)
  end)


  describe("with cache_ttl > 0", function()

    it("calls the external service only once", function()
      handler:access(config({ cache_ttl = 60 }))
      handler:access(config({ cache_ttl = 60 }))

      assert.equal(1, #http_calls)
      assert.same({ ["X-External-Value"] = "abc123" }, upstream_headers)
    end)

    it("does not cache failures", function()
      http_response = { nil, "timeout" }
      handler:access(config({ cache_ttl = 60 }))
      assert.equal(504, error_status)

      http_response = { { status = 200, body = '{"token":"later"}' } }
      handler:access(config({ cache_ttl = 60 }))
      assert.equal(2, #http_calls)
      assert.same({ ["X-External-Value"] = "later" }, upstream_headers)
    end)

  end)

end)
