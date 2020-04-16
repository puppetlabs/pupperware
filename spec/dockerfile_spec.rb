#! /usr/bin/env ruby

require "#{File.join(File.dirname(__FILE__), 'examples', 'running_cluster.rb')}"
include Pupperware::SpecHelpers

RSpec.configure do |c|
  c.before(:suite) do
    pull_images()
    teardown_cluster()
    docker_compose_up()
  end

  c.after(:suite) do
    emit_logs
    teardown_cluster()
  end
end

describe 'The docker-compose file works' do
  before(:all) do
    @timestamps = []
    @test_agent ||= "puppet_test#{Random.rand(1000)}"
  end

  describe 'when starting' do
    include_examples 'a running pupperware cluster'
  end

  describe 'after the cluster restarts' do
    before(:all) do
      restart_stack()
    end

    include_examples 'a running pupperware cluster'

    it 'should have a different report than earlier' do
      expect(@timestamps.size).to eq(2)
      expect(@timestamps.first).not_to eq(@timestamps.last)
    end
  end
end
