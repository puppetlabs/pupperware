require_relative './version'
require 'json'
require 'net/http'
require 'open3'
require 'timeout'
require 'openssl'
require 'stringio'
require 'thwait'
require 'time'
require 'yaml'

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
        stdout.each { |l| stdout_string << l and stream.puts l and stream.flush() }
      end
      stderr_reader = Thread.new do
        Thread.current.report_on_exception = false
        # Write stderr to stdout so it's more visible and shows up
        # in spec runs even when the tests aren't reading stderr
        stderr.each { |l| stderr_string << l and stream.puts l and stream.flush() }
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

  # Retries a given block in one seconds intervals, up to the given timeout,
  # until the block does not raise an error.
  #
  # @param timeout [Integer] how long to keep retrying the given block for
  #                          note the block is not guaranteed to complete by this timeout
  #                          instead, it's only guaranteed to no longer be executed
  #                          again if a successful execution has not yet been made
  # @exit_early_on [Proc]    when the block errors, this provides an optional
  #                          anonymous function to run on the raised error
  #                          if the function returns true, nil is returned early
  #                          from this method, even if timeout seconds have not elapsed
  # @raise_custom_error_type [Class] When specified, a custom error is raised
  #                          instead of raising a Timeout::Error if the timeout
  #                          value elapses without the block raising an error
  # @return [Object]         the return value of the block
  def retry_block_up_to_timeout(timeout, exit_early_on: -> e { false }, raise_custom_error_type: nil, &block)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    loop do
      begin
        return yield
      rescue
        # if this anonymous function returns true, exit without error
        return nil if exit_early_on.($!)
        waited = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        if waited > timeout
          raise raise_custom_error_type.nil? ?
            Timeout::Error.new("Waited #{waited.round(2)} seconds (timeout #{timeout})") :
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
      ciphers: 'DEFAULT:!DH',
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

  def docker_compose_config()
    YAML.safe_load(docker_compose('config')[:stdout].chomp)
  end

  def docker_compose_up()
    docker_compose('config', stream: STDOUT)
    docker_compose('up --no-start', stream: STDOUT)
    docker_compose_preload_cert_volumes() if ENV['PRELOAD_CERTS'] == '1'
    docker_compose('up --detach', stream: STDOUT)
    docker_compose('images', stream: STDOUT)
    wait_on_stack_healthy()
    # TODO: use --all when docker-compose fixes https://github.com/docker/compose/issues/6579
    docker_compose('ps', stream: STDOUT)
    get_containers().each do |id|
      labels = (get_container_labels(id).map { |k, v| "#{k}: #{v}"} || []).join("\n")
      STDOUT.puts("Container #{id} labels:\n#{labels}\n\n")
    end
  end

  def docker_compose_down()
    docker_compose('down --volumes --remove-orphans', stream: STDOUT)
    STDOUT.puts("Running containers in compose:")
    # TODO: use --all when docker-compose fixes https://github.com/docker/compose/issues/6579
    docker_compose('ps', stream: STDOUT)
    STDOUT.puts("Running containers in system:")
    run_command('docker ps --all')
  end

  def docker_compose_preload_cert_volumes()
    config = docker_compose_config()
    # list of available certs for services
    cert_path = Pathname.new(File.join(__dir__, 'certs'))
    named_volumes = config['volumes'].keys

    config['services'].each do |service_name, service|
      # for services that have certs
      source = cert_path.join(service_name)
      next unless source.directory?

      # where the first service volume name is a registered volume
      next if service['volumes'].nil?
      # user-specified ENV var can select the volume when container has multiple
      volume = service['environment']['CERT_VOLUME'] ||
        service['volumes'].map { |v| v.split(':') }.first[0]
      next unless named_volumes.include?(volume)
      labels = config['volumes'][volume]['labels']

      # containers don't need to be running to copy data to their volumes
      STDOUT.puts("Pre-loading certificates for service #{service_name}")
      docker_volume_cp(src_path: source, dest_volume: volume, dest_dir: 'certs',
        uid: labels ? labels['com.puppet.certs.uid'] : nil,
        gid: labels ? labels['com.puppet.certs.gid'] : nil)
    end
  end

  # takes a given src_path, and copies files to the dest_dir of dest_volume
  # uses a transient Alpine container to copy with instead of `docker cp`
  # initially built to support both Linux and LCOW, even though LCOW no longer in use
  def docker_volume_cp(src_path:, dest_volume:, dest_dir:, is_compose: true, uid:, gid:)
    uid ||= 'root'
    gid ||= 'root'
    if is_compose
      prefix = ENV['COMPOSE_PROJECT_NAME'] || File.basename(Dir.pwd)
      dest_volume = "#{prefix}_#{dest_volume}"
    end
    # create a temp container that bind mounts src_path files
    # and copies them to the appropriate volume
    cmd = "docker run \
      --rm \
      --volume #{src_path}:/tmp/src \
      --volume #{dest_volume}:/opt \
      alpine:3.10 \
      /bin/sh -c \"cp -r /tmp/src /opt/#{dest_dir}; chown -R #{uid}:#{gid} /opt/#{dest_dir}\""
    STDOUT.puts(<<-MSG)
Copying existing files through transient container:
  from         : #{src_path}
  to volume    : #{dest_volume}/#{dest_dir}
  with uid:gid : #{uid}:#{gid}
MSG
    run_command(cmd)
  end

  # will simultaneously wait on all containers with healthchecks defined
  def wait_on_stack_healthy()
    threads = []
    mutex = Mutex.new
    cancel = false

    get_containers().each do |id|
      # skip those without healthchecks
      next if get_container_healthcheck_details(id).nil?
      threads << Thread.new do
        # this must be set for the waiting to re-raise the thread
        Thread.current.abort_on_exception = true
        Thread.current.report_on_exception = false

        begin
          exit_early_on = -> err {
            raise err if ContainerNotFoundError == err.class
            mutex.synchronize do
              # check if any containers has failed to wait and stop waiting if necessary
              STDOUT.puts("Abandoning healthy wait for container: #{id}!") if cancel
              return cancel
            end
          }
          wait_on_container_health(container: id, exit_early_on: exit_early_on)
        # waiting for healthy has failed due to a dead container or failing healthcheck
        rescue
          STDOUT.puts("ERROR: #{$!.class} (#{$!.message}) while waiting for healthy container: #{id}! Cancelling other waiters.")
          # set cancel so that all other threads will stop executing prematurely
          mutex.synchronize { cancel = true  }
          raise
        end
      end
    end

    # WARN: this is a global setting, this will prevent stack trace noise from showing in spec logs
    # setting it for just the ThreadsWait waiter thread is not possible
    Thread.report_on_exception = false
    # Wait on all threads to complete and one of a few things happens:
    # * all containers are healthy, none error and the wait is a success
    # * one container fails, and throws an exception, teling all the others to cancel
    #   and the exception is immediately raised here (other threads will gc)
    waiter = ThreadsWait.new(threads)
    begin
      waiter.all_waits()
    rescue
      # wait for all other threads to cancel (ignoring any exceptions) so logs are ordered correctly
      waiter.threads.each do |thr|
        begin thr.join() if thr.alive? rescue nil end
      end
      # re-raise the exception from first failing thread
      raise
    end
  end

  def restart_stack()
    STDOUT.puts("Restarting cluster")
    clear_service_base_uri_cache()

    # get current restart counts
    restarts = get_containers().each_with_object({}) do |container, h|
      h[container] = get_container_restart_count(container)
    end

    # restart the cluster
    docker_compose('restart', stream: STDOUT)

    # make sure each container increments its restart count by 1
    # the waiting implementation is a little hokey given it requires the prior count
    # but that removes the need for complex threading / synchronization
    restarts.each_pair do |container, count|
      wait_on_container_restart(container: container, prior_count: count)
    end

    # and then wait for all containers to be marked healthy
    wait_on_stack_healthy()
  end

  # https://github.com/moby/moby/issues/39922
  # Each launched VM (and correspondingly container) is run under a unique Windows
  # user account (in this case a random GUID) to run it's vmwp.exe host process.
  # So the docker volume that gets created needs to have the FullControl permission
  # granted to that specific user that owns the VM / container, but that's not
  # currently the case.
  #
  # Until the bug can be fixed, grant the NT VIRTUAL MACHINE\Virtual Machines
  # group FullControl to a specific path so that operations like symlink
  # creation will succeed from inside Linux Containers
  #
  # Note this helper can't work under the usual C:\ProgramData\Docker\volumes
  # directory when called by the Azure CI agent, which is a lower privilege
  # account without access to permissions in that directory
  def grant_windows_vm_group_full_permissions(path)
    # icacls can't have trailing slashes in the path, so remove with expand_path
    run_command("icacls \"#{File.expand_path(path)}\" /grant *S-1-5-83-0:\"(OI)(CI)F\" /T")
  end

  # Windows requires directories to exist prior, whereas Linux will create them
  # @deprecated
  def create_host_volume_targets(root, volumes)
    return unless IS_WINDOWS

    STDOUT.puts("Creating volumes directory structure in #{root}")
    volumes.each { |subdir| FileUtils.mkdir_p(File.join(root, subdir)) }
    grant_windows_vm_group_full_permissions(root)
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
      services.sub!(/^#{ignore_service}$/, '')
    end
    services.gsub!("\n", ' ')
    docker_compose("pull --quiet #{services}", stream: STDOUT)
  end

  def clear_service_base_uri_cache
    @mapped_ports = {}
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
    raise ContainerNotFoundError.new(container) if result[:status].exitstatus != 0
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

  def get_container_restart_count(container)
    inspect_container(container,'{{.RestartCount}}')
  end

  def get_container_uptime_seconds(container)
    started_at = Time.parse(inspect_container(container, '{{ .State.StartedAt }}'))
    Time.now.utc - started_at
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

  # this method assumes that the previous restart count is queried prior to restart / is passed in
  def wait_on_container_restart(container: nil, prior_count: nil, seconds: 20)
    service = get_container_labels(container)['com.docker.compose.service'] || 'N/A'
    return retry_block_up_to_timeout(seconds) do
      prior_count == get_container_restart_count(container) ? true :
      raise("Service #{service} (container: #{container}) never restarted")
    end
  end

  def wait_on_service_health(service, seconds = nil, exit_early_on: nil)
    service_container = get_service_container(service)
    wait_on_container_health(container: service_container, seconds: seconds, exit_early_on: exit_early_on)
  end

  def wait_on_container_health(container:, seconds: nil, exit_early_on:)
    service = get_container_labels(container)['com.docker.compose.service'] || 'N/A'
    # this always runs after healthcheck timer started, so no need to wait extra time
    seconds = get_container_healthcheck_timeout(container) if seconds.nil?
    # only allow one iteration if container has already been up longer than its healthcheck
    if (uptime = Integer(get_container_uptime_seconds(container))) > seconds
      seconds = 1
      STDOUT.puts("Already running #{uptime} seconds - skipping additional waiting on service #{service} (container: #{container}) to be healthy...")
    else
      seconds -= uptime
      STDOUT.puts("Waiting up to #{seconds} seconds (running #{uptime} already) for service #{service} (container: #{container}) to be healthy...")
    end

    # services with healthcheck should deal with their own timeouts
    exit_early_on ||= -> err {
      raise err if ContainerNotFoundError == err.class
      false
    }
    return retry_block_up_to_timeout(seconds, exit_early_on: exit_early_on) do
      health = get_container_health_details(container)
      last_log = health&.Log&.last()
      container_log = run_command("docker logs --tail 3 --details #{container} 2>&1", stream: StringIO.new)[:stdout].chomp
      log_msg = <<-LOG
Exit [#{last_log&.ExitCode || 'Code Unknown'}]:

Healthcheck Logs:
===========================================================
#{last_log&.Output || 'Unavailable'}

Container Logs:
===========================================================
#{container_log}
LOG
      if get_container_state(container) == 'exited'
        raise ContainerNotFoundError.new("Service #{service} (container: #{container}) has exited\n#{log_msg}")
      end
      if health.nil?
        raise("#{service} does not define a healthcheck")
      elsif (health.Status == 'healthy' || health.Status == "'healthy'")
        up = get_container_uptime_seconds(container)
        STDOUT.puts("Service #{service} (container: #{container}) is healthy - running #{up.round(1)} seconds")
        return 'healthy'
      else
        raise("Service #{service} (container: #{container}) is not healthy - currently #{health.Status}\n#{log_msg}")
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
    container_name = begin get_container_name(container) rescue 'N/A' end
    STDOUT.puts("#{'*' * 80}\nContainer logs for #{container_name} / #{container}\n#{'*' * 80}\n")
    # run_command streams stdout / stderr
    run_command("docker logs --details --timestamps #{container} 2>&1", stream: STDOUT)
    STDOUT.puts("#{'*' * 80}\nEnd container logs for #{container_name} / #{container}\n#{'*' * 80}\n\n")
  end

  def teardown_container(container)
    network_id = begin get_container_network(container) rescue nil end
    if !network_id.nil? && !network_id.empty?
      STDOUT.puts("Tearing down test container #{container} - disconnecting from network #{network_id}")
      run_command("docker network disconnect --force #{network_id} #{container}")
    end
    run_command("docker container rm --force #{container}")
  end

  def emit_logs
    STDOUT.puts("Emitting container logs")
    get_containers.each { |id| emit_log(id) }
  end

  def kill_service_and_wait_for_return(service: nil, process: nil, timeout: 20)
    container = get_service_container(service)
    restart_count = get_container_restart_count(container)
    docker_compose("exec -T #{service} pkill #{process}")

    wait_on_container_restart(container: container, prior_count: restart_count)
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

  def generate_rbac_token(rbac_username: 'admin', rbac_password: 'pupperware')
    uri = URI.parse("https://localhost:4433/rbac-api/v1/auth/token")
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request.body = JSON.dump({
                               "login" => rbac_username,
                               "password" => rbac_password,
                               "lifetime" => "1h"
                             })
    req_options = {
      use_ssl: uri.scheme == "https",
      verify_mode: OpenSSL::SSL::VERIFY_NONE,
      ciphers: 'DEFAULT:!DH',
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

  def orchestrate_puppet_run(
        target_agent: 'puppet-agent',
        network: 'pupperware-commercial',
        rbac_username: 'admin',
        rbac_password: 'pupperware',
        puppetserver: 'puppet',
        pe_console_services: 'pe-console-services',
        pe_orchestration_services: 'pe-orchestration-services',
        image: 'artifactory.delivery.puppetlabs.net/pe-and-platform/pe-client-tools:latest'
      )
    run_command("docker pull #{image}")
    run_command("docker run \
           --rm \
           --network #{network} \
           --env RBAC_USERNAME=#{rbac_username} \
           --env RBAC_PASSWORD=#{rbac_password} \
           --env PUPPETSERVER_HOSTNAME=#{puppetserver} \
           --env PE_CONSOLE_SERVICES_HOSTNAME=#{pe_console_services} \
           #{image} \
           puppet-job run \
              --nodes #{target_agent} \
              --service-url https://#{pe_orchestration_services}:8143/")
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
      ciphers: 'DEFAULT:!DH',
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

  def run_agent(agent_name, network, server: get_container_hostname(get_service_container('puppet')), ca: get_container_hostname(get_service_container('puppet')), masterport: 8140, ca_port: nil)
    # default ca_port to masterport if unset
    ca_port = masterport if ca_port.nil?

    # setting up a Windows TTY is difficult, so we don't
    # allocating a TTY will show container pull output on Linux, but that's not good for tests
    STDOUT.puts("running agent #{agent_name} in network #{network} against #{server} / ca #{ca}")
    # In certain environments (like Travis), the hosts dns suffix may be appended
    # to the agents name, making an agent name become foo.travis.internal rather
    # than simply foo, which makes identifying that agent in reports difficult later
    # Docker flags --domainname --dns-opt --network-alias and --dns-search do not
    # seem to influence this behavior, but the agents certname can be set!
    result = run_command("docker run --rm --network #{network} --name #{agent_name} --hostname #{agent_name} puppet/puppet-agent-ubuntu agent --verbose --onetime --no-daemonize --summarize --server #{server} --certname #{agent_name} --masterport #{masterport} --ca_server #{ca} --ca_port #{ca_port}")
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

  def wait_for_pxp_agent_to_connect(agent_name: 'puppet-agent', timeout: 180)
    generate_rbac_token()
    puts "Waiting for the puppet-agent's pxp-agent to connect to the pe-orchestration-service"
    return retry_block_up_to_timeout(timeout) do
      raise("pxp-agent has not connected after #{timeout} seconds") if !JSON.parse(curl_pe_orchestration_services("orchestrator/v1/inventory/#{agent_name}"))['connected']
    end
  end

end
end
