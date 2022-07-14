require 'spec_helper'

describe Stretcher::Cluster do

  RSpec.shared_examples 'an alias' do
    let(:cluster) { server.cluster }

    describe :health do

      it 'should return the health' do
        cluster.health.should be_a Hash
        expect(indig(cluster.health, 'status')).to_not be nil
      end

    end

  end

  describe 'string keys' do
    it_behaves_like 'an alias' do
      let(:server) { Stretcher::Server.new(ES_URL, logger: DEBUG_LOGGER, symbolize_keys: false) }
    end
  end

  describe 'symbol keys' do
    it_behaves_like 'an alias' do
      let(:server) { Stretcher::Server.new(ES_URL, logger: DEBUG_LOGGER, symbolize_keys: true) }
    end
  end

end