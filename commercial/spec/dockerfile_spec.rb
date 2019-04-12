#! /usr/bin/env ruby

require "#{File.join(File.dirname(__FILE__), 'examples', 'running_cluster.rb')}"

describe 'The docker-compose file works' do
  include Pupperware::SpecHelpers

  VOLUMES = [
    'volumes/code',
    'volumes/puppet',
    'volumes/serverdata',
    'volumes/puppetdb/ssl',
    'volumes/puppetdb-postgres/data'
  ]

  before(:all) do
    @test_agent = "puppet_test#{Random.rand(1000)}"
    @timestamps = []
    status = run_command('docker-compose --no-ansi version')[:status]
    if status.exitstatus != 0
      fail "`docker-compose` must be installed and available in your PATH"
    end
    teardown_cluster()
    # LCOW requires directories to exist
    create_host_volume_targets(ENV['VOLUME_ROOT'], VOLUMES)
    # ensure all containers are latest versions
    run_command('docker-compose --no-ansi pull --quiet')
  end

  after(:all) do
    emit_logs()
    teardown_cluster()
  end

  describe 'the cluster starts' do
    include_examples 'a running pupperware cluster'
  end

  describe 'the cluster restarts' do
    before(:all) do
      @mapped_ports = {}
    end

    # don't run this on Windows because compose down takes forever
    # https://github.com/docker/for-win/issues/629
    it 'should stop the cluster', :if => File::ALT_SEPARATOR.nil? do
      ps = run_command('docker-compose --no-ansi ps')[:stdout].chomp
      expect(ps.match('puppet')).not_to eq(nil)
      run_command('docker-compose --no-ansi down')
      ps = run_command('docker-compose --no-ansi ps')[:stdout].chomp
      expect(ps.match('puppet')).to eq(nil)
    end

    include_examples 'a running pupperware cluster'

    it 'should have a different report than earlier' do
      expect(@timestamps.size).to eq(2)
      expect(@timestamps.first).not_to eq(@timestamps.last)
    end
  end
end
