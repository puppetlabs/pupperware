require 'open3'

module Helpers
  def run_command(command)
    status = nil
    STDOUT.puts "Executing #{command}"
    Open3.popen2e(command) do |stdin, stdout_stderr, wait_thread|
      Thread.new do
        stdout_stderr.each { |l| STDOUT.puts l }
      end

      stdin.close
      status = wait_thread.value
    end

    status
  end
end
