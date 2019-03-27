require 'open3'

module Helpers
  def run_command(command)
    stdout_string = ''
    status = nil

    Open3.popen3(command) do |stdin, stdout, stderr, wait_thread|
      Thread.new do
        stdout.each { |l| stdout_string << l; STDOUT.puts l }
      end
      Thread.new do
        stderr.each { |l| STDOUT.puts l }
      end

      stdin.close
      status = wait_thread.value
    end

    { status: status, stdout: stdout_string }
  end

  def get_containers
    result = run_command('docker-compose --no-ansi --log-level INFO ps -q')
    ids = result[:stdout].chomp
    STDOUT.puts("Retrieved running container ids:\n#{ids}")
    ids.lines.map(&:chomp)
  end

  def inspect_container(container, query)
    result = run_command("docker inspect \"#{container}\" --format \"#{query}\"")
    status = result[:stdout].chomp
    STDOUT.puts "queried #{query} of #{container}: #{status}"
    return status
  end

  def get_container_status(container)
    inspect_container(container, '{{.State.Health.Status}}')
  end

  def get_service_container(service, timeout = 120)
    result = run_command("docker-compose --no-ansi ps --quiet #{service}")
    container = result[:stdout].chomp
    Timeout::timeout(timeout) do
      while container.empty?
        sleep(1)
        result = run_command("docker-compose --no-ansi ps --quiet #{service}")
        container = result[:stdout].chomp
      end
    end

    STDOUT.puts("service named '#{service}' is hosted in container: '#{container}'")
    return container
  rescue Timeout::Error
    msg = "docker-compose never started a service named '#{service}'"
    STDOUT.puts(msg)
    raise msg
  end

  def get_service_base_uri(service, port)
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
end
