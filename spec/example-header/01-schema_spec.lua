-- Schema tests: validate plugin configurations without starting Kong.
-- Fast, no database needed. Run only this file with:
--   pongo run ./spec/example-header/01-schema_spec.lua

local PLUGIN_NAME = "example-header"


-- helper: validate a `config` table against the plugin schema, the same way
-- Kong does when the plugin is configured through the Admin API or decK.
-- Returns the full plugin entity (with defaults filled in) or nil + error table.
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins." .. PLUGIN_NAME .. ".schema")

  function validate(config)
    return validate_entity(config, plugin_schema)
  end
end


describe(PLUGIN_NAME .. ": (schema)", function()

  it("accepts an empty config and fills in the defaults", function()
    local entity, err = validate({})
    assert.is_nil(err)
    assert.equal("X-Example-Request", entity.config.request_header)
    assert.equal("X-Example-Response", entity.config.response_header)
    assert.equal("hello from example-header", entity.config.value)
  end)


  it("accepts custom header names and value", function()
    local entity, err = validate({
      request_header = "X-My-Request",
      response_header = "X-My-Response",
      value = "custom",
    })
    assert.is_nil(err)
    assert.equal("X-My-Request", entity.config.request_header)
    assert.equal("custom", entity.config.value)
  end)


  it("rejects a header name with invalid characters", function()
    local entity, err = validate({ request_header = "not a header" })
    assert.is_nil(entity)
    -- errors are reported per field, nested like the config itself
    assert.is_string(err.config.request_header)
  end)


  it("rejects an empty value", function()
    local entity, err = validate({ value = "" })
    assert.is_nil(entity)
    assert.same({ config = { value = "length must be at least 1" } }, err)
  end)


  it("rejects identical request and response header names", function()
    local entity, err = validate({
      request_header = "X-Same",
      response_header = "X-Same",
    })
    assert.is_nil(entity)
    -- entity checks report their errors under "@entity"
    assert.same({
      config = {
        ["@entity"] = {
          "values of these fields must be distinct: 'request_header', 'response_header'",
        },
      },
    }, err)
  end)


  it("has no require() calls in schema.lua (needed for Konnect)", function()
    local path = assert(package.searchpath("kong.plugins." .. PLUGIN_NAME .. ".schema", package.path))
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    -- strip comments first, so mentioning `require()` in a comment is fine
    source = source:gsub("%-%-[^\n]*", "")
    assert.is_nil(source:match("require%s*[%(\"']"), "schema.lua must not use require()")
  end)

end)
