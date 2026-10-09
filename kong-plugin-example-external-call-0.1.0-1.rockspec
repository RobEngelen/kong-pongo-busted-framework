local plugin_name = "example-external-call"
local package_name = "kong-plugin-" .. plugin_name
local package_version = "0.1.0"
local rockspec_revision = "1"

package = package_name
version = package_version .. "-" .. rockspec_revision
supported_platforms = { "linux", "macosx" }
source = {
  -- Only used when installing from a remote location; `pongo pack` / `luarocks make` build from the local files.
  url = "git+https://github.com/RobEngelen/kong-pongo-busted-framework.git",
}

description = {
  summary = "Example Kong plugin: calls an external HTTP service and forwards a value from its JSON response to the upstream.",
}

dependencies = {
  -- Lua dependencies of your plugin go here, e.g. "lua-resty-jwt >= 0.2.3".
  -- Pongo installs them (`luarocks install --only-deps`) when the test container starts.
  -- Libraries that ship with Kong (lua-resty-http, lua-cjson, penlight, ...) must NOT be listed.
}

build = {
  type = "builtin",
  modules = {
    -- every Lua file of the plugin must be listed here
    ["kong.plugins." .. plugin_name .. ".handler"] = "kong/plugins/" .. plugin_name .. "/handler.lua",
    ["kong.plugins." .. plugin_name .. ".schema"]  = "kong/plugins/" .. plugin_name .. "/schema.lua",
  },
}
