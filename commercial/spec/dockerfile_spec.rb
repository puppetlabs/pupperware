#! /usr/bin/env ruby

require 'rspec/core'
require 'json'
require "#{File.join(File.dirname(__FILE__), 'examples', 'running_cluster.rb')}"

describe 'The docker-compose file works' do
  before(:all) do
    @test_agent = "puppet_test#{Random.rand(1000)}"
    @timestamps = []
    %x(docker-compose --help)
    if $? != 0
      fail "`docker-compose` must be installed and available in your PATH"
    end
  end

  after(:all) do
    %x(docker-compose down)
  end

  describe 'the cluster starts' do
    include_examples 'a running pupperware cluster'
  end

  describe 'the cluster restarts' do
    it 'should stop the cluster' do
      ps = %x(docker-compose ps)
      expect(ps.match('puppet')).not_to eq(nil)
      %x(docker-compose down)
      ps = %x(docker-compose ps)
      expect(ps.match('puppet')).to eq(nil)
    end

    include_examples 'a running pupperware cluster'

    it 'should have a different report than earlier' do
      expect(@timestamps.size).to eq(2)
      expect(@timestamps.first).not_to eq(@timestamps.last)
    end
  end
end
