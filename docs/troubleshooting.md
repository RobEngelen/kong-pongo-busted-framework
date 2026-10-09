# Troubleshooting

## Finding out why a test fails

1. **Get the full error message.** The default `gtest` output only lists failures, so rerun with TAP output:
   ```bash
   pongo run -- -o TAP ./spec/my-plugin/10-integration_spec.lua
   ```
2. **Read Kong's log.** Integration tests delete Kong's working folder (`servroot/`) when they finish. Keep it:
   ```bash
   KONG_TEST_DONT_CLEAN=true pongo run ./spec/my-plugin/10-integration_spec.lua
   ```
   Then open `servroot/logs/error.log`; to follow it live, run `pongo tail` in a second terminal. With `scripts/test-plugin.sh`, use `--keep-logs`.
3. **Add logging to your plugin:** `kong.log.err("value: ", some_var)` or `kong.log.inspect(some_table)`. Then repeat step 2.
4. **Try it by hand:** `pongo shell`, then `kms` to start Kong with your plugin, and `curl` against `localhost:8000` / `localhost:8001` inside the shell.

## Common problems

**`bind() to unix:/kong-plugin/servroot/worker_events.sock failed (95: Operation not supported)`**
The plugin folder is on the Windows filesystem (`/mnt/c/...`), where unix sockets can't be created ([kong-pongo#368](https://github.com/Kong/kong-pongo/issues/368)). Clone the plugin inside WSL (`~/GIT/...`), or run `scripts/test-plugin.sh /mnt/c/...`, which tests a copy on the Linux side.

**`pongo: command not found`**
`~/.local/bin` is not on your PATH yet. Open a new terminal (Ubuntu's `~/.profile` adds it once the folder exists), or add `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc`.

**`Cannot connect to the Docker daemon` / `docker: command not found` in WSL**
Start Docker Desktop. Then check that *Settings → Resources → WSL integration* is enabled for your distro.

**`$'\r': command not found` or `bad interpreter: /bin/bash^M`**
A shell script has Windows (CRLF) line endings. Run `git config --global core.autocrlf input`, then re-clone or convert the file with `sed -i 's/\r$//' <file>`.

**`rm: cannot remove 'servroot/...': Permission denied`**
Kong runs as root inside the container, so the files it leaves behind belong to root. Remove them through the container:
```bash
pongo shell rm -rf /kong-plugin/servroot
```
For the staging copies of `scripts/test-plugin.sh`, run `scripts/test-plugin.sh --clean`.

**`'kong config db_export' only works with a database.`**
A leftover `servroot/` from a DB-less run confuses `helpers.make_yaml_file()`. Start `lazy_setup` with `helpers.clean_prefix()`, as the examples do, and use `helpers.stop_kong()` without arguments in `lazy_teardown`. The Kong template's `stop_kong(nil, true)` keeps `servroot/`.

**`plugin 'my-plugin' not enabled; add it to the 'plugins' configuration property`**
Pass `plugins = "bundled," .. PLUGIN_NAME` to `helpers.start_kong`, and `{ PLUGIN_NAME }` as the third argument of `helpers.get_db_utils`. `pongo run` does not enable custom plugins by itself.

**`module 'kong.plugins.my-plugin.handler' not found`**
The folder layout is wrong. It must be `kong/plugins/<name>/handler.lua`, relative to the folder you run `pongo` from.

**My custom Pongo dependency (`.pongo/<name>.yml`) doesn't start**
- The service name must equal the name in `pongorc` (`--<name>`).
- The service needs `networks: [ ${NETWORK_NAME} ]`.
- Check the dependency's own logs with `pongo logs <name>`.

**Tests fail after upgrading Pongo or changing the Kong image**
Rebuild the test image with `pongo build --force`. To start completely fresh, run `pongo clean`, which removes all Pongo containers and images.

**Docker Hub rate limit (`toomanyrequests`)**
Run `docker login`, or set `DOCKER_USERNAME` / `DOCKER_PASSWORD`.

**Builds fail behind a corporate proxy / TLS inspection**
Set `http_proxy` / `https_proxy`. For an inspecting proxy, build with its CA: `pongo build --custom-ca-cert /path/to/ca.crt`.

**The disk fills up**
Each Kong version has its own test image of a few GB.
- `pongo status` shows the images.
- `pongo clean` removes them.
- `docker system prune` cleans up the rest.

## Cleaning up

| Command | What it does |
|---|---|
| `pongo down` | stop this project's test containers (Postgres, httpbin, …) |
| `pongo down --all` | stop the test containers of all projects |
| `pongo clean` | remove all Pongo containers, networks and test images |
| `scripts/test-plugin.sh --clean` | remove the staging copies of Windows-side plugins |
