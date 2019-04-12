shared_examples 'a running pupperware cluster' do
  require 'rspec/core'

  include Pupperware::SpecHelpers

  it 'should start all of the cluster services' do
    run_command('docker-compose --no-ansi up --detach')
    wait_on_postgres_db('puppetdb')

    result = run_command('docker-compose --no-ansi ps puppet')
    expect(result[:status].exitstatus).to eq(0), "service puppet not found: #{result[:stdout].chomp}"

    result = run_command('docker-compose --no-ansi ps puppetdb')
    expect(result[:status].exitstatus).to eq(0), "service puppetdb not found: #{result[:stdout].chomp}"

    result = run_command('docker-compose --no-ansi ps postgres')
    expect(result[:status].exitstatus).to eq(0), "service postgres not found: #{result[:stdout].chomp}"
  end

  it 'should start puppetserver' do
    expect(wait_on_puppetserver_status()).to match(/\'?healthy\'?/)
  end

  it 'should start puppetdb' do
    expect(wait_on_puppetdb_status()).to eq('running')
  end

  it 'should include postgres extensions' do
    installed_extensions = get_postgres_extensions
    expect(installed_extensions).to match(/^\s+pg_trgm\s+/)
    expect(installed_extensions).to match(/^\s+pgcrypto\s+/)
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

  it 'should be able to clean a certificate' do
    status = clean_certificate(@test_agent)
    expect(status).to eq(0)
  end
end
