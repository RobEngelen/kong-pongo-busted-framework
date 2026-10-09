-- Schema tests: validate plugin configurations without starting Kong.

local PLUGIN_NAME = "example-external-call"


local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins." .. PLUGIN_NAME .. ".schema")

  function validate(config)
    return validate_entity(config, plugin_schema)
  end
end


describe(PLUGIN_NAME .. ": (schema)", function()

  it("accepts a minimal config and fills in the defaults", function()
    local entity, err = validate({ url = "http://example.test/token", json_field = "token" })
    assert.is_nil(err)
    assert.same({
      url = "http://example.test/token",
      json_field = "token",
      header_name = "X-External-Value",
      timeout = 2000,
      cache_ttl = 0,
      ssl_verify = true,
    }, entity.config)
  end)


  it("requires url and json_field", function()
    local entity, err = validate({})
    assert.is_nil(entity)
    assert.same({
      config = {
        url = "required field missing",
        json_field = "required field missing",
      },
    }, err)
  end)


  it("only accepts http(s) URLs", function()
    local entity, err = validate({ url = "ftp://example.test", json_field = "token" })
    assert.is_nil(entity)
    assert.is_string(err.config.url)
  end)


  it("rejects a timeout outside 1-60000 ms", function()
    local _, err = validate({ url = "http://example.test", json_field = "x", timeout = 0 })
    assert.same({ config = { timeout = "value should be between 1 and 60000" } }, err)
  end)


  it("rejects a negative cache_ttl", function()
    local _, err = validate({ url = "http://example.test", json_field = "x", cache_ttl = -1 })
    assert.same({ config = { cache_ttl = "value should be between 0 and 86400" } }, err)
  end)


  it("has no require() calls in schema.lua (needed for Konnect)", function()
    local path = assert(package.searchpath("kong.plugins." .. PLUGIN_NAME .. ".schema", package.path))
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    source = source:gsub("%-%-[^\n]*", "")
    assert.is_nil(source:match("require%s*[%(\"']"), "schema.lua must not use require()")
  end)

end)
