require 'spec_helper'

describe Stretcher::Index do
  RSpec.shared_examples 'indexes' do
    let(:index) { ensure_test_index(server, :foo, mappings) }
    let(:mappings) do
      {
        mappings: {
          properties: {
            username: { type: :text },
            age: { type: :integer },
            text: { type: :text },
            _text: { type: :text }
          }
        }
      }
    end
    let(:corpus) {
      # underscore field that are not system fields should make it through to _source
      [
        { 'username' => "john", 'age' => 25, 'text' => "Foo", '_text' => '_Foo', '_id' => 'fooid' },
        { 'username' => "jacob", 'age' => 32, 'text' => "Bar", '_text' => '_Bar', '_id' => 'barid' },
        { 'username' => "jingleheimer", 'age' => 54, 'text' => "Baz", '_text' => '_Baz', 'id' => 'bazid' } # Note we support both _id and id
      ]
    }

    def create_mapping
      index.put_mapping(mappings[:mappings])
    end

    def seed_corpus
      create_mapping
      index.bulk_index(corpus)
      index.refresh
    end

    it 'creates an index with the correct HTTP command' do
      index.delete rescue nil

      expected = %{curl -XPUT 'http://localhost:9200/foo' -d '#{Oj.dump(mappings)}' '-H Accept: application/json' '-H Content-Type: application/json' '-H User-Agent: Stretcher Ruby Gem #{Stretcher::VERSION}'}

      server.logger.should_receive(:debug) do |&block|
        block.call.should == expected
      end

      index.create(mappings)
    end

    it "should work on an existential level" do
      index.delete rescue nil
      index.exists?.should == false
      index.create
      index.exists?.should == true
    end

    it "should support block syntax for types" do
      exposed = nil
      res = index.docs { |t|
        exposed = t
        :retval
      }
      res.should == :retval
      exposed.class.should == Stretcher::IndexDocs
    end

    it "should return docs when issuing an mget" do
      seed_corpus
      user = corpus.first
      user_id = indig(user, '_id') || indig(user, 'id')
      res = index.mget([{ _index: index.name, _id: user_id }])

      expect(res.length).to eql(1)
      expect(indig(res.first, '_id')).to eql user_id
    end

    it "should return stats without error" do
      expect(indig(index.stats, '_all')).to_not be nil
    end

    it "should return the status without error" do
      expect(indig(index.status, '_shards')).to be_truthy
    end

    it "should put mappings for new types correctly" do
      create_mapping
    end

    it 'should be able to get mapping' do
      index.get_mapping.should_not be_nil
      expect(indig(index.get_mapping, 'foo')).to_not be nil
    end

    it "should retrieve settings properly" do
      index_settings = indig(index.get_settings, 'foo', 'settings', 'index')
      expect(indig(index_settings, 'number_of_shards')).to eql '1'
      expect(indig(index_settings, 'number_of_replicas')).to eql '0'
    end

    describe "bulk operations" do
      it "should bulk index documents properly" do
        seed_corpus
        corpus.each { |doc|
          doc_id = indig(doc, '_id') || indig(doc, 'id')
          fetched_doc = index.docs.get(doc_id, {}, true)
          source = indig(fetched_doc, '_source')
          expect(indig(source, 'text')).to eql doc['text']
          expect(indig(source, '_text')).to eql doc['_text']
          expect(indig(source, '_id')).to be nil
          expect(indig(source, '_type')).to be nil
        }
      end

      it "should bulk delete documents" do
        seed_corpus
        docs_meta = [
          { "_index" => index.name, "_id" => 'fooid' },
          { "_index" => index.name, "_id" => 'barid' }
        ]
        index.mget(docs_meta).length.should == 2
        index.bulk_delete(docs_meta)
        index.refresh
        index.mget(docs_meta).length.should == 0
      end

      it 'allows _routing to be set on bulk index documents' do
        server.index(:with_routing).delete if server.index(:with_routing).exists?
        server.index(:with_routing).create({
                                             settings: {
                                               number_of_shards: 1,
                                               number_of_replicas: 0
                                             },
                                             mappings: {
                                               _routing: { required: true }
                                             }
                                           })

        server.index(:with_routing).bulk_index(corpus)

        routed_corpus = corpus.map do |doc|
          routed_doc = doc.clone
          routed_doc['routing'] = 'abc'
          routed_doc
        end

        server.index(:with_routing).bulk_index(routed_corpus)

        server.index(:with_routing).delete
      end
    end

    describe "suggestion" do
      it "should correctly format the suggest request" do
        expected = {
          "sug-alias" => {
            text: "prefix",
            completion: { field: "sug-field" } } }
        index.
          should_receive(:request).
          with(:post, "_suggest", nil, expected).once.and_return(:result)
        index.suggest("sug-alias", "prefix", field: "sug-field").should == :result
      end
    end

    it "should delete by query" do
      seed_corpus
      index.search(query: { match_all: {} }).total == 3
      index.delete_query(match_all: {})
      index.refresh
      index.search(query: { match_all: {} }).total == 0
    end

    it "should search without error" do
      seed_corpus
      match_text = corpus.first['text']
      index.refresh
      res = index.search({}, { query: { match: { text: match_text } } })
      expect(indig(res.results.first, 'text')).to eql match_text
    end

    # TODO: Actually use two indexes
    describe "msearch" do
      let(:res) {
        seed_corpus
        q2_text = corpus.first['text']
        queries = [
          { query: { match_all: {} } },
          { query: { match: { text: q2_text } } }
        ]
        index.msearch(queries)
      }

      it "should return an array of Stretcher::SearchResults" do
        res.length.should == 2
        res[0].class.should == Stretcher::SearchResults
      end

      it "should return the query results in order" do
        # First query returns all docs, second only one
        res[0].results.length.should == corpus.length
        res[1].results.length.should == 1
      end

      it "should raise an error if any query is bad" do
        queries = [
          { query: { match_all: {} } },
          { query: { invalid_query: {} } }
        ]
        expect {
          index.msearch(queries)
        }.to raise_error(Stretcher::RequestError)
      end
    end

    it "execute the analysis API and return an expected result" do
      analyzed = server.index(:foo).analyze("Candles", analyzer: :snowball)
      first = indig(analyzed, 'tokens').first
      expect(indig(first, 'token')).to eql 'candl'
    end

    it "should raise an exception when msearching a non-existant index" do
      lambda {
        server.index(:does_not_exist).msearch([{ query: { match_all: {} } }])
      }.should raise_exception(Stretcher::RequestError)
    end

    describe "#update_settings" do
      it "updates settings on the index" do
        expect(indig(index.get_settings, 'foo', 'settings', 'index', 'number_of_replicas')).to eql '0'
        index.update_settings("index.number_of_replicas" => "1")
        expect(indig(index.get_settings, 'foo', 'settings', 'index', 'number_of_replicas')).to eql '1'
      end
    end

    describe "#forcemerge" do
      let(:request_url) { "http://localhost:9200/foo/_forcemerge" }

      context "with no options" do
        it "calls request for the correct endpoint with empty options" do
          expect(index.server).to receive(:request).with(:post, request_url, nil, nil, {}, {})
          index.forcemerge
        end

        it "successfully runs the forcemerge command for the index" do
          expect(indig(index.forcemerge, '_shards', 'failed')).to eql(0)
        end
      end

      context "with options" do
        it "calls request for the correct endpoint with options passed" do
          expect(index.server).to receive(:request).with(:post, request_url, { "max_num_segments" => 1 }, nil, {}, {})
          index.forcemerge("max_num_segments" => 1)
        end

        it "successfully runs the forcemerge command for the index with the options passed" do
          expect(indig(index.forcemerge("max_num_segments" => 1), '_shards', 'failed')).to eql(0)
        end
      end

    end
  end

  describe 'string keys' do
    it_behaves_like 'indexes' do
      let(:server) { Stretcher::Server.new(ES_URL, logger: DEBUG_LOGGER, symbolize_keys: false) }
    end
  end

  describe 'symbol keys' do
    it_behaves_like 'indexes' do
      let(:server) { Stretcher::Server.new(ES_URL, logger: DEBUG_LOGGER, symbolize_keys: true) }
    end
  end

end