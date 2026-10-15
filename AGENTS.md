# Puppet module

This file is shared by every `puppet-*` module and synced from [mindhivenz/msync](https://github.com/mindhivenz/msync). Change it there, not here.

The module is managed with [jig](https://github.com/voxpupuli/jig) (`jig.toml` beside `metadata.json`). Checks run inside the [VoxBox](https://github.com/voxpupuli/container-voxbox) container, so the host needs only jig and Docker. Host Ruby is not used. jig is also in the image: run it with `--entrypoint jig`.

## Checking changes

After any change, validate, lint, rubocop and spec must all pass. A failure is blocking. CI runs the same four on every push and pull request.

The pinned image ref is `VOXBOX_IMAGE` in `.github/workflows/ci.yml`, the single source of truth. Run with the same ref:

```sh
export JIG_RUNNER_TYPE=voxbox
export JIG_RUNNER_IMAGE=$(sed -n 's/^  VOXBOX_IMAGE: //p' .github/workflows/ci.yml)
jig validate     # syntax, puppet-lint and rubocop
jig test unit    # rspec-puppet unit tests
```

To run a single spec file, call the container directly. Its entrypoint is `rake`, so any rake task works, such as `lint_fix`, `rubocop:autocorrect` or `spec`:

```sh
docker run --rm -v "$PWD:/repo" -e SPEC=spec/classes/<name>_spec.rb "$JIG_RUNNER_IMAGE" spec
```

## VoxBox gotchas

* VoxBox uses its own `/opt/voxbox/Gemfile` and `/opt/voxbox/Rakefile`, so modules have neither, and msync deletes any that `jig convert` writes.
  * Put lint config in `.puppet-lint.rc`, not in Rakefile tweaks.
  * A gem the image lacks can't be added from the repo.
* Lint is Vox Pupuli strict: extra plugins, and warnings fail the run. Run `lint_fix` first, then fix the rest by hand.
  * `lint_fix` can emit `else {[] }`, which fails a whitespace check however it is spaced. Rewrite it as a selector assigned to a variable outside the resource.
  * Move selectors and conditionals out of resource bodies into variables.
* facterdb has no legacy facts (`$::osfamily`, `ipaddress`, ...). Use structured facts such as `$facts['os']['family']`. If a fixture module you don't own reads a legacy fact, derive it in `spec/spec_helper_local.rb` with a comment saying why:
  `add_custom_fact :osfamily, ->(_os, facts) { facts[:os]['family'] }`
* In GitHub Actions, run the image with `docker run` from a host step. A `container:` job can't work, because the image is Alpine and JavaScript actions such as checkout fail in it.

## Spec customization

`spec/spec_helper.rb` is synced from msync, and `jig convert` overwrites it. Put spec customization in `spec/spec_helper_local.rb` and module facts in `spec/default_module_facts.yml`.

## Fixtures

Use https URLs for git fixtures in `.fixtures.yml`. CI has no SSH key.

## Adding components

`jig new class|defined_type|function|fact|task <name>` adds a component and its spec in the module layout.

## Building

* `jig build` writes the package to `pkg/`. It needs `summary` and `source` in `metadata.json`.
* The `[build]` section of `jig.toml` controls what is packaged. It ignores `.gitignore`.
  * `deny` mode packages only the allowlisted directories (`manifests/`, `files/`, ...) plus exceptions. It can't exclude a path inside an allowlisted directory, such as a local `files/**/.venv`.
  * In that case use `allow` mode, with exceptions listing the dev files.
* Check the package with `tar -tzf pkg/<file>.tar.gz`.

## More

When creating a new module, or changing its GitHub access, read the Confluence page [Puppet module dev](https://mindhive-global.atlassian.net/wiki/x/sgAdLQ).
