
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "cosmos/ccsds_transfer_frames/version"

Gem::Specification.new do |spec|
  spec.name          = "cosmos-ccsds_transfer_frames"
  spec.version       = Cosmos::CcsdsTransferFrames::VERSION
  spec.authors       = ["Martin Erik Werner"]
  spec.email         = ["martinerikwerner@gmail.com"]

  spec.summary       = "CCSDS transfer frame protocol for use in COSMOS"
  spec.description   = <<-EOF
    A Ball Aerospace COSMOS extension gem which provides a read-only
    protocol for extracting CCSDS space packets from CCSDS transfer frames,
    optionally prefixing each packet with the transfer frame headers of the
    frame where it started.
  EOF
  spec.homepage      = "https://github.com/ienorand/cosmos-ccsds_transfer_frames"
  spec.license       = "GPL-3.0"

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
