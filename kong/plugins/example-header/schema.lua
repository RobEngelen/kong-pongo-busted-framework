-- Configuration schema of the plugin.
--
-- This schema deliberately has no `require()` calls (no `kong.db.schema.typedefs`),
-- because Konnect only accepts self-contained schemas. Kong Gateway itself would
-- also accept typedefs such as `typedefs.header_name`.

local PLUGIN_NAME = "example-header"

return {
  name = PLUGIN_NAME,
  fields = {
    { config = {
        type = "record",
        fields = {
          { request_header = {
              description = "Header added to the request that is sent to the upstream service.",
              type = "string",
              required = true,
              default = "X-Example-Request",
              match = "^[%w%-]+$",   -- letters, digits and dashes
          } },
          { response_header = {
              description = "Header added to the response that is returned to the client.",
              type = "string",
              required = true,
              default = "X-Example-Response",
              match = "^[%w%-]+$",
          } },
          { value = {
              description = "Value of both headers.",
              type = "string",
              required = true,
              default = "hello from example-header",
              len_min = 1,
          } },
        },
        -- entity checks validate combinations of fields
        entity_checks = {
          { distinct = { "request_header", "response_header" } },
        },
      },
    },
  },
}
