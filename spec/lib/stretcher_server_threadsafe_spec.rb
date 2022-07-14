require 'spec_helper'
# Explictly test threaded mode 
describe Stretcher::Server do

  RSpec.shared_examples 'a thread safe server' do
    it "should initialize threadsafe mode cleanly" do
      server.class.should == Stretcher::Server
    end

    it "should properly return that our server is up" do
      server.up?.should eql true
    end

    it "should perform threaded alias operations properly" do
      t1 = Thread.new {
        server.index(:foots).delete if server.index(:foots).exists?
        server.index(:foots).create
        server.aliases(actions: [{ add: { index: :foots, alias: :foots_alias } }])

        server.index(:foots_alias).get_settings.should == server.index(:foots).get_settings
        expect(indig(server.aliases, 'foots', 'aliases', 'foots_alias')).to_not be nil
      }
      t2 = Thread.new {
        server.index(:foots2).delete if server.index(:foots2).exists?
        server.index(:foots2).create
        server.aliases(actions: [{ add: { index: :foots2, alias: :foots_alias2 } }])

        server.index(:foots_alias2).get_settings.should == server.index(:foots2).get_settings

        expect(indig(server.aliases, 'foots2', 'aliases', 'foots_alias2')).to_not be nil
      }
      # Check the thread have not finished; they should both be running or sleeping. Any other value
      # indicates an unexpected result
      t1.status.should match /run|sleep/
      t2.status.should match /run|sleep/

      t1.join
      t2.join
    end

    it "should check the status w/o error" do
      expect(indig(server.status, 'indices')).to be
    end

    it "should refresh w/o error" do
      expect(indig(server.refresh, '_shards', 'failed')).to eql 0
    end

    it "should perform unthreaded alias operations properly" do

      server.index(:foots).delete if server.index(:foots).exists?
      server.index(:foots).create
      server.aliases(actions: [{ add: { index: :foots, alias: :foots_alias } }])

      server.index(:foots_alias).get_settings.should == server.index(:foots).get_settings

      expect(indig(server.aliases, 'foots', 'aliases', 'foots_alias')).to_not be nil

      server.index(:foots2).delete if server.index(:foots2).exists?
      server.index(:foots2).create
      server.aliases(actions: [{ add: { index: :foots2, alias: :foots_alias2 } }])

      server.index(:foots_alias2).get_settings.should == server.index(:foots2).get_settings

      expect(indig(server.aliases, 'foots2', 'aliases', 'foots_alias2').keys).to_not be nil
    end

    it "should check the status w/o error" do
      expect(indig(server.status, 'indices')).to be
    end

    it "should refresh w/o error" do
      expect(indig(server.refresh, '_shards', 'failed')).to eql 0
    end

  end

  describe 'string keys' do
    it_behaves_like 'a thread safe server' do
      let(:server) { Stretcher::Server.new(ES_URL, http_threadsafe: true, logger: DEBUG_LOGGER, symbolize_keys: false) }
    end
  end

  describe 'symbol keys' do
    it_behaves_like 'a thread safe server' do
      let(:server) { Stretcher::Server.new(ES_URL, http_threadsafe: true, logger: DEBUG_LOGGER, symbolize_keys: true) }
    end
  end

end 