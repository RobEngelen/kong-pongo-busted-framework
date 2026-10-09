-- Integration tests against a real Kong and a mocked external service.
--
-- The "external service" is go-httpbin, started by Pongo as a custom dependency
-- (see .pongo/pongorc and .pongo/httpbin.yml). Inside the test network it is
-- reachable as http://httpbin:8080. Useful endpoints:
--   /uuid             -> {"uuid": "<random uuid>"}  (new value on every call)
--   /status/<code>    -> responds with that HTTP status
--   /delay/<seconds>  -> responds after a delay
--   /html             -> a non-JSON response

local helpers = require "spec.helpers"

local PLUGIN_NAME = "example-external-call"
local HTTPBIN = "http://httpbin:8080"
local UUID_PATTERN = "^%x+%-%x+%-%x+%-%x+%-%x+$"


for _, strategy in helpers.all_strategies() do

  describe(PLUGIN_NAME .. ": (integration) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      helpers.clean_prefix()
      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      -- one route per scenario, each with its own plugin configuration
      local function add_route(host, config)
        local route = bp.routes:insert({ hosts = { host } })
        bp.plugins:insert {
          name = PLUGIN_NAME,
          route = { id = route.id },
          config = config,
        }
      end

      add_route("ok.test",         { url = HTTPBIN .. "/uuid", json_field = "uuid" })
      add_route("cached.test",     { url = HTTPBIN .. "/uuid", json_field = "uuid", cache_ttl = 60 })
      add_route("error.test",      { url = HTTPBIN .. "/status/500", json_field = "uuid" })
      add_route("slow.test",       { url = HTTPBIN .. "/delay/2", json_field = "uuid", timeout = 500 })
      add_route("unreachable.test",{ url = "http://httpbin:9/", json_field = "uuid", timeout = 1000 })
      add_route("not-json.test",   { url = HTTPBIN .. "/html", json_field = "uuid" })
      add_route("no-field.test",   { url = HTTPBIN .. "/uuid", json_field = "does-not-exist" })

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. PLUGIN_NAME,
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)


    -- sends a request through Kong and returns the response
    local function get(host)
      return client:get("/request", { headers = { host = host } })
    end


    describe("when the external service responds", function()

      it("forwards the JSON field to the upstream as a header", function()
        local r = get("ok.test")
        assert.response(r).has.status(200)
        local value = assert.request(r).has.header("X-External-Value")
        assert.matches(UUID_PATTERN, value)
      end)

      it("calls the external service on every request without caching", function()
        local first = assert.request(get("ok.test")).has.header("X-External-Value")
        local second = assert.request(get("ok.test")).has.header("X-External-Value")
        assert.not_equal(first, second)
      end)

      it("reuses the cached value when cache_ttl is set", function()
        local first = assert.request(get("cached.test")).has.header("X-External-Value")
        local second = assert.request(get("cached.test")).has.header("X-External-Value")
        assert.equal(first, second)
      end)

    end)


    describe("when the external service fails", function()

      it("returns 502 on an error status", function()
        assert.response(get("error.test")).has.status(502)
      end)

      it("returns 504 on a timeout, without waiting for the slow response", function()
        ngx.update_time()
        local started = ngx.now()
        assert.response(get("slow.test")).has.status(504)
        ngx.update_time()
        assert.is_true(ngx.now() - started < 1.5, "should give up after the 500ms timeout")
      end)

      it("returns 502 when the service is unreachable", function()
        assert.response(get("unreachable.test")).has.status(502)
      end)

      it("returns 502 on a non-JSON response", function()
        assert.response(get("not-json.test")).has.status(502)
      end)

      it("returns 502 when the JSON field is missing", function()
        assert.response(get("no-field.test")).has.status(502)
      end)

    end)

  end)

end
