require_relative './version'
require 'json'
require 'net/http'
require 'open3'
require 'timeout'
require 'openssl'
require 'stringio'

module Pupperware
module SpecHelpers

  class ContainerNotFoundError < StandardError; end

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

  # Returns hash with `status`, `stdout`, and `stderr` keys
  # Use `result[:status].exitstatus` to get the exit code.
  # You may want to call `.chomp` on the stdout/stderr values.
  def run_command(env = ENV.to_h, command, stream: STDOUT)
    stdout_string = ''
    stderr_string = ''
    status = nil

    Open3.popen3(env, command) do |stdin, stdout, stderr, wait_thread|
      stdout_reader = Thread.new do
        Thread.current.report_on_exception = false
        stdout.each { |l| stdout_string << l and stream.puts l }
      end
      stderr_reader = Thread.new do
        Thread.current.report_on_exception = false
        # Write stderr to stdout so it's more visible and shows up
        # in spec runs even when the tests aren't reading stderr
        stderr.each { |l| stderr_string << l and stream.puts l }
      end

      stdin.close
      # wait for threads handling output to complete
      stdout_reader.join()
      stderr_reader.join()
      # wait on process exit
      status = wait_thread.value
    end

    { status: status, stdout: stdout_string, stderr: stderr_string }
  end

  def retry_block_up_to_timeout(timeout, exit_early_on_error_type: [], raise_custom_error_type: nil, &block)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    loop do
      begin
        return yield
      rescue
        raise $! if [exit_early_on_error_type].flatten.include?($!.class)
        if (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) > timeout
          raise raise_custom_error_type.nil? ?
            Timeout::Error.new :
            raise_custom_error_type.new
        end
        sleep(1)
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

  def docker_compose(command_and_args, stream: StringIO.new)
    overrides = IS_WINDOWS ?
                  'docker-compose.windows.yml' :
                  'docker-compose.override.yml'
    # Only use overrides file if it exists
    file_arg = File.file?(overrides) ? "--file #{overrides}" : ''
    file_arg += ' --file docker-compose.fixtures.yml' if File.file?('docker-compose.fixtures.yml')
    run_command("docker-compose --file docker-compose.yml #{file_arg} \
                                --no-ansi \
                                #{command_and_args}", stream: stream)
  end

  def docker_compose_up()
    docker_compose('up --detach', stream: STDOUT)
    docker_compose('images', stream: STDOUT)
    # TODO: use --all when docker-compose fixes https://github.com/docker/compose/issues/6579
    docker_compose('ps', stream: STDOUT)
    get_containers().each do |id|
      labels = (get_container_labels(id).map { |k, v| "#{k}: #{v}"} || []).join("\n")
      STDOUT.puts("Container #{id} labels:\n#{labels}\n\n")
    end
  end

  def docker_compose_down()
    docker_compose('down --volumes', stream: STDOUT)
    STDOUT.puts("Running containers in compose:")
    # TODO: use --all when docker-compose fixes https://github.com/docker/compose/issues/6579
    docker_compose('ps', stream: STDOUT)
    STDOUT.puts("Running containers in system:")
    run_command('docker ps --all')
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

  def get_service_container(service, timeout = 5)
    return retry_block_up_to_timeout(timeout, raise_custom_error_type: ContainerNotFoundError) do
      container = docker_compose("ps --quiet #{service}")[:stdout].chomp
      if container.empty?
        raise "docker-compose never started a service named '#{service}' in #{timeout} seconds"
      end

      STDOUT.puts("service named '#{service}' is hosted in container: '#{container}'")
      container
    end
  end

  # Pull images defined in the compose file. To not pull the image for a
  # particular service, supply the name of that service as it's defined
  # in the compose file.
  # Typically the ignored service will be the one under test, since in
  # that case we want to use the image we just built, not the latest released.
  def pull_images(ignore_service = nil)
    services = docker_compose('config --services')[:stdout].chomp
    if ignore_service.nil?
      puts "Pulling images"
    else
      puts "Pulling images (ignoring image for service #{ignore_service})"
      services = services.gsub(ignore_service, '')
      services = services.gsub("\n", ' ')
    end
    docker_compose("pull --quiet #{services}", stream: STDOUT)
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
    docker_compose_down()
  end

  ######################################################################
  # Docker Helpers
  ######################################################################

  def inspect_container(container, query)
    result = run_command("docker inspect \"#{container}\" --format \"#{query}\"", stream: StringIO.new)
    status = result[:stdout].chomp
    return status
  end

  # returns a Ruby object for the Health of a container
  def get_container_health_details(container)
    # docker returns string 'null' when there is no health
    json = inspect_container(container, '{{json .State.Health}}')
    json = 'null' if json.empty?
    JSON.parse(json, object_class: OpenStruct)
  end

  def get_container_healthcheck_details(container)
    # docker returns string 'null' when there is no healthcheck
    json = inspect_container(container, '{{json .Config.Healthcheck}}')
    json = 'null' if json.empty?
    JSON.parse(json, object_class: OpenStruct)
  end

  def get_container_healthcheck_timeout(container)
    check = get_container_healthcheck_details(container)
    return 180 if check.nil?

    nanoseconds_to_seconds = 1000000000

    # container won't be marked unhealthy during start period
    # then has a max number of retries over given interval before changing from starting to unhealthy
    ((check.StartPeriod || 0) + (check.Interval * check.Retries)) / nanoseconds_to_seconds
  end

  def get_container_status(container)
    inspect_container(container, '{{.State.Health.Status}}')
  end

  def get_container_name(container)
    inspect_container(container, '{{.Name}}')
  end

  def get_container_labels(container)
    json = inspect_container(container, '{{json .Config.Labels}}')
    json = 'null' if json.empty?
    JSON.parse(json) || {}
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

  def wait_on_service_health(service, seconds = nil)
    service_container = get_service_container(service)
    # this always runs after healthcheck timer started, so no need to wait extra time
    seconds = get_container_healthcheck_timeout(service_container) if seconds.nil?
    STDOUT.puts("Waiting up to #{seconds} seconds for service #{service} to be healthy...")

    # services with healthcheck should deal with their own timeouts
    return retry_block_up_to_timeout(seconds, exit_early_on_error_type: ContainerNotFoundError) do
      health = get_container_health_details(service_container)
      last_log = health&.Log&.last()
      log_msg = "Exit [#{last_log&.ExitCode || 'Code Unknown'}]:\n\n#{last_log&.Output || 'Log Unavailable'}"
      if get_container_state(service_container) == 'exited'
        raise ContainerNotFoundError.new("Service #{service} (container: #{service_container}) has exited\n#{log_msg}")
      end
      if health.nil?
        raise("#{service} does not define a healthcheck")
      elsif (health.Status == 'healthy' || health.Status == "'healthy'")
        STDOUT.puts("Service #{service} (container: #{service_container}) is healthy")
        return 'healthy'
      else
        raise("#{service} is not healthy - currently #{health.Status}\n#{log_msg}")
      end
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

  # this only works when a container has a single network
  def get_container_network(container)
    inspect_container(container, '{{range .NetworkSettings.Networks}}{{.NetworkID}}{{end}}')
  end

  def emit_log(container)
    container_name = get_container_name(container)
    STDOUT.puts("#{'*' * 80}\nContainer logs for #{container_name} / #{container}\n#{'*' * 80}\n")
    # run_command streams stdout / stderr
    run_command("docker logs --details --timestamps #{container} 2>&1")[:stdout]
  end

  def teardown_container(container)
    network_id = get_container_network(container)
    STDOUT.puts("Tearing down test container #{container} - disconnecting from network #{network_id}")
    run_command("docker network disconnect -f #{network_id} #{container}")
    run_command("docker container rm --force #{container}")
  end

  def emit_logs
    STDOUT.puts("Emitting container logs")
    get_containers.each { |id| emit_log(id) }
  end

  ######################################################################
  # Postgres Helpers
  ######################################################################

  # @deprecated
  def count_postgres_database(database, service = 'postgres')
    cmd = "exec -T #{service} psql -t --username=puppetdb --command=\"SELECT count(datname) FROM pg_database where datname = '#{database}'\""
    docker_compose(cmd)[:stdout].strip
  end

  # @deprecated
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

  ######################################################################
  # PE Bolt Server Helpers
  ######################################################################

  def curl_job_number(job_number:, timeout: 30)
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

  def curl_console_task(target_nodes:)
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
    STDOUT.puts("running agent #{agent_name} in network #{network} against #{server} / ca #{ca}")
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

  def wait_for_pxp_agent_to_connect(service: 'puppet-agent', timeout: 180)
    puts "Waiting for the puppet-agent's pxp-agent to connect to the pe-orchestration-service"
    return retry_block_up_to_timeout(timeout) do
      command = "cat /var/log/puppetlabs/pxp-agent/pxp-agent.log"
      output = docker_compose("exec -T #{service} #{command}")
      raise("pxp-agent has not connected after #{timeout} seconds") if !output[:stdout].include?('Starting the monitor task')
    end
  end

end
end
