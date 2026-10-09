-- Integration tests: start a real Kong with the plugin enabled and send it
-- HTTP requests. Run only this file with:
--   pongo run ./spec/example-header/10-integration_spec.lua
--
-- Kong's test helpers ("spec.helpers") come with Kong itself; Pongo makes them
-- available. Source: https://github.com/Kong/kong/blob/master/spec/helpers.lua

local helpers = require "spec.helpers"

local PLUGIN_NAME = "example-header"


-- Run every test once per strategy (= deployment topology):
--   "postgres" : traditional mode, Kong with a database
--   "off"      : DB-less mode, Kong with a declarative config (also what a
--                data plane in hybrid mode / Konnect runs)
-- Run a single strategy with its tag, e.g.: pongo run -- --tags=off ./spec/example-header
for _, strategy in helpers.all_strategies() do

  describe(PLUGIN_NAME .. ": (integration) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      -- Remove the Kong prefix (./servroot) left behind by an earlier run.
      -- make_yaml_file() below would otherwise pick up its old settings.
      helpers.clean_prefix()

      -- get_db_utils returns a "blueprint" (bp) to create Kong entities.
      -- It also resets the database, so every spec file starts clean.
      -- For DB-less we still use postgres to *build* the config, and then
      -- export it to a declarative file below (make_yaml_file).
      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      -- A route without a service gets a default service that points to the
      -- mock upstream started by the test nginx template. That upstream echoes
      -- the request it received, so we can check what the plugin sent to it.

      -- route 1: plugin with the default configuration
      local route1 = bp.routes:insert({ hosts = { "default.test" } })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {},
      }

      -- route 2: plugin with a custom configuration
      local route2 = bp.routes:insert({ hosts = { "custom.test" } })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route2.id },
        config = {
          request_header = "X-Custom-Request",
          response_header = "X-Custom-Response",
          value = "custom value",
        },
      }

      -- route 3: no plugin at all
      bp.routes:insert({ hosts = { "no-plugin.test" } })

      assert(helpers.start_kong({
        database = strategy,
        -- test template that also starts the mock upstream
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- `pongo run` does not enable custom plugins by itself: list it here
        plugins = "bundled," .. PLUGIN_NAME,
        -- DB-less: write the entities created above to a declarative config file
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }))
    end)

    lazy_teardown(function()
      -- stops Kong and deletes ./servroot; to keep the logs for debugging, run:
      --   KONG_TEST_DONT_CLEAN=true pongo run ...   (log: ./servroot/logs/error.log)
      helpers.stop_kong()
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)


    describe("with the default config", function()

      it("adds the request header sent to the upstream", function()
        local r = client:get("/request", { headers = { host = "default.test" } })
        assert.response(r).has.status(200)
        -- assert.request() inspects the request as echoed back by the mock upstream
        local value = assert.request(r).has.header("X-Example-Request")
        assert.equal("hello from example-header", value)
      end)

      it("adds the response header returned to the client", function()
        local r = client:get("/request", { headers = { host = "default.test" } })
        assert.response(r).has.status(200)
        local value = assert.response(r).has.header("X-Example-Response")
        assert.equal("hello from example-header", value)
      end)

    end)


    describe("with a custom config", function()

      it("uses the configured header names and value", function()
        local r = client:get("/request", { headers = { host = "custom.test" } })
        assert.response(r).has.status(200)
        assert.equal("custom value", assert.request(r).has.header("X-Custom-Request"))
        assert.equal("custom value", assert.response(r).has.header("X-Custom-Response"))
        assert.request(r).has.no.header("X-Example-Request")
        assert.response(r).has.no.header("X-Example-Response")
      end)

    end)


    describe("without the plugin", function()

      it("does not add any header", function()
        local r = client:get("/request", { headers = { host = "no-plugin.test" } })
        assert.response(r).has.status(200)
        assert.request(r).has.no.header("X-Example-Request")
        assert.response(r).has.no.header("X-Example-Response")
      end)

    end)

  end)

end
