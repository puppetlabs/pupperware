require 'rspec'
require 'pupperware/spec_helper'
include Pupperware::SpecHelpers

RSpec.configure do |c|
  c.before(:suite) do
    teardown_cluster()
    # LCOW requires directories to exist
    # VOLUMES = ['postgres-data', 'postgres-ssl']
    # create_host_volume_targets(ENV['VOLUME_ROOT'], VOLUMES)
    docker_compose_up()
    timeout = 8 * 60
    wait_on_service_health('pe-orchestration-services', timeout)
    wait_for_pxp_agent_to_connect
  end

  c.after(:suite) do
    emit_logs
    teardown_cluster()
  end
end

describe 'PE stack' do
  it 'can orchestrate a puppet run on an agent via the client tools' do
    output = run_command("docker run \
           --rm \
           --network pupperware-commercial \
           --env RBAC_USERNAME=admin \
           --env RBAC_PASSWORD=admin \
           --env PUPPETSERVER_HOSTNAME=puppet.test \
           --env PE_CONSOLE_SERVICES_HOSTNAME=pe-console-services.test \
           artifactory.delivery.puppetlabs.net/pe-and-platform/pe-client-tools:19.1.3 \
           puppet-job run \
              --nodes puppet-agent.test \
              --service-url https://pe-orchestration-services.test:8143/")
    expect(output[:stdout]).to include('Success! 1/1 runs succeeded.')
  end
end
