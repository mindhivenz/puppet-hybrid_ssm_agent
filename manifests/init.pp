class hybrid_ssm_agent (
  String $version = 'latest',
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
    # Can't use $version here as is different. e,g, download version 2.3.978.0 -> package version 2.3.978.0-1
    ensure   => latest,
    provider => 'dpkg',
    source   => $install_file,
  }
  ~> service { $service_name:
    ensure => running,
    enable => true,
  }

  Package['amazon-ssm-agent']
  -> exec { 'register-ssm-agent':
    command => "amazon-ssm-agent -register -code ${$activation[code]} -id ${$activation[id]} -region ${region}",
    unless  => 'grep aws_session_token /root/.aws/credentials',
    path    => '/bin:/usr/bin',
  }
  ~> Service[$service_name]

  exec { 'restart-ssm-agent-if-sleeping':
    # Due to this bug: https://github.com/aws/amazon-ssm-agent/issues/468
    command => '/bin/true',
    onlyif  => '/bin/journalctl -b -u amazon-ssm-agent.service | /bin/tail -n1 | /bin/grep Sleeping',
  }
  ~> Service[$service_name]

  if $proxy {
    systemd::dropin_file { "$service_name-proxy.conf":
      unit    => "$service_name.service",
      content => epp('hybrid_ssm_agent/proxy.conf.epp', $proxy),
    }
    ~> Service[$service_name]
  }

}
