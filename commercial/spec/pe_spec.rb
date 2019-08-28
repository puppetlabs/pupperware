require 'rspec'
require 'pupperware/spec_helper'
include Pupperware::SpecHelpers

CLIENT_TOOLS_IMAGE = 'artifactory.delivery.puppetlabs.net/pe-and-platform/pe-client-tools:kearney-latest'

RSpec.configure do |c|
  c.before(:suite) do
    teardown_cluster()
    pull_images()
    run_command("docker pull --quiet #{CLIENT_TOOLS_IMAGE}")
    docker_compose_up()
    wait_on_service_health('pe-orchestration-services')
    wait_for_pxp_agent_to_connect()
  end

  c.after(:suite) do
    emit_logs()
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
           #{CLIENT_TOOLS_IMAGE} \
           puppet-job run \
              --nodes puppet-agent.test \
              --service-url https://pe-orchestration-services.test:8143/")
    expect(output[:stdout]).to include('Success! 1/1 runs succeeded.')
  end
end
