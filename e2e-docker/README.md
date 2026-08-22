# Docker End-to-End Tests

This directory verifies TypstRails behaves correctly across real, isolated
environments using Docker -- things the unit test suite can't cover because
it mocks the compilation step and always runs in one Ruby process with
whatever happens to be installed on the host.

Specifically, it answers two questions:

1. **Backend matrix**: does `TypstRails::Backends::Registry.resolve(:auto)`
   pick the right compilation backend in every combination of "is the `typst`
   gem installed" x "is the Typst CLI installed" -- including the case where
   neither is available, which should fail with a clear error instead of a
   confusing one?
2. **Fresh install**: does the gem actually work when installed the way a
   real user installs it (`gem build` + `gem install`, picking up only
   `spec.files`), rather than loaded straight out of the working tree via a
   Bundler `path:` dependency the way every other test in this repo runs it?

## Prerequisites

Docker and Docker Compose (`docker compose`, the v2 plugin syntax).

## Scenarios

| Service         | Typst CLI | `typst` gem | Expected backend           |
|------------------|:---------:|:-----------:|-----------------------------|
| `cli-only`       | yes       | no          | `:cli`                       |
| `gem-only`       | no        | yes         | `:gem`                       |
| `both`           | yes       | yes         | `:gem` (preferred over CLI)  |
| `neither`        | no        | no          | fails with `TypstRails::Error` |
| `fresh-install`  | yes       | no          | gem built + installed like a real release, then rendered |

Each backend-matrix service builds a minimal Debian-based image, bundles
TypstRails via a `path:` Gemfile pointing at the repo root (`Gemfile.cli-only`
/ `Gemfile.gem-only`, selecting whether the `typst` gem is bundled), and runs
[`scenarios/backend_smoke_test.rb`](scenarios/backend_smoke_test.rb), which
asserts the resolved backend matches what's expected and that a real PDF
comes out (or that compilation fails with the expected error, for `neither`).

`fresh-install` instead runs `gem build typst-rails.gemspec && gem install
./typst-rails-*.gem` and then
[`scenarios/fresh_install_test.rb`](scenarios/fresh_install_test.rb) -- catching
packaging bugs the other scenarios can't, such as a new `lib/` file that
works locally but was never `git add`ed and so is silently missing from
`spec.files` (this suite caught exactly that during development).

## Running

```bash
# Run everything (recommended) -- builds all images, runs each scenario,
# prints a pass/fail summary, tears down the compose network
bundle exec rake e2e:docker

# Or drive Docker Compose directly, e.g. to iterate on one scenario
cd e2e-docker
docker compose build gem-only
docker compose run --rm gem-only
docker compose down --remove-orphans
```

A scenario prints `OK: ...` and exits 0 on success, or `FAIL: ...` and exits
non-zero. `rake e2e:docker` aborts (non-zero exit) if any scenario fails, and
lists which ones.

## Adding a scenario

1. Add (or reuse) a `Gemfile.*` in this directory controlling whether the
   `typst` gem is bundled.
2. Add a `Dockerfile.*` that installs whatever the scenario needs (Typst CLI,
   nothing, etc.) and runs a script from `scenarios/`.
3. Add a service to `docker-compose.yml` pointing at it.
4. Add the service name to `DOCKER_SCENARIOS` in the root `Rakefile`.

## Notes

- These images intentionally do **not** install the `development` gem group
  (`bundle config set --local without development`) so that TypstRails'
  own dev dependency on the `typst` gem (used for backend unit tests) can't
  leak into the `cli-only` / `neither` scenarios and invalidate them.
- `.dockerignore` at the repo root excludes local dev state
  (`.devenv/`, `coverage/`, etc.) from the build context, but keeps `.git/`,
  since `typst-rails.gemspec` shells out to `git ls-files` to compute
  `spec.files`.
- The Typst CLI version installed in these images is pinned via the
  `TYPST_VERSION` build arg in each Dockerfile (currently 0.13.1) and is
  independent of the `typst` gem's bundled compiler version -- a version
  mismatch between them is expected and not a bug.
