# kong-pongo-busted-framework

A ready-to-use setup for testing **custom Kong Gateway plugins**. Clone it and run the example tests in minutes, then test your own plugins the same way.

- **[Pongo](https://github.com/Kong/kong-pongo)** starts a throw-away Kong (plus Postgres and mock services) in Docker.
- **[busted](https://lunarmodules.github.io/busted/)** runs the tests (`spec/**/*_spec.lua`), using Kong's own test helpers.
- **Isolated:** it is fully separate from your real gateways. Nothing connects to them.
- **Topologies:** every integration test runs twice, against Kong with a database and against DB-less Kong (the mode hybrid data planes and Konnect use).

```
 your machine (WSL2 / Linux / macOS)
 ┌──────────────────────────────────────────────────────────────┐
 │  pongo run                                                   │
 │    │                                                         │
 │    ▼  Docker                                                 │
 │  ┌───────────────────────────┐   ┌──────────┐  ┌──────────┐  │
 │  │ Kong test container       │──▶│ postgres │  │ httpbin  │  │
 │  │  - your plugin (mounted)  │   └──────────┘  │ (mock)   │  │
 │  │  - busted + spec.helpers  │────────────────▶└──────────┘  │
 │  └───────────────────────────┘                               │
 └──────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

| | |
|---|---|
| **Docker** | Docker Desktop (Windows/macOS) or Docker Engine (Linux), with `docker compose` |
| **Windows** | WSL2 with Docker Desktop's *WSL integration* turned on for your distro |
| **Tools** | `git`, `curl`, `realpath`, `md5sum` (coreutils), `bash` |
| **Disk** | about 4 GB per Kong version (test image), plus Postgres |

`scripts/setup.sh` checks all of these for you. For step-by-step Windows/WSL2 setup, see **[docs/prerequisites.md](docs/prerequisites.md)**.

> **WSL2 users:** clone this repo (and your plugins) **inside WSL**, e.g. `~/GIT/`, *not* under `/mnt/c/...`. Kong's integration tests don't work on the Windows filesystem. `scripts/test-plugin.sh` handles plugins that are on `/mnt/c` for you.

## Quick start

```bash
git clone https://github.com/RobEngelen/kong-pongo-busted-framework.git ~/GIT/kong-pongo-busted-framework
```
```bash
cd ~/GIT/kong-pongo-busted-framework
```
```bash
scripts/setup.sh
```
```bash
pongo run
```

- **`scripts/setup.sh`** checks the prerequisites and installs Pongo (pinned version) into `~/.local/share/kong-pongo`, linked as `~/.local/bin/pongo`. If it says `pongo` is not on your PATH yet, open a new terminal.
- **`pongo run`** builds the Kong test image the first time, which takes a few minutes. After that it runs every spec file in `spec/`. Expect `[ PASSED ] 48 tests`.

When you're done for the day, stop the test containers:

```bash
pongo down
```

---

## Testing your own plugin

A plugin project has this layout (it's what Kong and Pongo expect):

```
kong/plugins/<name>/handler.lua         request/response logic (required)
kong/plugins/<name>/schema.lua          configuration schema (required)
spec/<name>/*_spec.lua                  tests
kong-plugin-<name>-<version>.rockspec   packaging + Lua dependencies
.pongo/pongorc                          which services Pongo starts (optional)
```

### Option A: work inside this repo

Start a new plugin from the example, or copy an existing plugin into `kong/plugins/<name>` and `spec/<name>`:

```bash
scripts/new-plugin.sh custom-my-plugin
```
```bash
pongo run ./spec/custom-my-plugin
```

Plugins you add here are **ignored by git**, so customer code can't be committed to this shared repo by accident. Only `example-*` plugins are tracked.

### Option B: test a plugin that lives in its own repo

```bash
scripts/test-plugin.sh ~/GIT/my-plugin-repo
```
```bash
scripts/test-plugin.sh /mnt/c/Users/me/repos/KongCustomization/plugins/*
```

- It accepts one or more plugin project folders; Windows paths like `C:\...` work too.
- Folders on the Windows filesystem are first copied to `~/.cache/kong-pongo-framework/stage/`; the original is never changed.
- Busted options go after `--`: `scripts/test-plugin.sh ~/GIT/my-plugin -- --tags=off`

To create a new standalone plugin project: `scripts/new-plugin.sh custom-my-plugin --dir ~/GIT/custom-my-plugin`.

---

## Everyday commands

Run these from the plugin project root: this repo, or your plugin repo.

| What | Command |
|---|---|
| Run all tests | `pongo run` |
| Run one plugin / one file | `pongo run ./spec/example-header` · `pongo run ./spec/example-header/02-unit_spec.lua` |
| Only DB-less (or only Postgres) | `pongo run -- --tags=off ./spec/example-header` (busted options **before** the paths) |
| Keep Kong's log after the tests | `KONG_TEST_DONT_CLEAN=true pongo run` → `servroot/logs/error.log` |
| Unit-test coverage | `pongo run -- --coverage` → `luacov.report.out` |
| Lint (luacheck) | `pongo lint` |
| Shell in the Kong container | `pongo shell`, then `kms` (start Kong with migrations) or `kdbl` (start DB-less) |
| Expose Kong on localhost:8000/8001 | `pongo up --expose`, then start Kong in `pongo shell` |
| Follow the Kong log | `pongo tail` |
| Stop / remove containers | `pongo down` · `pongo clean` (also removes the test images) |

## The examples

| Plugin | Shows |
|---|---|
| [`example-header`](kong/plugins/example-header) | Kong's tutorial plugin. Adds a configurable header to the upstream request and to the response. Covers schema validation, unit tests with a fake PDK, and integration tests against Kong's echo upstream. |
| [`example-external-call`](kong/plugins/example-external-call) | Calls an external HTTP service (`lua-resty-http`), forwards a JSON field as a header, and caches it with `kong.cache`, which is the pattern behind token plugins. The external service is mocked by a [Pongo custom dependency](.pongo/httpbin.yml), with tests for timeouts, error codes and caching. |

Each plugin has three spec files:

| File | Contains |
|---|---|
| `01-schema_spec.lua` | configuration validation (fast, no Kong) |
| `02-unit_spec.lua` | handler logic with a fake `kong` PDK (fast, no Kong) |
| `10-integration_spec.lua` | a real Kong, with real requests, for `postgres` and `off` (DB-less) |

How to write these tests, mock services and use the helpers: **[docs/writing-tests.md](docs/writing-tests.md)**.

## Kong versions and Enterprise

- **Default:** Pongo tests against **Kong 3.9.2**, the last open-source release. No license is needed.
- **Another version:** set `KONG_VERSION`. Run `pongo status versions` to list the available versions. For example:

```bash
KONG_VERSION=3.9.x pongo run
```
```bash
KONG_VERSION=3.10.0.14 pongo run
```

- **Enterprise:** versions with four parts (`3.10.0.14`) are Kong Enterprise (`kong/kong-gateway`). The examples pass on 3.10.0.14 **without a license**. If your plugin uses Enterprise-only features, pass a license with `KONG_LICENSE_DATA="$(cat ~/kong-license.json)"`. Never commit it; `*license*.json` is git-ignored.
- **Your company's image:** test against it with `KONG_IMAGE=<image>`.

See **[docs/topologies.md](docs/topologies.md)**.

## Topologies

| Topology | Covered by |
|---|---|
| Traditional (Kong + Postgres) | `[#postgres]` tests |
| DB-less (declarative config) | `[#off]` tests |
| Hybrid mode, data plane | `[#off]` tests: a DP runs DB-less, so `kong.db` is not available |
| Hybrid mode, control plane | schema tests: the CP only validates configuration |
| Konnect | schema tests also check that `schema.lua` has no `require()`. No custom DAOs, `api.lua` or migrations. |

The details, plus how to write a real CP/DP test, are in **[docs/topologies.md](docs/topologies.md)**.

## Troubleshooting

| Problem | Fix |
|---|---|
| `bind() to unix:/kong-plugin/servroot/... failed (95: Operation not supported)` | The plugin is on `/mnt/c`. Move it into WSL, or use `scripts/test-plugin.sh`. |
| `pongo: command not found` | Open a new terminal, or add `~/.local/bin` to your PATH. |
| `$'\r': command not found` | Windows line endings. Run `git config --global core.autocrlf input` and re-clone. |
| `rm: cannot remove 'servroot/...': Permission denied` | Those files were created by root in the container: `pongo shell rm -rf /kong-plugin/servroot`. |
| A test fails and you need Kong's log | `KONG_TEST_DONT_CLEAN=true pongo run ...`, then read `servroot/logs/error.log`. |

More: **[docs/troubleshooting.md](docs/troubleshooting.md)**.

## Repository layout

```
.pongo/pongorc                      services Pongo starts: postgres + httpbin
.pongo/httpbin.yml                  the httpbin mock service (Pongo custom dependency)
.busted .luacov .luacheckrc         busted, coverage and lint settings
kong/plugins/example-*/             example plugins
spec/example-*/                     their tests
kong-plugin-example-*.rockspec      their rockspecs
scripts/setup.sh                    prerequisites check + Pongo install
scripts/new-plugin.sh               scaffold a new plugin
scripts/test-plugin.sh              test plugin repos outside this one (handles /mnt/c)
docs/                               setup, test writing, topologies, troubleshooting
```

## Resources

- Kong plugins: [plugin entity](https://developer.konghq.com/gateway/entities/plugin/) · [custom plugins](https://developer.konghq.com/custom-plugins/) · [custom plugin reference](https://developer.konghq.com/custom-plugins/reference/) · [PDK reference](https://developer.konghq.com/gateway/pdk/reference/)
- Kong's custom plugin tutorial:
  1. [set up a plugin project](https://developer.konghq.com/custom-plugins/get-started/set-up-plugin-project/)
  2. [add plugin testing](https://developer.konghq.com/custom-plugins/get-started/add-plugin-testing/)
  3. [add configuration](https://developer.konghq.com/custom-plugins/get-started/add-plugin-configuration/)
  4. [consume external services](https://developer.konghq.com/custom-plugins/get-started/consume-external-services/)
  5. [add metrics](https://developer.konghq.com/custom-plugins/get-started/add-metrics/)
  6. [deploy with Docker](https://developer.konghq.com/custom-plugins/get-started/deploy-plugins/)
- Tools: [Pongo](https://github.com/Kong/kong-pongo) · [busted](https://lunarmodules.github.io/busted/) · [Kong test helpers source](https://github.com/Kong/kong/blob/master/spec/helpers.lua) · [Kong plugin template](https://github.com/Kong/kong-plugin)
