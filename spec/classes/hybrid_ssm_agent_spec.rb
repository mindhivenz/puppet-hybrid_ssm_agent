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
    end
  end
end
