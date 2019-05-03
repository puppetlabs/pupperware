require_relative './version'
require 'json'
require 'net/http'
require 'open3'
require 'timeout'

module Pupperware
module SpecHelpers

  ######################################################################
  # General Ruby Helpers
  ######################################################################

  def run_command(env = ENV.to_h, command)
    stdout_string = ''
    status = nil

    Open3.popen3(env, command) do |stdin, stdout, stderr, wait_thread|
      Thread.new do
        Thread.current.report_on_exception = false
        stdout.each { |l| stdout_string << l and STDOUT.puts l }
      end
      Thread.new do
        Thread.current.report_on_exception = false
        stderr.each { |l| STDOUT.puts l }
      end

      stdin.close
      status = wait_thread.value
    end

    { status: status, stdout: stdout_string }
  end

  def retry_block_up_to_timeout(timeout, &block)
    ex = nil
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    loop do
      begin
        return yield
      rescue => e
        ex = e
        sleep(1)
      ensure
        if (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) > timeout
          raise Timeout::Error.new(ex)
        end
      end
    end
  end

  ######################################################################
  # Docker Compose Helpers
  ######################################################################

  # Windows requires directories to exist prior, whereas Linux will create them
  def create_host_volume_targets(root, volumes)
    return unless !!File::ALT_SEPARATOR

    STDOUT.puts("Creating volumes directory structure in #{root}")
    volumes.each { |subdir| FileUtils.mkdir_p(File.join(root, subdir)) }
    # Hack: grant all users access to this temp dir for the sake of Docker daemon
    run_command("icacls \"#{root}\" /grant Users:\"(OI)(CI)F\" /T")
  end

  def get_containers
    result = run_command('docker-compose --no-ansi --log-level INFO ps -q')
    ids = result[:stdout].chomp
    STDOUT.puts("Retrieved running container ids:\n#{ids}")
    ids.lines.map(&:chomp)
  end

  def get_service_container(service, timeout = 120)
    return retry_block_up_to_timeout(timeout) do
      container = run_command("docker-compose --no-ansi ps --quiet #{service}")[:stdout].chomp
      if container.empty?
        raise "docker-compose never started a service named '#{service}' in #{timeout} seconds"
      end

      STDOUT.puts("service named '#{service}' is hosted in container: '#{container}'")
      container
    end
  end

  def get_service_base_uri(service, port)
    @mapped_ports ||= {}
    @mapped_ports["#{service}:#{port}"] ||= begin
      result = run_command("docker-compose --no-ansi port #{service} #{port}")
      service_ip_port = result[:stdout].chomp
      raise "Could not retrieve service endpoint for #{service}:#{port}" if service_ip_port == ''
      uri = URI("http://#{service_ip_port}")
      uri.host = 'localhost' if uri.host == '0.0.0.0'
      STDOUT.puts "determined #{service} endpoint for port #{port}: #{uri}"
      uri
    end
    @mapped_ports["#{service}:#{port}"]
  end

  def teardown_cluster
    STDOUT.puts("Tearing down test cluster")
    get_containers.each do |id|
      STDOUT.puts("Killing container #{id}")
      run_command("docker container kill #{id}")
    end
    # still needed to remove network / provide failsafe
    run_command('docker-compose --no-ansi down --volumes')
  end

  ######################################################################
  # Docker Helpers
  ######################################################################

  def inspect_container(container, query)
    result = run_command("docker inspect \"#{container}\" --format \"#{query}\"")
    status = result[:stdout].chomp
    STDOUT.puts "queried #{query} of #{container}: #{status}"
    return status
  end

  def get_container_status(container)
    inspect_container(container, '{{.State.Health.Status}}')
  end

  def get_container_name(container)
    inspect_container(container, '{{.Name}}')
  end

  def get_container_hostname(container)
    # '{{json .NetworkSettings.Networks}}' useful in debug
    # returns all aliases in a Go array like [foo bar baz], so turn into Ruby array to inspect
    aliases = inspect_container(container, '{{range .NetworkSettings.Networks}}{{.Aliases}}{{end}}')
    aliases = (aliases || '').slice(1, aliases.length - 2).split(/\s/)
    # find the first alias that at least looks like foo.bar
    fqdn = aliases.find { |a| a.match /.+\..+/ }

    return fqdn || inspect_container(container, '{{.Config.Hostname}}')
  end

  def emit_log(container)
    container_name = get_container_name(container)
    STDOUT.puts("#{'*' * 80}\nContainer logs for #{container_name} / #{container}\n#{'*' * 80}\n")
    logs = run_command("docker logs --details --timestamps #{container}")[:stdout]
    STDOUT.puts(logs)
  end

  def emit_logs
    STDOUT.puts("Emitting container logs")
    get_containers.each { |id| emit_log(id) }
  end

  ######################################################################
  # Postgres Helpers
  ######################################################################

  def count_postgres_database(database)
    cmd = "docker-compose --no-ansi exec -T postgres psql -t --username=puppetdb --command=\"SELECT count(datname) FROM pg_database where datname = '#{database}'\""
    run_command(cmd)[:stdout].strip
  end

  def wait_on_postgres_db(database, seconds = 240)
    return retry_block_up_to_timeout(seconds) do
      count_postgres_database('puppetdb') == '1' ? '1' :
        raise("database #{database} never created")
    end
  end

  def get_postgres_extensions
    return retry_block_up_to_timeout(30) do
      query = 'docker-compose --no-ansi exec -T postgres psql --username=puppetdb --command="SELECT * FROM pg_extension"'
      extensions = run_command(query)[:stdout].chomp
      raise('failed to retrieve extensions') if extensions.empty?
      STDOUT.puts("retrieved extensions: #{extensions}")
      extensions
    end
  end

  ######################################################################
  # PuppetDB Helpers
  ######################################################################

  def get_puppetdb_state
    # make sure PDB container hasn't stopped
    get_service_container('puppetdb', 5)
    # now query its status endpoint
    pdb_uri = URI::join(get_service_base_uri('puppetdb', 8080), '/status/v1/services/puppetdb-status')
    response = Net::HTTP.get_response(pdb_uri)
    STDOUT.puts "retrieved raw puppetdb status: #{response.body}"
    case response
      when Net::HTTPSuccess then
        return JSON.parse(response.body)['state']
      else
        return ''
    end
  rescue Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError => e
    STDOUT.puts "PDB not accepting connections yet #{pdb_uri}: #{e}"
    return ''
  rescue JSON::ParserError
    STDOUT.puts "Invalid JSON response: #{e}"
    return ''
  rescue
    STDOUT.puts "Failure querying #{pdb_uri}: #{$!}"
    raise
  end

  def wait_on_puppetdb_status(seconds = 240)
    # since pdb doesn't have a proper healthcheck yet, this could spin forever
    # add a timeout so it eventually returns.
    return retry_block_up_to_timeout(seconds) do
      get_puppetdb_state() == 'running' ? 'running' :
        raise('puppetdb never entered running state')
    end
  end

  ######################################################################
  # Puppetserver Helpers
  ######################################################################

  def wait_on_puppetserver_status(seconds = 180, service_name = 'puppet')
    # puppetserver has a healthcheck, we can let that deal with timeouts
    return retry_block_up_to_timeout(seconds) do
      status = get_container_status(get_service_container(service_name))
      (status == 'healthy' || status == "'healthy'") ? 'healthy' :
        raise("puppetserver stuck in #{status}")
    end
  end

  def clean_certificate(agent_name)
    result = run_command('docker-compose --no-ansi exec -T puppet facter domain')
    domain = result[:stdout].chomp
    STDOUT.puts "cleaning cert for #{agent_name}.#{domain}"
    result = run_command("docker-compose --no-ansi exec -T puppet puppetserver ca clean --certname #{agent_name}.#{domain}")
    return result[:status].exitstatus
  end

  ######################################################################
  # Puppet Agent Helpers
  ######################################################################

  # When testing with the `puppet/puppet-agent-alpine` image on windows
  # systems with LCOW we had intermittent failures in DNS resolution that
  # occurred fairly regularly. It seems to be specifically interaction
  # between the base alpine (3.8 and 3.9) images with windows/LCOW.
  #
  # Two issues related to this issue are
  # https://github.com/docker/libnetwork/issues/2371 and
  # https://github.com/Microsoft/opengcs/issues/303
  def run_agent(agent_name, network, server = get_container_hostname(get_service_container('puppet')), ca = get_container_hostname(get_service_container('puppet')))
    # setting up a Windows TTY is difficult, so we don't
    # allocating a TTY will show container pull output on Linux, but that's not good for tests
    STDOUT.puts("running agent #{agent_name} in network #{network} against #{server}")
    result = run_command("docker run --rm --network #{network} --name #{agent_name} --hostname #{agent_name} puppet/puppet-agent-ubuntu agent --verbose --onetime --no-daemonize --summarize --server #{server} --ca_server #{ca}")
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

end
end
