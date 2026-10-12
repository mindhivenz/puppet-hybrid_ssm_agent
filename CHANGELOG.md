# Changelog

## Release 3.0.0

### Breaking changes

- Removed the `version` parameter. SSM's `AWS-UpdateSSMAgent` association now owns the agent version: Puppet installs the latest agent only when it's missing and never upgrades or downgrades it. Automatic lookup ignores the now unknown `hybrid_ssm_agent::version` hiera key, so it's inert in artemis-control and can be deleted
- Requires Puppet `>= 7.0.0 < 9.0.0` and supports Ubuntu 20.04, 22.04 and 24.04 only. Debian 9 is dropped

### Features

- `ensure => absent` stops, disables and removes the agent, its proxy drop-in, the cached `.deb`, the registration credentials and the module's files under `/root/.aws`

### Bug fixes

- The bootstrap `.deb` is cached in `/var/cache` instead of `/tmp`, which Ubuntu clears on boot, so a reboot no longer downloads it again
- `proxy` no longer causes a dependency cycle when a control repo orders `User[root]` after this class. The drop-in is a plain file that doesn't autorequire `User[root]`
- The activation code is redacted from Puppet's logs and reports

### Other changes

- Dropped the `puppet/systemd` dependency
- Converted from PDK to jig, with VoxBox CI and full spec coverage
