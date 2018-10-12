#! /usr/bin/env ruby

require 'rspec/core'
require 'json'
require "#{File.join(File.dirname(__FILE__), 'examples', 'running_cluster.rb')}"

describe 'The docker-compose file works' do
  def which(cmd)
    exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
    ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
      exts.each { |ext|
        exe = File.join(path, "#{cmd}#{ext}")
        return exe if File.executable?(exe) && !File.directory?(exe)
      }
    end
    return nil
  end

  before(:all) do
    @test_agent = "puppet_test#{Random.rand(1000)}"
    @docker = which('docker')
    @compose = which('docker-compose')
    @timestamps = []
    if @compose.nil?
      fail "`docker-compose` must be installed and available in your PATH"
    end
  end

  after(:all) do
    %x(#{@compose} down)
  end

  describe 'the cluster starts' do
    include_examples 'a running pupperware cluster'
  end

  describe 'the cluster restarts' do
    it 'should stop the cluster' do
      ps = %x(#{@compose} ps)
      expect(ps.match('puppet')).not_to eq(nil)
      %x(#{@compose} down)
      ps = %x(#{@compose} ps)
      expect(ps.match('puppet')).to eq(nil)
    end

    include_examples 'a running pupperware cluster'

    it 'should have a different report than earlier' do
      expect(@timestamps.size).to eq(2)
      expect(@timestamps.first).not_to eq(@timestamps.last)
    end
  end
end
