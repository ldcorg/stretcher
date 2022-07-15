require 'spec_helper'

describe Stretcher::SearchResults do

  RSpec.shared_examples 'a search' do
    let(:index) { ensure_test_index(server, :foo) }

    let(:result) do
      {
        'facets' => [],
        'hits' => {
          'total' => 1,
          'hits' => [{
                       '_score' => 255,
                       '_id' => 2,
                       '_index' => 'index_name',
                       '_type' => 'type_name',
                     }]
        }
      }
    end

    let(:result_with_hightlight) do
      {
        'facets' => [],
        'hits' => {
          'total' => 1,
          'hits' => [{
                       '_score' => 255,
                       '_id' => 2,
                       '_index' => 'index_name',
                       '_type' => 'type_name',
                       'highlight' => { 'message.*' => ["meeting at <hit>protonet</hit>!"] }
                     }]
        }
      }
    end

    context 'merges in underscore keys' do
      subject(:search_result) {
        Stretcher::SearchResults.new(result).documents.first
      }

      its(['_score']) { should == 255 }
      its(['_id']) { should == 2 }
      its(['_index']) { should == 'index_name' }
      its(['_type']) { should == 'type_name' }
      its(['_highlight']) { should be(nil) }
    end

    describe 'merges in optional keys' do
      let!(:search_result) { Stretcher::SearchResults.new(result_with_hightlight).documents.first }

      it 'merges the keys' do
        expect(indig(search_result, '_id')).to eql 2
        expect(indig(search_result, '_highlight')).to eql({ 'message.*' => ["meeting at <hit>protonet</hit>!"] })
      end

    end

    describe 'result object types' do
      let(:search_result) {
        sleep 2 rescue nil # Delay a little bit to see what's up with Travis CI
        index.search(query: { match_all: {} })
      }

      it 'returns a plain hash for raw' do
        sleep 1
        search_result.raw.should be_instance_of(::Hash)
      end

    end
  end

  describe 'string keys' do
    it_behaves_like 'a search' do
      let(:server) { Stretcher::Server.new(ES_URL, logger: DEBUG_LOGGER, symbolize_keys: false) }
    end
  end

  describe 'symbol keys' do
    it_behaves_like 'a search' do
      let(:server) { Stretcher::Server.new(ES_URL, logger: DEBUG_LOGGER, symbolize_keys: true) }
    end
  end

end