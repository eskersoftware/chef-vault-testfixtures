require 'pathname'
require 'json'

require 'rspec'
require 'rspec/core/shared_context'
require 'chef-vault'

class ChefVault
  # dynamic RSpec contexts for cookbooks that use chef-vault
  class TestFixtures
    VERSION = '0.4.0'

    # dynamically creates a memoized RSpec shared context
    # that when included into an example group will stub
    # ChefVault::Item for each of the defined vaults. The
    # context is memoized and only created once
    # @return [Module] the RSpec shared context
    class << self
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def rspec_shared_context
        @context ||= begin
          Module.new do
            extend RSpec::Core::SharedContext

            before { find_vaults }

            private

            def find_vaults
              dbdir = Pathname.new('test') + 'integration' + 'data_bags'
              dbdir.each_child do |vault|
                next unless vault.directory?
                stub_vault(vault)
              end
            end

            def stub_vault(vault)
              vault.each_child do |e|
                next unless e.file?
                m = e.basename.to_s.downcase.match(/(.+)\.json/i)
                stub_vault_item(vault.basename.to_s, m[1], e.read) if m
              end
            end

            def stub_vault_item(vault, item, json)
              content = JSON.parse(json)
              db = make_fakedatabag(vault, item)
              dbi = make_fakedatabagitem(vault, item)
              vi = make_fakevault(vault, item)

              # stub lookup of each of the vault item keys
              content.each do |k, v|
                next if 'id' == k
                dbi[k] = { 'encrypted_data' => '...' }
                allow(vi).to receive(:[]).with(k).and_return(v)
              end

              # stub ChefVault and Chef::DataBag to return the doubles
              # via both symbol and string forms of the data bag name
              [vault, vault.to_sym].each do |dbname|
                allow(ChefVault::Item).to(
                  receive(:load)
                  .with(dbname, item)
                  .and_return(vi)
                )
                allow(Chef::DataBagItem).to(
                  receive(:load)
                  .with(dbname, item)
                  .and_return(dbi)
                )
                allow(Chef::DataBag).to(
                  receive(:load)
                  .with(dbname)
                  .and_return(db)
                )
              end
            end

            def make_fakedatabagitem(_, _)
              {}
            end

            def make_fakedatabag(vault, item)
              db = double "databag #{vault}"
              %w(key? has_key?).each do |pred|
                allow(db).to(receive(pred.to_sym)
                             .with("#{item}_keys")
                             .and_return(true))
              end
              db
            end

            def make_fakevault(vault, item)
              fakevault = double "vault item #{vault}/#{item}"
              allow(fakevault).to receive(:[]=).with(String, Object)
              allow(fakevault).to receive(:clients).with(String)
              allow(fakevault).to receive(:save)
              fakevault
            end
          end
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    end
  end
end
