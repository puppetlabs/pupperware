shared_examples 'a running pupperware cluster' do
  require 'timeout'
  require 'json'
  require 'rspec/core'

  def puppetserver_health_check(container)
    %x(docker inspect "#{container}" --format '{{.State.Health.Status}}').chomp
  end

  def get_puppetdb_state
    status = %x(docker-compose exec -T puppet curl -s 'http://puppetdb:8080/status/v1/services/puppetdb-status').chomp
    return JSON.parse(status)['state'] unless status.empty?
  rescue
    return ''
  else
    return ''
  end

  def start_puppetserver
    container = %x(docker-compose ps -q puppet).chomp
    Timeout::timeout(120) do
      while container.empty?
        sleep(1)
        container = %x(docker-compose ps -q puppet).chomp
      end
    end
  rescue Timeout::Error
    return ''
  else
    status = puppetserver_health_check(container)
    # puppetserver has a healthcheck, we can let that deal with timeouts
    while status == 'starting'
      sleep(1)
      status = puppetserver_health_check(container)
    end

    # work around SERVER-2354
    %x(docker-compose exec puppet puppet config set server puppet)

    return status
  end

  def run_agent(agent_name)
    %x(docker run --rm -it --net pupperware_default --name #{agent_name} --hostname #{agent_name} puppet/puppet-agent-ubuntu)
    return $?
  end

  def check_report(agent_name)
    domain = %x(docker-compose exec -T puppet facter domain).chomp
    body = "{ \"query\": \"nodes { certname = \\\"#{agent_name}.#{domain}\\\" } \" }"
    out = ''
    Timeout::timeout(120) do
      while out.empty?
        out = %x(docker-compose exec -T puppet curl -s -X POST http://puppetdb:8080/pdb/query/v4 -H 'Content-Type:application/json' -d '#{body}')
        sleep(1) if out.empty?
      end
      JSON.parse(out).first['report_timestamp']
    end
  rescue Timeout::Error
    return ''
  rescue
      return ''
  end

  def clean_certificate(agent_name)
    domain = %x(docker-compose exec -T puppet facter domain).chomp
    %x(docker-compose exec -T puppet puppetserver ca clean --certname #{agent_name}.#{domain})
    return $?
  end

  def start_puppetdb
    status = get_puppetdb_state
    # since pdb doesn't have a proper healthcheck yet, this could spin forever
    # add a timeout so it eventually returns.
    Timeout::timeout(600) do
      while status != 'running'
        sleep(1)
        status = get_puppetdb_state
      end
    end
  rescue Timeout::Error
    return ''
  else
    return status
  end

  it 'should start the cluster' do
    %x(docker-compose up -d)
    ps = %x(docker-compose ps)
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

  it 'should be able to clean a certificate' do
    status = clean_certificate(@test_agent)
    expect(status).to eq(0)
  end
end
