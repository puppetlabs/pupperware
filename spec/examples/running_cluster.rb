shared_examples 'a running pupperware cluster' do
  require 'json'
  require 'rspec/core'
  require 'net/http'

  include Pupperware::SpecHelpers

  def run_agent(agent_name)
    # setting up a Windows TTY is difficult, so we don't
    # allocating a TTY will show container pull output on Linux, but that's not good for tests
    result = run_command("docker run --rm --network pupperware_default --name #{agent_name} --hostname #{agent_name} puppet/puppet-agent-alpine")
    return result[:status].exitstatus
  end

  def check_report(agent_name)
    pdb_uri = URI::join(get_service_base_uri('puppetdb', 8080), '/pdb/query/v4')
    result = run_command("docker-compose --no-ansi exec -T puppet facter domain")
    domain = result[:stdout].chomp
    body = "{ \"query\": \"nodes { certname = \\\"#{agent_name}.#{domain}\\\" } \" }"

    return retry_block_up_to_timeout(120) do
      Net::HTTP.start(pdb_uri.hostname, pdb_uri.port) do |http|
        req = Net::HTTP::Post.new(pdb_uri)
        req.content_type = 'application/json'
        req.body = body
        res =  http.request(req)
        out = res.body if res.code == '200' && !res.body.empty?
        STDOUT.puts "retrieved agent #{agent_name} report info from #{req.uri}: HTTP #{res.code} /  #{res.body}"
        raise('empty PDB report received') if out.nil? || out.empty?
        JSON.parse(out).first['report_timestamp']
      end
    end
  end

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
