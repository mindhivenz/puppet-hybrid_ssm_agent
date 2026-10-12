# frozen_string_literal: true

require 'spec_helper'

describe 'hybrid_ssm_agent' do
  let(:params) do
    {
      region: 'us-east-1',
      activation: { id: 'SOME_ID', code: 'SOME_CODE' },
    }
  end

  def bootstrap_deb
    '/var/cache/amazon-ssm-agent.deb'
  end

  def proxy_dropin_dir
    '/etc/systemd/system/amazon-ssm-agent.service.d'
  end

  def proxy_dropin
    "#{proxy_dropin_dir}/proxy.conf"
  end

  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      it { is_expected.to compile.with_all_deps }

      it { is_expected.to contain_package('screen').with_ensure('installed') }

      it {
        is_expected.to contain_archive(bootstrap_deb).with(
          source: 'https://s3.us-east-1.amazonaws.com/amazon-ssm-us-east-1/latest/debian_amd64/amazon-ssm-agent.deb',
          cleanup: false,
          proxy_server: nil,
        ).that_requires('Package[screen]')
      }

      it {
        is_expected.to contain_package('amazon-ssm-agent').with(
          ensure: 'installed',
          provider: 'dpkg',
          source: bootstrap_deb,
        ).that_requires("Archive[#{bootstrap_deb}]")
      }

      it {
        is_expected.to contain_service('amazon-ssm-agent').with(
          ensure: 'running',
          enable: true,
        ).that_subscribes_to('Package[amazon-ssm-agent]')
      }

      it {
        is_expected.to contain_exec('register-ssm-agent').with(
          command: sensitive('amazon-ssm-agent -register -code SOME_CODE -id SOME_ID -region us-east-1 -y'),
          unless: 'grep aws_session_token /root/.aws/credentials',
          path: '/bin:/usr/bin',
        ).that_requires('Package[amazon-ssm-agent]').that_notifies('Service[amazon-ssm-agent]')
      }

      it { is_expected.not_to contain_file(proxy_dropin) }

      it {
        is_expected.to contain_exec('immutable-machine-id-for-consistent-ssm-fingerprint-during-ubuntu-release-upgrades').with(
          command: '/usr/bin/chattr +i /etc/machine-id',
          onlyif: ['/usr/bin/test -s /etc/machine-id', '/bin/grep -qE "^[0-9a-f]{32}$" /etc/machine-id'],
          unless: '/usr/bin/lsattr /etc/machine-id | /bin/grep -q "^....i"',
        )
      }

      describe 'rotating SSM credentials for SDKs and tools (credential_process)' do
        it { is_expected.to contain_file('/root/.aws').with(ensure: 'directory', mode: '0700', owner: nil, group: nil) }

        it {
          is_expected.to contain_file('/root/.aws/ssm-creds-process').with(
            ensure: 'file',
            mode: '0755',
            source: 'puppet:///modules/hybrid_ssm_agent/ssm-creds-process',
          )
        }

        it {
          is_expected.to contain_file('/root/.aws/config').with(
            ensure: 'file',
            mode: '0644',
            content: "[profile ssm]\ncredential_process = /root/.aws/ssm-creds-process\n",
          )
        }
      end

      context 'with User[root] managed after this class, as control repos do' do
        let(:pre_condition) do
          <<-PUPPET
            user { 'root': }
            Class['hybrid_ssm_agent'] -> User['root']
          PUPPET
        end

        it { is_expected.to compile.with_all_deps }

        context 'with a proxy' do
          let(:params) { super().merge(proxy: { http_proxy: 'http://proxy.example.com:3128' }) }

          it { is_expected.to compile.with_all_deps }
        end

        context 'when absent' do
          let(:params) { super().merge(ensure: 'absent') }

          it { is_expected.to compile.with_all_deps }
        end
      end

      context 'in another region' do
        let(:params) { super().merge(region: 'ap-southeast-2') }

        it { is_expected.to contain_archive(bootstrap_deb).with_source('https://s3.ap-southeast-2.amazonaws.com/amazon-ssm-ap-southeast-2/latest/debian_amd64/amazon-ssm-agent.deb') }

        it { is_expected.to contain_exec('register-ssm-agent').with_command(sensitive('amazon-ssm-agent -register -code SOME_CODE -id SOME_ID -region ap-southeast-2 -y')) }
      end

      {
        'x86_64' => 'amd64',
        'amd64' => 'amd64',
        'i386' => '386',
        'aarch64' => 'arm64',
        'arm64' => 'arm64',
      }.each do |architecture, deb_arch|
        context "on #{architecture} architecture" do
          let(:facts) { os_facts.merge(os: os_facts[:os].merge('architecture' => architecture)) }

          it { is_expected.to contain_archive(bootstrap_deb).with_source(%r{/latest/debian_#{deb_arch}/amazon-ssm-agent\.deb\z}) }
        end
      end

      context 'on an unsupported architecture' do
        let(:facts) { os_facts.merge(os: os_facts[:os].merge('architecture' => 'ppc64le')) }

        it { is_expected.to compile.and_raise_error(%r{Module not supported on ppc64le architecture}) }
      end

      context 'with only an http proxy' do
        let(:params) { super().merge(proxy: { http_proxy: 'http://proxy.example.com:3128' }) }

        it { is_expected.to compile.with_all_deps }

        it { is_expected.to contain_archive(bootstrap_deb).with_proxy_server('http://proxy.example.com:3128') }

        it { is_expected.to contain_file(proxy_dropin_dir).with(ensure: 'directory', owner: nil, group: nil) }

        it {
          is_expected.to contain_file(proxy_dropin).with(
            ensure: 'file',
            mode: '0644',
            owner: nil,
            group: nil,
            content: <<~CONF,
              [Service]
              Environment="http_proxy=http://proxy.example.com:3128"
              Environment="https_proxy=http://proxy.example.com:3128"
              Environment="no_proxy=169.254.169.254"
            CONF
          ).that_notifies('Service[amazon-ssm-agent]')
        }
      end

      context 'with http, https and no_proxy settings' do
        let(:params) do
          super().merge(
            proxy: {
              http_proxy: 'http://proxy.example.com:3128',
              https_proxy: 'http://secure-proxy.example.com:3129',
              no_proxy: 'localhost,10.0.0.0/8',
            },
          )
        end

        it { is_expected.to contain_archive(bootstrap_deb).with_proxy_server('http://secure-proxy.example.com:3129') }

        it {
          is_expected.to contain_file(proxy_dropin).with_content(<<~CONF).that_notifies('Service[amazon-ssm-agent]')
            [Service]
            Environment="http_proxy=http://proxy.example.com:3128"
            Environment="https_proxy=http://secure-proxy.example.com:3129"
            Environment="no_proxy=localhost,10.0.0.0/8"
          CONF
        }
      end

      context 'when absent' do
        let(:params) { super().merge(ensure: 'absent', proxy: { http_proxy: 'http://proxy.example.com:3128' }) }

        it { is_expected.to compile.with_all_deps }

        it { is_expected.to contain_service('amazon-ssm-agent').with(ensure: 'stopped', enable: false) }

        it {
          is_expected.to contain_package('amazon-ssm-agent').with(
            ensure: 'absent',
            provider: 'dpkg',
          ).that_requires('Service[amazon-ssm-agent]')
        }

        it { is_expected.to contain_file(bootstrap_deb).with_ensure('absent') }

        it { is_expected.to contain_file(proxy_dropin_dir).with(ensure: 'absent', force: true).that_requires('Service[amazon-ssm-agent]') }

        it { is_expected.to contain_file('/root/.aws/ssm-creds-process').with_ensure('absent') }

        it { is_expected.to contain_file('/root/.aws/config').with_ensure('absent') }

        it { is_expected.to contain_file('/root/.aws/credentials').with_ensure('absent') }

        it { is_expected.not_to contain_file('/root/.aws') }

        it { is_expected.not_to contain_archive(bootstrap_deb) }

        it { is_expected.not_to contain_exec('register-ssm-agent') }

        it { is_expected.not_to contain_exec('immutable-machine-id-for-consistent-ssm-fingerprint-during-ubuntu-release-upgrades') }

        it { is_expected.not_to contain_package('screen') }
      end

      context 'with an unknown ensure' do
        let(:params) { super().merge(ensure: 'latest') }

        it { is_expected.to compile.and_raise_error(%r{ensure}) }
      end

      context 'with the removed version parameter' do
        let(:params) { super().merge(version: '3.3.40.0') }

        it { is_expected.to compile.and_raise_error(%r{version}) }
      end
    end
  end
end
