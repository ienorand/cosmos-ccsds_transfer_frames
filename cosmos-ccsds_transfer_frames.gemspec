
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "cosmos-ccsds_transfer_frames"
  spec.version       = "0.1.0"
  spec.authors       = ["Fredrik Persson", "Martin Erik Werner"]
  spec.email         = ["u.fredrik.persson@gmail.com", "martinerikwerner@gmail.com"]

  spec.summary       = "CCSDS transfer frame protocol for use in COSMOS"
  spec.description   = <<-EOF
    A Ball Aerospace COSMOS 'tool' gem which provides a read-only protocol
    for extracting CCSDS space packets from CCSDS transfer frames, optionally
    prefixing each packet, with the transfer frame headers of the frame where
    it started.
  EOF
  spec.homepage      = "TODO: Put your gem's website or public repo URL here."
  spec.license       = "GPL-3.0"

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

  spec.add_dependency "cosmos", "~> 4"

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "ruby-termios", "~> 0.9"
end
