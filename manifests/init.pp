class hybrid_ssm_agent (
  String $region,
  Struct[{
    id   => String,
    code => String,
  }] $activation,
  Enum['present', 'absent'] $ensure = 'present',
  Optional[Struct[{
    http_proxy            => String,
    Optional[https_proxy] => String,
    Optional[no_proxy]    => String,
  }]] $proxy = undef,
) {
  $service_name = 'amazon-ssm-agent'
  # Outside /tmp, which Ubuntu clears on boot: a missing file would download again
  $bootstrap_deb = '/var/cache/amazon-ssm-agent.deb'
  $proxy_dropin_dir = "/etc/systemd/system/${service_name}.service.d"
  $aws_dir = '/root/.aws'
  $credential_process = "${aws_dir}/ssm-creds-process"
  $aws_config = "${aws_dir}/config"
  $aws_credentials = "${aws_dir}/credentials"

  if $ensure == 'present' {
    $arch = case $facts['os']['architecture'] {
      'x86_64', 'amd64': { 'amd64' }
      'i386': { '386' }
      'aarch64', 'arm64': { 'arm64' }
      default: {
        fail("Module not supported on ${facts['os']['architecture']} architecture")
      }
    }

    $source_prefix = "https://s3.${region}.amazonaws.com/amazon-ssm-${region}"
    $archive_proxy_server = if $proxy {
      if 'https_proxy' in $proxy {
        $proxy['https_proxy']
      } else {
        $proxy['http_proxy']
      }
    } else {
      undef
    }

    package { 'screen':
      ensure => installed,
    }
    -> archive { $bootstrap_deb:
      source       => "${source_prefix}/latest/debian_${arch}/amazon-ssm-agent.deb",
      cleanup      => false,
      proxy_server => $archive_proxy_server,
    }
    -> package { 'amazon-ssm-agent':
      ensure   => installed,
      provider => 'dpkg',
      source   => $bootstrap_deb,
    }
    ~> service { $service_name:
      ensure => running,
      enable => true,
    }

    # No owner/group on the files here: they default to root, and declaring them
    # autorequires User[root], which control repos may order after this class (cycle)
    file { $aws_dir:
      ensure => directory,
      mode   => '0700',
    }

    file { $credential_process:
      ensure => file,
      mode   => '0755',
      source => 'puppet:///modules/hybrid_ssm_agent/ssm-creds-process',
    }

    file { $aws_config:
      ensure  => file,
      mode    => '0644',
      content => "[profile ssm]\ncredential_process = ${credential_process}\n",
    }

    Package['amazon-ssm-agent']
    -> exec { 'register-ssm-agent':
      command => Sensitive("amazon-ssm-agent -register -code ${activation['code']} -id ${activation['id']} -region ${region} -y"),
      unless  => "grep aws_session_token ${aws_credentials}",
      path    => '/bin:/usr/bin',
    }
    ~> Service[$service_name]

    if $proxy {
      file { $proxy_dropin_dir:
        ensure => directory,
      }

      # Restarting the service runs the daemon-reload the new drop-in needs
      file { "${proxy_dropin_dir}/proxy.conf":
        ensure  => file,
        mode    => '0644',
        content => epp('hybrid_ssm_agent/proxy.conf.epp', $proxy),
      }
      ~> Service[$service_name]
    }

    exec { 'immutable-machine-id-for-consistent-ssm-fingerprint-during-ubuntu-release-upgrades':
      command => '/usr/bin/chattr +i /etc/machine-id',
      onlyif  => [
        '/usr/bin/test -s /etc/machine-id',
        '/bin/grep -qE "^[0-9a-f]{32}$" /etc/machine-id',
      ],
      unless  => '/usr/bin/lsattr /etc/machine-id | /bin/grep -q "^....i"',
    }
  } else {
    service { $service_name:
      ensure => stopped,
      enable => false,
    }
    -> package { 'amazon-ssm-agent':
      ensure   => absent,
      provider => 'dpkg',
    }

    Service[$service_name]
    -> file { $proxy_dropin_dir:
      ensure => absent,
      force  => true,
    }

    # A stale token would skip registration if the node is made present again
    file { [$bootstrap_deb, $credential_process, $aws_config, $aws_credentials]:
      ensure => absent,
    }
  }
}
