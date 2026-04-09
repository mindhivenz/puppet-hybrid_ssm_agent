class hybrid_ssm_agent (
  String $version = latest,
  String $region,
  Struct[{
    id   => String,
    code => String,
  }] $activation,
  Optional[Struct[{
    http_proxy            => String,
    Optional[https_proxy] => String,
    Optional[no_proxy]    => String,
  }]] $proxy      = undef,
) {

  $arch = case $facts[os][architecture] {
    'x86_64', 'amd64': { 'amd64' }
    'i386': { '386' }
    'aarch64', 'arm64': { 'arm64' }
    default: {
      fail("Module not supported on ${$facts[os][architecture]} architecture")
    }
  }

  $service_name = 'amazon-ssm-agent'
  $install_file = "/tmp/amazon-ssm-agent-${version}.deb"
  $source_prefix = "https://s3.${region}.amazonaws.com/amazon-ssm-${region}"
  $archive_proxy_server = if $proxy {
    if https_proxy in $proxy {
      $proxy[https_proxy]
    } else {
      $proxy[http_proxy]
    }
  } else {
    undef
  }

  package { 'screen':
    ensure => installed,
  }
  -> archive { $install_file:
    source       => "${source_prefix}/${version}/debian_${arch}/amazon-ssm-agent.deb",
    creates      => $install_file,
    cleanup      => false,
    proxy_server => $archive_proxy_server,
  }
  -> package { 'amazon-ssm-agent':
    ensure   => $version ? { latest => latest, default => "${version}-1" },
    provider => 'dpkg',
    source   => $install_file,
  }
  ~> service { $service_name:
    ensure => running,
    enable => true,
  }

  Package['amazon-ssm-agent']
  -> exec { 'register-ssm-agent':
    command => "amazon-ssm-agent -register -code ${$activation[code]} -id ${$activation[id]} -region ${region} -y",
    unless  => 'grep aws_session_token /root/.aws/credentials',
    path    => '/bin:/usr/bin',
  }
  ~> Service[$service_name]

  if $proxy {
    systemd::dropin_file { "$service_name-proxy.conf":
      unit    => "$service_name.service",
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

}
