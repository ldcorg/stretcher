require 'spec_helper'

describe Stretcher::IndexDocs do

  RSpec.shared_examples 'index docs' do

    let(:index) { ensure_test_index(server, :foo) }
    let(:mapping) do
      { "properties" => { "message" => { "type" => "text" } } }
    end
    let(:docs) { index.docs }

    before(:each) do
      docs.delete_query(match_all: {})

      index.refresh
      index.put_mapping({
                          "properties" => {
                            "message" => { "type" => "text", analyzer: "snowball", "store": true },
                            "username" => { "type" => "text" }
                          } })
    end

    it "should be existentially aware" do
      docs = index.docs
      docs.exists?(1).should eq false
      d = docs.put(1, { message: 'test' })
      docs.exists?(indig(d, '_id')).should eq true
    end

    describe "searching" do
      before do
        @doc = { message: "hello" }

        docs.put(123123, @doc)
        index.refresh
      end

      it "should search and find the right doc" do
        res = docs.search(query: { match: { message: @doc[:message] } })
        expect(indig(res.documents.first, 'message')).to eql @doc[:message]
      end

      it "should build results when _source is not included in loaded fields" do
        res = docs.search(query: { match_all: {} }, stored_fields: ['message'])
        indig(res.documents.first, 'message').should == [@doc[:message]]
      end

      it "should build results when no document fields are selected" do
        res = docs.search(query: { match_all: {} }, stored_fields: ['_id'])
        expect(indig(res.documents.first, '_id')).to_not be nil
      end

      it "should add _highlight field to resulting documents when present" do
        res = docs.search(query: { match: { message: 'hello' } }, highlight: { fields: { message: {} } })
        expect(indig(res.documents.first, 'message')).to eql @doc[:message]
        expect(indig(res.documents.first, '_highlight')).to_not be nil
      end
    end

    describe 'mget' do
      let(:doc_one) { { message: "message one!" } }
      let(:doc_two) { { message: "message two!" } }

      before do
        docs.put(988, doc_one)
        docs.put(989, doc_two)
      end

      it 'fetches multiple documents by id' do
        results = indig(docs.mget([988, 989]), 'docs')

        expect(results.count).to eql 2
        expect(indig(results.first, '_source', 'message')).to eql 'message one!'
        expect(indig(results.last, '_source', 'message')).to eql 'message two!'
      end

      it 'allows options to be passed through' do
        results = indig(docs.mget([988, 989], stored_fields: 'message'), 'docs')

        expect(indig(results.first, 'fields', 'message')).to eql ['message one!']
        expect(indig(results.last, 'fields', 'message')).to eql ['message two!']
      end
    end

    describe "ops on individual docs" do
      before(:each) do
        @doc = { message: "hello!" }
        @put_res = docs.put(987, @doc, { refresh: :wait_for })
      end

      describe "put" do
        it "should put correctly, with options" do
          primary_term = indig(@put_res, '_primary_term')
          seq_no = indig(@put_res, '_seq_no')
          res = docs.put(987, @doc, if_seq_no: seq_no, if_primary_term: primary_term)
          expect(indig(res, '_version')).to eql indig(@put_res, '_version') + 1
        end

        it "should post correctly, with options" do
          res = docs.post(@doc, refresh: true)
          expect(indig(res, '_version')).to eql 1
        end
      end

      describe "get" do
        it "should get individual documents correctly" do
          expect(indig(docs.get(987), 'message')).to eql @doc[:message]
        end

        it "should return nil when retrieving non-extant docs" do
          lambda {
            docs.get(898323329)
            docs.get(898323329)
          }.should raise_exception(Stretcher::RequestError::NotFound)
        end

        it "should get individual fields given a String, passing through additional options" do
          res = docs.get(987, { stored_fields: 'message' })
          expect(indig(res, 'message').first).to eql @doc[:message]
        end

        it "should get individual fields given an Array, passing through additional options" do
          res = docs.get(987, { stored_fields: ['message'] })
          expect(indig(res, 'message').first).to eql @doc[:message]
        end

        it "should have source and other fields accessible when raw=true" do
          res = docs.get(987, { stored_fields: ['message', '_source'] }, true)
          expect(indig(res, '_source', 'message')).to eql @doc[:message]
          expect(indig(res, 'fields', 'message').first).to eql @doc[:message]
        end

        it "should get individual raw documents correctly" do
          res = docs.get(987, {}, true)
          expect(indig(res, '_id')).to eql '987'
          expect(indig(res, '_source', 'message')).to eql @doc[:message]
        end

        it "should get individual raw documents correctly with legacy API" do
          res = docs.get(987, true)
          expect(indig(res, '_id')).to eql '987'
          expect(indig(res, '_source', 'message')).to eql @doc[:message]
        end
      end

      describe 'explain' do
        it "should explain a query" do
          docs.exists?(987).should eq(true)
          index.refresh
          res = docs.explain(987, { query: { match_all: {} } })
          expect(indig(res, 'explanation')).to_not be nil
        end

        it 'should allow options to be passed through' do
          index.refresh
          res = docs.explain(987, { query: { match_all: {} } }, { stored_fields: 'message' })
          expect(indig(res, 'get', 'fields', 'message')).to eql ['hello!']
        end
      end

      it "should update individual docs correctly using ctx.source" do
        pending "figure out how we want to handle turning groovy on (maybe use mustache?)"
        raise NotImplementedError
        #type.update(987, :script => "ctx._source.message = 'Updated!'")
        #type.get(987).message.should == 'Updated!'
      end

      it "should update individual docs correctly using doc" do
        docs.update(987, doc: { message: 'Updated!' })
        expect(indig(docs.get(987), 'message')).to eql 'Updated!'
      end

      it "should update individual docs correctly using doc and fields" do
        response = docs.update(987, { doc: { message: 'Updated!' } }, _source_includes: ['message'])
        expect(indig(response, 'get', '_source', 'message')).to eql 'Updated!'
      end

      it "should delete by query correctly" do
        res = docs.delete_query({ match_all: {} }, refresh: true)
        index.refresh
        docs.exists?(987).should == false
      end

      it "should delete individual docs correctly" do
        docs.exists?(987).should == true
        docs.delete(987)
        docs.exists?(987).should == false
      end

      it "should allow params to be passed to delete" do
        es_doc = docs.get(987, {}, true)
        primary_term = indig(es_doc, '_primary_term')
        seq_no = indig(es_doc, '_seq_no')
        lambda { docs.delete(987, if_primary_term: primary_term, if_seq_no: seq_no + 1) }.should raise_exception(Stretcher::RequestError)
        docs.delete(987, if_primary_term: primary_term, if_seq_no: seq_no)
        docs.exists?(987).should == false
      end
    end

    it 'tests indig' do
      [Stretcher::EsComponent, server, index, index.docs].each do |obj|

        hash = {
          a: 'a1',
          b: {
            b1: 'b1',
            b2: {
              b3: 'b3'
            }
          },
          'aa' => 'aa1',
          'bb' => {
            'bb1' => 'bb1',
            'bb2' => {
              'bb3' => 'bb3'
            }
          },
          c: {
            'd' => {
              e: 'e1'
            }
          }
        }

        expect(obj.indig(hash, :a)).to eql hash[:a]
        expect(obj.indig(hash, :a, :a1)).to eql nil
        expect(obj.indig(hash, :z)).to eql nil

        expect(obj.indig(hash, :b)).to eql hash[:b]
        expect(obj.indig(hash, :b, :b1)).to eql hash[:b][:b1]
        expect(obj.indig(hash, :b, :b2, :b3)).to eql hash[:b][:b2][:b3]
        expect(obj.indig(hash, :b, :b2, :b3, :bz)).to eql nil

        expect(obj.indig(hash, 'aa')).to eql hash['aa']
        expect(obj.indig(hash, 'aa', 'aa1')).to eql nil
        expect(obj.indig(hash, 'zz')).to eql nil

        expect(obj.indig(hash, 'bb')).to eql hash['bb']
        expect(obj.indig(hash, 'bb', 'bb1')).to eql hash['bb']['bb1']
        expect(obj.indig(hash, 'bb', 'bb2', 'bb3')).to eql hash['bb']['bb2']['bb3']
        expect(obj.indig(hash, 'bb', 'bb2', 'bb3', 'bbz')).to eql nil

        expect(obj.indig(hash, 'c', :d, 'e')).to eql hash[:c]['d'][:e]
      end
    end

    it 'tests deep_transform_keys' do
      [Stretcher::EsComponent, server, index, index.docs].each do |obj|
        hash = {
          'a' => 'a1',
          'b' => {
            'b1' => 'b1',
            'b2' => {
              'b3' => 'b3'
            }
          },
          c: {
            'd' => {
              e: 'e1'
            }
          }
        }
        h = obj.deep_transform_keys(hash)
        expect(h.keys.all? { |k| k.is_a?(Symbol) }).to eql true
        expect(h[:b].keys.all? { |k| k.is_a?(Symbol) }).to eql true
        expect(h[:b][:b2].keys.all? { |k| k.is_a?(Symbol) }).to eql true
        expect(h[:c].keys.all? { |k| k.is_a?(Symbol) }).to eql true
        expect(h[:c][:d].keys.all? { |k| k.is_a?(Symbol) }).to eql true
      end
    end
  end

  describe 'string keys' do
    it_behaves_like 'index docs' do
      let(:server) { Stretcher::Server.new(ES_URL, logger: DEBUG_LOGGER, symbolize_keys: false) }
    end
  end

  describe 'symbol keys' do
    it_behaves_like 'index docs' do
      let(:server) { Stretcher::Server.new(ES_URL, logger: DEBUG_LOGGER, symbolize_keys: true) }
    end
  end

end
