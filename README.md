# hybrid_ssm_agent

Installs the [AWS SSM agent](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent.html) on an on-premises Ubuntu node in hybrid mode, registers it with a hybrid activation, and lets other tools use the credentials the agent rotates.

## Usage

```puppet
class { 'hybrid_ssm_agent':
  region     => 'us-east-1',
  activation => { id => '<activation id>', code => '<activation code>' },
  proxy      => { http_proxy => 'http://proxy.example:3128' }, # optional
  ensure     => 'present',                                     # default, or 'absent'
}
```

* The agent version is managed by SSM's auto-update association (`AWS-UpdateSSMAgent`), not Puppet. Puppet only installs the agent when it's missing and never changes its version afterwards.
* To install, the latest agent `.deb` for the node's architecture (amd64, 386 or arm64) is downloaded once from the region's SSM bucket to `/var/cache/amazon-ssm-agent.deb` and installed with dpkg.
* The agent registers once with the activation, and the activation code is redacted from Puppet's logs and reports. Registration is skipped when `/root/.aws/credentials` already holds a session token.
* The agent writes rotating credentials to the `default` profile of `/root/.aws/credentials`. SDKs read that file only once, so the module also adds an `ssm` profile to `/root/.aws/config` whose `credential_process` (`/root/.aws/ssm-creds-process`) serves the current credentials with an expiry. SDKs run it again when that passes, so they pick up each rotation. Use `AWS_PROFILE=ssm`, including in containers that mount `/root/.aws`.
* `proxy` sets the agent's proxy environment through a systemd drop-in and is also used for the download. `https_proxy` defaults to `http_proxy` and `no_proxy` to `169.254.169.254`.
* `/etc/machine-id` is made immutable, so Ubuntu release upgrades don't change it and break the agent's fingerprint.
* `ensure => absent` stops and disables the agent, then removes its package, the proxy drop-in, the cached `.deb`, and `/root/.aws/config`, `/root/.aws/credentials` and `/root/.aws/ssm-creds-process`. It leaves `/etc/machine-id` immutable. `region` and `activation` are still required.

## Development

The module is managed with [jig](https://github.com/voxpupuli/jig). Validation and unit tests run inside the [VoxBox](https://github.com/voxpupuli/container-voxbox) container, so the only host requirements are jig and Docker (or Podman).

### Setup

Install jig from its [releases](https://github.com/voxpupuli/jig/releases), then point its runner at the same VoxBox image CI uses (see `VOXBOX_IMAGE` in `.github/workflows/ci.yml`):

```shell
export JIG_RUNNER_TYPE=voxbox
export JIG_RUNNER_IMAGE=ghcr.io/voxpupuli/voxbox:10.1.0-openvox8.30.0@sha256:01bb8ce5e24d5b111934660f75e2786b4d7c7adcaa7518a564856d1d3041d10d
```

To make this permanent, put the equivalent `[runner]` section in your jig config file instead (see the [jig voxbox docs](https://github.com/voxpupuli/jig/blob/main/docs/voxbox.md)).

### Validate and test

```shell
jig validate     # syntax, puppet-lint and rubocop
jig test unit    # rspec-puppet unit tests
```

Run a single spec file by calling the container directly:

```shell
docker run --rm -v "$PWD:/repo" -e SPEC=spec/classes/hybrid_ssm_agent_spec.rb "$JIG_RUNNER_IMAGE" spec
```

### Build

```shell
jig build
```

The package is written to `pkg/`. Which files are packaged is controlled by the `[build]` section of `jig.toml`.
