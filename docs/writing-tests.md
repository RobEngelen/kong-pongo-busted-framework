# Writing plugin tests

Tests are [busted](https://lunarmodules.github.io/busted/) spec files in `spec/<plugin-name>/`, with names ending in `_spec.lua`. Pongo runs them inside a container that has Kong, its test helpers (`require "spec.helpers"`) and your plugin. The example plugins in this repo are commented as worked examples, so start there.

## Spec layout

| File | Speed | What it tests |
|---|---|---|
| `01-schema_spec.lua` | ms | Configuration validation: defaults, required fields, invalid values |
| `02-unit_spec.lua` | ms | Handler logic, with a fake `kong` PDK and fake libraries |
| `10-integration_spec.lua` | seconds | A real Kong with your plugin, receiving real HTTP requests |

- Files run in alphabetical order, so the numbers keep the fast tests first.
- Each file is isolated: globals and `package.loaded` changes made in one spec file are undone before the next one.

## Running a subset

```bash
pongo run ./spec/example-header
```
```bash
pongo run ./spec/example-header/02-unit_spec.lua
```
```bash
pongo run -- --tags=off ./spec/example-header
```
```bash
pongo run -- --filter="caching" ./spec
```

- The first runs one plugin, the second a single file.
- `--tags=off` runs only the DB-less tests; `--tags=postgres` runs only the Postgres ones.
- `--filter` runs only tests whose name matches.
- **Busted options go before the paths.** `pongo run ./spec/x -- --tags=off` silently runs everything.
- `pongo run -- --help` lists all busted options.

## Schema tests

`validate_plugin_config_schema` validates a `config` table the same way Kong does for the Admin API and decK. It returns the full plugin entity with defaults filled in, or `nil` plus an error table:

```lua
local validate_entity = require("spec.helpers").validate_plugin_config_schema
local schema = require("kong.plugins.my-plugin.schema")

local entity, err = validate_entity({ url = "http://x.test" }, schema)
-- err = { config = { json_field = "required field missing" } }
```

## Unit tests

- Replace the global `kong` with a fake that has only the PDK functions your plugin uses, and that records what the plugin does.
- To fake a library, put a table in `package.loaded["<module>"]`. For example, set `package.loaded["resty.http"]` to a fake whose responses each test scripts.
- **Do both before you `require` the handler.**

```lua
setup(function()
  package.loaded["resty.http"] = { new = function() return fake_client end }
  _G.kong = {
    log = { err = function() end },
    service = { request = { set_header = function(k, v) headers[k] = v end } },
    response = { error = function(status) error_status = status end },
  }
  handler = require("kong.plugins.my-plugin.handler")
end)
```

See `spec/example-external-call/02-unit_spec.lua` for a complete example. It fakes `resty.http` and `kong.cache`, and covers timeouts, error responses and caching.

## Integration tests

Every integration spec follows this pattern. The parts marked `-- !` are required:

```lua
local helpers = require "spec.helpers"
local PLUGIN_NAME = "my-plugin"

for _, strategy in helpers.all_strategies() do          -- "postgres" and "off" (DB-less)
  describe(PLUGIN_NAME .. " [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      helpers.clean_prefix()                             -- ! remove leftovers of earlier runs
      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy,
                                      nil, { PLUGIN_NAME })            -- ! plugin name
      local route = bp.routes:insert({ hosts = { "test.test" } })
      bp.plugins:insert({ name = PLUGIN_NAME, route = { id = route.id }, config = {} })

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. PLUGIN_NAME,             -- ! Pongo doesn't enable it for you
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }))
    end)

    lazy_teardown(function() helpers.stop_kong() end)
    before_each(function() client = helpers.proxy_client() end)
    after_each(function() if client then client:close() end end)

    it("does something", function()
      local r = client:get("/request", { headers = { host = "test.test" } })
      assert.response(r).has.status(200)
    end)
  end)
end
```

- **DB-less:** entities are created in Postgres with the blueprint (`bp`). `make_yaml_file()` then exports them to a declarative config, which the DB-less Kong loads.
- **Echo upstream:** a route without a service points to Kong's built-in mock upstream. It echoes the request back, so `assert.request(r)` can check what your plugin sent upstream. Mock upstream endpoints:

  | Endpoint | Behaviour |
  |---|---|
  | `/request`, `/anything` | echo the request |
  | `/status/<code>` | respond with that status |
  | `/delay/<seconds>` | respond after a delay |
  | `/response-headers?X-Foo=bar` | set response headers |

### Blueprint cheat-sheet

```lua
local service  = bp.services:insert({ name = "svc", host = "httpbin", port = 8080, protocol = "http" })
local route    = bp.routes:insert({ service = { id = service.id }, paths = { "/svc" } })
local consumer = bp.consumers:insert({ username = "alice" })
bp.keyauth_credentials:insert({ key = "alice-key", consumer = { id = consumer.id } })
bp.plugins:insert({ name = "key-auth", route = { id = route.id } })   -- bundled plugins work too
bp.plugins:insert({ name = PLUGIN_NAME, route = { id = route.id }, config = { ... } })
```

### Clients and assertions

| | |
|---|---|
| `helpers.proxy_client()` | requests through Kong's proxy (port 9000) |
| `helpers.admin_client()` | Kong's Admin API (port 9001), read-only in DB-less mode |
| `client:get(path, { headers = {...} })` | also `client:post`, `client:send({ method, path, headers, body })` |
| `assert.response(r).has.status(200)` | checks the status, returns the body |
| `assert.res_status(200, r)` | same, shorter |
| `assert.response(r).has.header("X-Foo")` | returns the header value |
| `assert.response(r).has.no.header("X-Foo")` | |
| `assert.response(r).has.jsonbody()` | returns the decoded JSON body |
| `assert.request(r).has.header("X-Foo")` | header the *upstream* received (echo upstream only) |
| `helpers.wait_until(fn, timeout)` / `assert.eventually(fn)...` | wait for something asynchronous |

The helper source, with docs: <https://github.com/Kong/kong/blob/master/spec/helpers.lua>, or run `pongo docs`.

## Mocking external services

These options go from lightest to heaviest:

1. **Fake library in unit tests.** Use `package.loaded["resty.http"] = ...` as shown above. It's the fastest way to test error paths.
2. **Kong's mock upstream.** Point your plugin at `helpers.mock_upstream_url .. "/status/500"` and the other endpoints listed earlier. There is nothing to set up.
3. **`spec.helpers.http_mock`.** Starts a small nginx inside the test container with responses you script, and records the requests it receives. It's good for faking a token endpoint.
4. **A Pongo dependency.** Any Docker image becomes a service in the test network. This repo uses go-httpbin as `http://httpbin:8080`; see [.pongo/httpbin.yml](../.pongo/httpbin.yml). To add your own (WireMock, Keycloak, …):
   - Create `.pongo/<name>.yml` with one service called `<name>` on network `${NETWORK_NAME}`.
   - Add `--<name>` to `.pongo/pongorc`.
   - Reach it from Kong as `http://<name>:<port>`.

   Built-in dependencies you can switch on in `pongorc`: `--redis` (`redis:6379`), `--squid` (forward proxy `squid:3128`) and `--grpcbin`.

Don't call real external services (identity providers, SaaS APIs) from tests. Those tests break when credentials expire or the network changes, and they leak secrets into the repo.

## Dependencies, files and environment variables

- **Lua libraries.** List them in the rockspec under `dependencies`. Pongo installs them when the container starts. Don't list libraries that ship with Kong (`lua-resty-http`, `lua-cjson`, `penlight`, `lua-resty-openssl`, …).
- **Setup hook.** `.pongo/pongo-setup.sh` is sourced inside the container before the tests run, and it **replaces** the default dependency install. To keep that install, end the hook with `. /pongo/default-pongo-setup.sh`. A second hook, `.pongo/pongo-setup-host.sh`, runs on your machine before the container starts.
- **Test files** such as keys, certificates and JSON fixtures go in `spec/fixtures/<plugin>/`. Inside the container your project is mounted at `/kong-plugin`, and tests run from `/kong`. So use absolute paths like `/kong-plugin/spec/fixtures/my-plugin/key.pem`. Never commit real keys or passwords.
- **Environment variables** from your shell are not passed to the tests, except `KONG_LICENSE_DATA`, `KONG_TEST_DONT_CLEAN` and the proxy variables. Export anything else in `.pongo/pongo-setup.sh`.

## Coverage, lint and reports

```bash
pongo run -- --coverage
```
```bash
pongo lint
```
```bash
pongo run -- -o TAP
```
```bash
pongo run -- -o junit -Xoutput /kong-plugin/junit.xml
```

- `--coverage` writes `luacov.report.out`. It measures unit tests only; code running inside Kong isn't measured.
- `pongo lint` runs luacheck with the settings in `.luacheckrc`.
- `-o TAP` shows full error messages for failures that the default `gtest` output abbreviates.
- `-o junit` produces a JUnit report (`junit.xml` in the project root), useful in CI later.
