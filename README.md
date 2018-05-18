# Cosmos::CcsdsTransferFrames

This gem contains a [CCSDS](https://public.ccsds.org/default.aspx) transfer frame protocol for use with the [Ball Aerospace COSMOS application](http://cosmosrb.com).

The protocol extracts CCSDS space packets from CCSDS transfer frames, optionally prefixing each packet with the transfer frame headers of the frame where it started.

See [CCSDS 132.0-B-2 - TM Space Data Link Protocol. Blue Book.](https://public.ccsds.org/Pubs/132x0b2.pdf) and [CCSDS 133.0-B-1 - Space Packet Protocol. Blue Book.](https://public.ccsds.org/Pubs/133x0b1c2.pdf) for detailed information.

## Installation

This gem is intended to be installed as a [gem based target/tool](http://cosmosrb.com/docs/gemtargets/) in COSMOS and made available for use as a normal protocol in a target command and telemetry server configuration. Note that the protocol provided in this gem is neither a target nor a tool in the COSMOS sense.

In order to make this protocol available for use in your COSMOS targets, add this line to the Gemfile of your COSMOS project:

```ruby
gem 'cosmos-ccsds_transfer_frames'
```

and then execute

```sh
$ bundle
```

## Usage

In order to use this protocol in your COSMOS target first make sure to add the following to the `target.txt` file for your target:

```
REQUIRE cosmos/ccsds_transfer_frames
```

Then add the protocol in the command and telemetry server configuration in an interface definition as usual. The full explicit module namespace `Cosmos::CcsdsTransferFrames::CcsdsTransferFrameProtocol` is necessary.

For example:

```
INTERFACE INTERFACE_NAME tcpip_client_interface.rb localhost 12345 12345 10.0 nil
  PROTOCOL READ Cosmos::CcsdsTransferFrames::CcsdsTransferFrameProtocol 1115 0 true true
  TARGET TARGET_NAME
```

would set up the protocol to expect transfer frames with:

* A total size of 1115 bytes.
* No secondary header.
* Operational control field.
* Frame error control field.

and to perform:

* No prefixing of packets (default).
* Discarding of idle packets (default).

Another example:

```
INTERFACE INTERFACE_NAME tcpip_client_interface.rb localhost 12345 12345 10.0 nil
  PROTOCOL READ Cosmos::CcsdsTransferFrames::CcsdsTransferFrameProtocol 1115 64 false false true true
  TARGET TARGET_NAME
```

would set up the protocol to expect transfer frames with:

* A total size of 1115 bytes.
* A secondary header with a size of 64 bytes.
* No operational control field.
* No frame error control field.

and to perform:

* Prefixing of packets.
* No discarding of idle packets.

For detailed information about the available configuration parameters for the protocol, please consult the yard inline source code documentation in [ccsds_transfer_frame_protocol.rb](lib/cosmos/ccsds_transfer_frames/ccsds_transfer_frame_protocol.rb) or the generated documentation for the currently published gem at https://www.rubydoc.info/gems/cosmos-ccsds_transfer_frames/Cosmos/CcsdsTransferFrames/CcsdsTransferFrameProtocol

## Development

[![Build Status](https://travis-ci.org/ienorand/cosmos-ccsds_transfer_frames.svg?branch=master)](https://travis-ci.org/ienorand/cosmos-ccsds_transfer_frames)

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in the gemspec file, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ienorand/cosmos-ccsds_transfer_frames. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.

A copy of the GPLv3.0 is provided in [LICENSE.txt](LICENSE.txt).

## Code of Conduct

Everyone interacting in the Cosmos::CcsdsTransferFrames project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/ienorand/cosmos-ccsds_transfer_frames/blob/master/CODE_OF_CONDUCT.md).
