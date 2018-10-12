#! /usr/bin/env ruby

require 'rspec/core'
require 'json'

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

  def puppetserver_health_check(container)
    %x(#{@docker} inspect "#{container}" --format '{{.State.Health.Status}}').chomp
  end

  def get_puppetdb_state
    status = %x(#{@compose} exec -T puppet curl -s 'http://puppetdb:8080/status/v1/services/puppetdb-status').chomp
    return JSON.parse(status)['state'] unless status.empty?
    return ''
  end

  def start_puppetserver
    container = %x(#{@compose} ps -q puppet).chomp
    while container.empty?
      sleep(1)
      container = %x(#{@compose} ps -q puppet).chomp
    end
    status = puppetserver_health_check(container)
    while status == 'starting'
      sleep(1)
      status = puppetserver_health_check(container)
    end

    # work around SERVER-2354
    %x(#{@compose} exec puppet puppet config set server puppet)

    return status
  end

  def start_puppetdb
    status = get_puppetdb_state
    while status != 'running'
      sleep(1)
      status = get_puppetdb_state
    end
    return status
  end

  def run_agent(agent_name)
    %x(#{@docker} run --rm -it --net pupperware_default --name #{agent_name} --hostname #{agent_name} puppet/puppet-agent-ubuntu)
    return $?
  end

  def check_report(agent_name)
    domain = %x(#{@compose} exec -T puppet facter domain).chomp
    body = "{ \"query\": \"nodes { certname = \\\"#{agent_name}.#{domain}\\\" } \" }"
    out = ''
    while out.empty?
      out = %x(#{@compose} exec -T puppet curl -s -X POST http://puppetdb:8080/pdb/query/v4 -H 'Content-Type:application/json' -d '#{body}')
      sleep(1) if out.empty?
    end
    begin
      JSON.parse(out).first['report_timestamp']
    rescue
      return ''
    end
  end

  def clean_certificate(agent_name)
    domain = %x(#{@compose} exec -T puppet facter domain).chomp
    %x(#{@compose} exec -T puppet puppetserver ca clean --certname #{agent_name}.#{domain})
    return $?
  end

  before(:all) do
    @test_agent = "puppet_test#{Random.rand(1000)}"
    @docker = which('docker')
    @compose = which('docker-compose')
    @timestamps = []
    if @compose.nil?
      fail "`docker-compose` must be installed and available in your PATH"
    end
    %x(#{@compose} up -d)
  end

  after(:all) do
    %x(#{@compose} down)
  end

  describe 'the cluster starts' do
    it 'should start puppetserver' do
      status = start_puppetserver
      expect(status).to eq('healthy')
    end

    it 'should start puppetdb' do
      status = start_puppetdb
      expect(status).to eq('running')
    end

    it 'should be able to run an agent' do
      status = run_agent(@test_agent)
      expect(status).to eq(0)
    end

    it 'should have a report in puppetdb' do
      timestamp = check_report(@test_agent)
      @timestamps << timestamp
      expect(timestamp).not_to eq('')
    end

    it 'should be able to clean a certificate' do
      status = clean_certificate(@test_agent)
      expect(status).to eq(0)
    end
  end

  describe 'the cluster restarts' do
    it 'should stop the cluster' do
      ps = %x(#{@compose} ps)
      expect(ps.match('puppet')).not_to eq(nil)
      %x(#{@compose} down)
      ps = %x(#{@compose} ps)
      expect(ps.match('puppet')).to eq(nil)
    end

    it 'should start the cluster' do
      %x(#{@compose} up -d)
      ps = %x(#{@compose} ps)
      expect(ps.match('puppet')).not_to eq(nil)
    end

    it 'should start puppetserver' do
      status = start_puppetserver
      expect(status).to eq('healthy')
    end

    it 'should start puppetdb' do
      status = start_puppetdb
      expect(status).to eq('running')
    end

    it 'should be able to run an agent' do
      status = run_agent(@test_agent)
      expect(status).to eq(0)
    end

    it 'should have a report in puppetdb' do
      timestamp = check_report(@test_agent)
      expect(timestamp).not_to eq('')
      @timestamps << timestamp
    end

    it 'should have a different report than earlier' do
      expect(@timestamps.size).to eq(2)
      expect(@timestamps.first).not_to eq(@timestamps.last)
    end

    it 'should be able to clean a certificate' do
      status = clean_certificate(@test_agent)
      expect(status).to eq(0)
    end
  end
end
