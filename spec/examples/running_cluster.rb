shared_context "running_cluster", :shared_context => :metadata do
  include Pupperware::SpecHelpers

  before(:each) do
    docker_compose_up()
  end
end

shared_examples 'a running pupperware cluster' do
  require 'rspec/core'

  include_context 'running_cluster'

  it 'should start all of the cluster services' do
    expect(get_service_container('puppet')).to_not be_empty
    expect(get_service_container('postgres')).to_not be_empty
    expect(get_service_container('puppetdb')).to_not be_empty
  end

  it 'should include postgres extensions' do
    installed_extensions = get_postgres_extensions
    expect(installed_extensions).to match(/^\s+pg_trgm\s+/)
    expect(installed_extensions).to match(/^\s+pgcrypto\s+/)
  end

  it 'should be able to run an agent' do
    status = run_agent(@test_agent, 'pupperware_default')
    expect(status).to eq(0)
  end

  it 'should have a report in puppetdb' do
    timestamp = check_report(@test_agent)
    expect(timestamp).not_to eq('')
    @timestamps << timestamp
  end

  it 'should be able to clean a certificate' do
    status = clean_certificate(@test_agent)
    expect(status).to eq(0)
  end
end
