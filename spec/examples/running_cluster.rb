shared_examples 'a running pupperware cluster' do
  require 'rspec/core'

  it 'should include postgres extensions' do
    installed_extensions = get_postgres_extensions
    expect(installed_extensions).to match(/\s+pg_trgm\s+/)
    expect(installed_extensions).to match(/\s+pgcrypto\s+/)
  end

  it 'should be able to run an agent' do
    status = run_agent(@test_agent, 'pupperware')
    expect(status).to eq(0)
  end

  it 'should have a report in puppetdb' do
    timestamp = check_report_timestamp(
        target_agent: @test_agent,
        network: 'pupperware',
        rbac_username: 'admin',
        rbac_password: RBAC_PASSWORD,
        puppetdb: 'puppetdb',
        image: CLIENT_TOOLS_IMAGE
      )
    expect(timestamp).not_to eq('')
    @timestamps << timestamp
  end

  it 'should be able to clean a certificate' do
    status = clean_certificate(@test_agent)
    expect(status).to eq(0)
  end
end
