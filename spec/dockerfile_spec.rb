#! /usr/bin/env ruby

require "#{File.join(File.dirname(__FILE__), 'examples', 'running_cluster.rb')}"

describe 'The docker-compose file works' do
  include Pupperware::SpecHelpers

  before(:all) do
    # append .internal (or user domain) to ensure domain suffix for Docker DNS resolver is used
    # since search domains are not appended to /etc/resolv.conf
    @test_agent = "puppet_test#{Random.rand(1000)}.#{ENV['DOMAIN'] || 'internal'}"
    @timestamps = []
    status = docker_compose('version')[:status]
    if status.exitstatus != 0
      fail "`docker-compose` must be installed and available in your PATH"
    end
    teardown_cluster()
    # ensure all containers are latest versions
    docker_compose('pull --quiet', stream: STDOUT)
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
      expect(get_containers()).not_to be_empty
      # don't use shared helper as it removes volumes
      docker_compose('down', stream: STDOUT)
      expect(get_containers()).to be_empty
    end

    include_examples 'a running pupperware cluster'

    it 'should have a different report than earlier' do
      expect(@timestamps.size).to eq(2)
      expect(@timestamps.first).not_to eq(@timestamps.last)
    end
  end
end
