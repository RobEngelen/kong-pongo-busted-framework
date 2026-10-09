-- Configuration schema of the plugin.
-- No `require()` calls, so the schema can also be uploaded to Konnect.

local PLUGIN_NAME = "example-external-call"

return {
  name = PLUGIN_NAME,
  fields = {
    { config = {
        type = "record",
        fields = {
          { url = {
              description = "URL of the external service, called with an HTTP GET.",
              type = "string",
              required = true,
              match = "^https?://",
          } },
          { json_field = {
              description = "Field in the JSON response of the external service whose value is forwarded.",
              type = "string",
              required = true,
          } },
          { header_name = {
              description = "Header on the upstream request that receives the value.",
              type = "string",
              required = true,
              default = "X-External-Value",
              match = "^[%w%-]+$",
          } },
          { timeout = {
              description = "Timeout for the call to the external service, in milliseconds.",
              type = "integer",
              required = true,
              default = 2000,
              between = { 1, 60000 },
          } },
          { cache_ttl = {
              description = "Seconds to cache the value in Kong's cache. 0 disables caching.",
              type = "integer",
              required = true,
              default = 0,
              between = { 0, 86400 },
          } },
          { ssl_verify = {
              description = "Verify the TLS certificate of the external service (https only).",
              type = "boolean",
              required = true,
              default = true,
          } },
        },
      },
    },
  },
}
