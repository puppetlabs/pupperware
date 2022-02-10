
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "pupperware/version"

Gem::Specification.new do |spec|
  spec.name          = "pupperware"
  spec.version       = Pupperware::VERSION
  spec.authors       = ["Iristyle"]
  spec.email         = ["Iristyle@github"]

  spec.summary       = %q{Shared testing code for Pupperware projects}
  spec.description   = %q{Shared testing code for Pupperware projects}
  spec.homepage      = "https://github.com/puppetlabs/pupperware"

  # Need Ruby 2.5+ for timeout-related features
  spec.required_ruby_version = '>= 2.5'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'thwait', '~> 0.2'
end
