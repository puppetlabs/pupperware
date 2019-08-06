require_relative './version'
require 'json'
require 'net/http'
require 'open3'
require 'timeout'
require 'openssl'

module Pupperware
module SpecHelpers

  IS_WINDOWS = !!File::ALT_SEPARATOR

  def require_test_image()
    image = ENV['PUPPET_TEST_DOCKER_IMAGE']
    if image.nil?
      fail <<-MSG
* * * * *
  PUPPET_TEST_DOCKER_IMAGE environment variable must be set so we
  know which image to test against!
* * * * *
      MSG
    end
    image
  end

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

  # Returns response object with `.body` and `.status` fields
  def curl(hostname, port, endpoint)
    uri = URI.parse(URI.encode("https://#{hostname}:#{port}/#{endpoint}"))
    request = Net::HTTP::Get.new(uri)
    request['X-Authentication'] = @rbac_token
    req_options = {
      use_ssl: uri.scheme == 'https',
      verify_mode: OpenSSL::SSL::VERIFY_NONE,
    }
    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end
    response
  end

  ######################################################################
  # Docker Compose Helpers
  ######################################################################

  def docker_compose(command_and_args)
    overrides = IS_WINDOWS ?
                  'docker-compose.windows.yml' :
                  'docker-compose.override.yml'
    # Only use overrides file if it exists
    file_arg = File.file?(overrides) ? "--file #{overrides}" : ''
    run_command("docker-compose --file docker-compose.yml #{file_arg} \
                                --no-ansi \
                                #{command_and_args}")
  end

  # Windows requires directories to exist prior, whereas Linux will create them
  def create_host_volume_targets(root, volumes)
    return unless IS_WINDOWS

    STDOUT.puts("Creating volumes directory structure in #{root}")
    volumes.each { |subdir| FileUtils.mkdir_p(File.join(root, subdir)) }
    # Hack: grant all users access to this temp dir for the sake of Docker daemon
    run_command("icacls \"#{root}\" /grant Users:\"(OI)(CI)F\" /T")
  end

  def get_containers
    result = docker_compose('--log-level INFO ps -q')
    ids = result[:stdout].chomp
    STDOUT.puts("Retrieved running container ids:\n#{ids}")
    ids.lines.map(&:chomp)
  end

  def get_service_container(service, timeout = 120)
    return retry_block_up_to_timeout(timeout) do
      container = docker_compose("ps --quiet #{service}")[:stdout].chomp
      if container.empty?
        raise "docker-compose never started a service named '#{service}' in #{timeout} seconds"
      end

      STDOUT.puts("service named '#{service}' is hosted in container: '#{container}'")
      container
    end
  end

  def pull_images(ignore_service)
    puts "Pulling images (ignoring image for #{ignore_service}):"
    services = docker_compose('config --services')[:stdout].chomp
    services = services.gsub(ignore_service, '')
    services = services.gsub("\n", ' ')
    docker_compose("pull --quiet #{services}")
  end

  def get_service_base_uri(service, port)
    @mapped_ports ||= {}
    @mapped_ports["#{service}:#{port}"] ||= begin
      result = docker_compose("port #{service} #{port}")
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
      teardown_container(id)
    end
    # still needed to remove network / provide failsafe
    docker_compose('down --volumes')
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

  def get_container_state(container)
    inspect_container(container, '{{.State.Status}}')
  end

  def get_container_exit_code(container)
    inspect_container(container, '{{.State.ExitCode}}').to_i
  end

  def wait_on_container_exit(container, timeout = 60)
    return retry_block_up_to_timeout(timeout) do
      get_container_state(container) == 'exited' ? 'exited' :
        raise('container never exited')
    end
  end

  def wait_on_service_health(service, seconds = 180)
    # services with healthcheck should deal with their own timeouts
    return retry_block_up_to_timeout(seconds) do
      status = get_container_status(get_service_container(service))
      (status == 'healthy' || status == "'healthy'") ? 'healthy' :
        raise("#{service} is not healthy - currently #{status}")
    end
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

  # this only works when a container has a single network
  def get_container_ip(container)
    inspect_container(container, '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
  end

  def emit_log(container)
    container_name = get_container_name(container)
    STDOUT.puts("#{'*' * 80}\nContainer logs for #{container_name} / #{container}\n#{'*' * 80}\n")
    logs = run_command("docker logs --details --timestamps #{container}")[:stdout]
    STDOUT.puts(logs)
  end

  def teardown_container(container)
    STDOUT.puts("Tearing down test container")
    run_command("docker container rm --force #{container}")
  end

  def emit_logs
    STDOUT.puts("Emitting container logs")
    get_containers.each { |id| emit_log(id) }
  end

  ######################################################################
  # Postgres Helpers
  ######################################################################

  def count_postgres_database(database, service = 'postgres')
    cmd = "exec -T #{service} psql -t --username=puppetdb --command=\"SELECT count(datname) FROM pg_database where datname = '#{database}'\""
    docker_compose(cmd)[:stdout].strip
  end

  def wait_on_postgres_db(database = 'puppetdb', seconds = 240, service = 'postgres')
    return retry_block_up_to_timeout(seconds) do
      count_postgres_database(database, service) == '1' ? '1' :
        raise("database #{database} never created")
    end
  end

  def get_postgres_extensions(service: 'postgres')
    return retry_block_up_to_timeout(30) do
      query = "exec -T #{service} psql --username=puppetdb --command=\"SELECT * FROM pg_extension\""
      extensions = docker_compose(query)[:stdout].chomp
      raise('failed to retrieve extensions') if extensions.empty?
      STDOUT.puts("retrieved extensions: #{extensions}")
      extensions
    end
  end

  ######################################################################
  # PuppetDB Helpers
  ######################################################################

  # @deprecated - remove method once all callers are updated
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

  # @deprecated - remove method once all callers are updated
  def wait_on_puppetdb_status(seconds = 300)
    wait_on_service_health('puppetdb', seconds)
  end

  ######################################################################
  # PE Console Services Helper
  ######################################################################
  def unrevoke_console_admin_user(postgres_container_name = "postgres")
    query = "exec -T #{postgres_container_name} psql --username=puppetdb --dbname=pe-rbac --command \"UPDATE subjects SET is_revoked = 'f' WHERE login='admin';\""
    output = docker_compose(query)[:stdout].chomp
    raise('failed to unrevoke the admin account') if ! output.eql? "UPDATE 1"
  end

  def curl_pe_console_services(end_point)
    curl('localhost', 4433, end_point).body
  end

  def get_pe_console_services_status()
    curl_pe_console_services("status/v1/simple")
  end

  def wait_for_pe_console_services()
    # 5 minute timeout to wait for a fresh "install" of PE
    timeout = 5 * 60
    puts "Waiting for pe-console-services to be ready ..."
    return retry_block_up_to_timeout(timeout) do
      get_pe_console_services_status == 'running' ? 'running' :
        raise("pe-console-services was not ready after #{timeout} seconds")
    end
  end

  def generate_rbac_token()
    uri = URI.parse("https://localhost:4433/rbac-api/v1/auth/token")
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request.body = JSON.dump({
                               "login" => "admin",
                               "password" => "admin",
                               "lifetime" => "1h"
                             })
    req_options = {
      use_ssl: uri.scheme == "https",
      verify_mode: OpenSSL::SSL::VERIFY_NONE,
    }
    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    @rbac_token = JSON.parse(response.body)['token']
  end

  ######################################################################
  # PE Orchestrator Helpers
  ######################################################################

  def curl_pe_orchestration_services(end_point)
    curl('localhost', 8143, end_point).body
  end

  def get_pe_orchestration_services_status()
    curl_pe_orchestration_services("orchestrator/v1")
  end

  def wait_for_pe_orchestration_services()
    wait_for_pe_console_services()
    unrevoke_console_admin_user()
    generate_rbac_token()
    timeout = 2 * 60
    puts "Waiting for pe-orchestration-services to be ready ..."
    return retry_block_up_to_timeout(timeout) do
      unless get_pe_orchestration_services_status.include? "Application Management API"
        raise("pe-orchestration-services was not ready after #{timeout} seconds")
      end
    end
  end

  ######################################################################
  # PE Bolt Server Helpers
  ######################################################################

  def curl_job_number(job_number, timeout = 30)
    #Wait for 30 seconds for the task to run
    puts "Waiting for the task to run..."
    return retry_block_up_to_timeout(timeout) do
      output = curl('localhost', 443, "api/jobs/#{job_number}").body
      puts output
      output !~ /running/ ? output :
        raise("Job was still running after #{timeout} seconds")
    end
    return output
  end

  def curl_console_task(target_nodes)
    uri = URI.parse("https://localhost:443/api/tasks/create")
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request["X-Authentication"] = @rbac_token
    request.body = JSON.dump({
                               "nodes" => [
                                 target_nodes
                               ],
                               "targets" => [
                                 {
                                   "transport" => "ssh",
                                   "user" => "root",
                                   "password" => "root",
                                   "hostnames" => [
                                     target_nodes
                                   ]
                                 }
                               ],
                               "task" => "service",
                               "params" => [
                                 {
                                   "name" => "action",
                                   "value" => "status"
                                 },
                                 {
                                   "name" => "name",
                                   "value" => "sshd"
                                 }
                               ]
                             })
    req_options = {
      use_ssl: uri.scheme == "https",
      verify_mode: OpenSSL::SSL::VERIFY_NONE,
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    return response.body
  end

  ######################################################################
  # Puppetserver Helpers
  ######################################################################

  # @deprecated - remove method once all callers are updated
  # Waits for the container healthcheck to return 'healthy'
  # See also: `wait_for_puppetserver`
  def wait_on_puppetserver_status(seconds = 180, service_name = 'puppet')
    wait_on_service_health(service_name, seconds)
  end

  def get_puppetserver_status()
    curl('localhost', 8140, 'status/v1/simple').body
  end

  # Waits for the `status/v1/simple` endpoint to return 'running'
  # See also: `wait_on_puppetserver_status`
  def wait_for_puppetserver(timeout: 180)
    puts "Waiting for puppetserver to be ready ..."
    return retry_block_up_to_timeout(timeout) do
      get_puppetserver_status == 'running' ? 'running' :
        raise("puppetserver was not ready after #{timeout} seconds")
    end
  end

  # agent_name is the fully qualified name of the node
  def clean_certificate(agent_name, service: 'puppet')
    STDOUT.puts "cleaning cert for #{agent_name}"
    result = docker_compose("exec -T #{service} puppetserver ca clean --certname #{agent_name}")
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
  def run_agent(agent_name, network, server: get_container_hostname(get_service_container('puppet')), ca: get_container_hostname(get_service_container('puppet')), masterport: 8140, ca_port: nil)
    # default ca_port to masterport if unset
    ca_port = masterport if ca_port.nil?

    # setting up a Windows TTY is difficult, so we don't
    # allocating a TTY will show container pull output on Linux, but that's not good for tests
    STDOUT.puts("running agent #{agent_name} in network #{network} against #{server}")
    result = run_command("docker run --rm --network #{network} --name #{agent_name} --hostname #{agent_name} puppet/puppet-agent-ubuntu agent --verbose --onetime --no-daemonize --summarize --server #{server} --masterport #{masterport} --ca_server #{ca} --ca_port #{ca_port}")
    return result[:status].exitstatus
  end

  # agent_name is the fully qualified name of the node
  def check_report(agent_name)
    pdb_uri = URI::join(get_service_base_uri('puppetdb', 8080), '/pdb/query/v4')
    body = "{ \"query\": \"nodes { certname = \\\"#{agent_name}\\\" } \" }"

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

  def wait_for_pxp_agent_to_connect(service: 'puppet-agent')
    puts "Waiting for the puppet-agent's pxp-agent to connect to the pe-orchestration-service"
    return retry_block_up_to_timeout(100) do
      command = "#{service} cat /var/log/puppetlabs/pxp-agent/pxp-agent.log"
      output = docker_compose("exec -T #{command}")
      raise('pxp-agent has not connected after 180 seconds') if !output[:stdout].include?('Starting the monitor task')
    end
  end

end
end
