# frozen_string_literal: true

require 'spec_helper'

describe 'hybrid_ssm_agent' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }
      let(:params) do
        {
          :region => 'us-east-1',
          :activation => {
            :id => 'SOME_ID',
            :code => 'SOME_CODE',
          },
          :proxy => {
            :http_proxy => 'http://exmaple.com',
          }
        }
      end

      it { is_expected.to compile }

      context 'with User[root] managed after this class, as control repos do' do
        # Not compatible with the proxy param: systemd::dropin_file hardcodes
        # owner root, which autorequires User[root] and closes the cycle
        let(:params) { super().reject { |key, _| key == :proxy } }

        let(:pre_condition) do
          <<-PUPPET
            user { 'root': }
            Class['hybrid_ssm_agent'] -> User['root']
          PUPPET
        end

        it { is_expected.to compile }
      end

      it { is_expected.to contain_file('/root/.aws').with_ensure('directory') }

      it {
        is_expected.to contain_file('/root/.aws/ssm-creds-process').with(
          :mode   => '0755',
          :source => 'puppet:///modules/hybrid_ssm_agent/ssm-creds-process',
        )
      }

      it {
        is_expected.to contain_file('/root/.aws/config').with_content(
          "[profile ssm]\ncredential_process = /root/.aws/ssm-creds-process\n"
        )
      }
    end
  end
end
