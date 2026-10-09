-- LuaCheck configuration, used by: pongo lint
std             = "ngx_lua"
unused_args     = false
redefined       = false
max_line_length = false


include_files = {
  "**/*.lua",
  "*.rockspec",
  ".busted",
  ".luacheckrc",
}


exclude_files = {
  "servroot*/**",   -- Kong test prefix created by the integration tests
}


globals = {
  "_KONG",
  "kong",
  "ngx.IS_CLI",
}


not_globals = {
  "string.len",
  "table.getn",
}


ignore = {
  "6.", -- ignore whitespace warnings
}


files["spec/**/*.lua"] = {
  std = "ngx_lua+busted",
}
