#! /usr/bin/env ruby

require "#{File.join(File.dirname(__FILE__), 'examples', 'running_cluster.rb')}"
include Pupperware::SpecHelpers

# unifies volume naming
ENV['COMPOSE_PROJECT_NAME'] ||= 'pupperware'
RBAC_PASSWORD = 'admin'
CLIENT_TOOLS_IMAGE = 'artifactory.delivery.puppetlabs.net/platform-services-297419/pe-and-platform/pe-client-tools:latest'
Pupperware::SpecHelpers.load_compose_services='pe-postgres,pe-puppet,pe-puppetdb,pe-console-services,pe-bolt-server,pe-orchestration-services'

RSpec.configure do |c|
  c.before(:suite) do
    teardown_cluster()
    pull_images()
    run_command("docker pull --quiet #{CLIENT_TOOLS_IMAGE}")
    docker_compose_up(preload_certs: true)
  end

  c.after(:suite) do
    emit_logs
    teardown_cluster()
  end
end

describe 'PE stack' do
  before(:all) do
    @timestamps = []
    @test_agent ||= "puppet_test#{Random.rand(1000)}"
    # unrevoke the default admin/admin login and set the global RBAC token
    unrevoke_console_admin_user()
    generate_rbac_token(rbac_password: RBAC_PASSWORD)
    wait_for_pxp_agent_to_connect(agent_name: 'puppet-agent')
  end

  describe 'when starting' do
    include_examples 'a running pupperware cluster'
  end

  it 'can orchestrate a puppet run on an agent via the client tools' do
    output = run_command("docker run \
           --rm \
           --network pupperware \
           --env RBAC_USERNAME=admin \
           --env RBAC_PASSWORD=#{RBAC_PASSWORD} \
           --env PUPPETSERVER_HOSTNAME=puppet \
           --env PUPPETDB_HOSTNAME=puppetdb \
           --env PE_CONSOLE_SERVICES_HOSTNAME=pe-console-services \
           --env PE_ORCHESTRATION_SERVICES_HOSTNAME=pe-orchestration-services \
           #{CLIENT_TOOLS_IMAGE} \
           puppet-job run --nodes puppet-agent")
    expect(output[:stdout]).to include('Success! 1/1 runs succeeded.')
  end

  it 'will recieve an API request to run a task over SSH' do
    result = curl_console_task(target_nodes: 'test-sshd')
    expect(result).to include('"job":"2"')
  end

  it 'confirm the task completed without error' do
    result = curl_job_number(job_number: 2)
    expect(result).to include('"state":"finished"')
  end

  describe 'after a service crashes' do

    before(:all) do
      ['pe-console-services', 'pe-orchestration-services', 'puppet', 'puppetdb'].sample(1).each do | service |
        kill_service_and_wait_for_return(service: service, process: 'runuser')
        wait_on_stack_healthy()
      end

      # from OSS suite
      # restart_stack()
    end

    include_examples 'a running pupperware cluster'

    it 'can recover from services crashing and run puppet' do
      output = orchestrate_puppet_run(
          target_agent: 'puppet-agent',
          rbac_username: 'admin',
          rbac_password: RBAC_PASSWORD,
          puppetserver: 'puppet',
          pe_console_services: 'pe-console-services',
          pe_orchestration_services: 'pe-orchestration-services'
        )

      expect(output[:stdout]).to include('Success!')
    end

    it 'should have a different report than earlier' do
      expect(@timestamps.size).to eq(2)
      expect(@timestamps.first).not_to eq(@timestamps.last)
    end
  end
end
