# encoding: ascii-8bit

# Copyright 2018 Martin Erik Werner <martinerikwerner@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'spec_helper'
require 'cosmos/interfaces/interface'
require 'cosmos/streams/stream'
require 'cosmos/ccsds_transfer_frames/ccsds_transfer_frame_protocol'

module Cosmos
  module CcsdsTransferFrames
    describe CcsdsTransferFrameProtocol do
      before(:each) do
        @interface = StreamInterface.new
        allow(@interface).to receive(:connected?) { true }
      end

      describe "initialize" do

        shared_examples "a protocol with an empty data buffer" do
          it "clears the data buffer" do
            expect(@interface.read_protocols[0].instance_variable_get(:@data)).to eq ''
          end
        end

        shared_examples "a protocol with initialised empty virtual channels" do
          it "initialises the correct amount of virtual channels" do
            expect(@interface.read_protocols[0].instance_variable_get(:@virtual_channels).length).to eq 8
          end

          it "resets the data of each virtual channel" do
            @interface.read_protocols[0].instance_variable_get(:@virtual_channels).each do |vc|
              expect(vc.packet_queue).to eq []
              expect(vc.pending_incomplete_packet_bytes_left).to eq 0
            end
          end
        end

        context "is setup for a transfer frame of size 1115 with operational control field and frame errors control" do
          before do
            @interface.add_protocol(
              CcsdsTransferFrameProtocol,
              [1115, 0, true, true],
              :READ)
          end

          it_behaves_like "a protocol with an empty data buffer"
          it_behaves_like "a protocol with initialised empty virtual channels"

          it "initialises instance variables by parameters" do
            expect(@interface.read_protocols[0].instance_variable_get(:@frame_length)).to eq 1115
            expect(@interface.read_protocols[0].instance_variable_get(:@frame_headers_length)).to eq 6 + 0
            expect(@interface.read_protocols[0].instance_variable_get(:@frame_trailer_length)).to eq 4 + 2
            expect(@interface.read_protocols[0].instance_variable_get(:@prefix_packets)).to eq false
            expect(@interface.read_protocols[0].instance_variable_get(:@include_idle_packets)).to eq false
          end
        end

        context "is setup for a transfer frame of size 1115 with a secondary header, prefixing of packets, and inclusion of idle packets" do
          before do
            @interface.add_protocol(
              CcsdsTransferFrameProtocol,
              [1115, 7, false, false, true, true],
              :READ)
          end

          it_behaves_like "a protocol with an empty data buffer"
          it_behaves_like "a protocol with initialised empty virtual channels"

          it "initialises instance variables by parameters" do
            expect(@interface.read_protocols[0].instance_variable_get(:@frame_length)).to eq 1115
            expect(@interface.read_protocols[0].instance_variable_get(:@frame_headers_length)).to eq 6 + 7
            expect(@interface.read_protocols[0].instance_variable_get(:@frame_trailer_length)).to eq 0 + 0
            expect(@interface.read_protocols[0].instance_variable_get(:@prefix_packets)).to eq true
            expect(@interface.read_protocols[0].instance_variable_get(:@include_idle_packets)).to eq true
          end
        end
      end

      describe "read" do
        context "is setup for a minimal transfer frame" do
          before do
            @interface.add_protocol(CcsdsTransferFrameProtocol, [
              # Transfer frame length, 7 bytes data field (minimum space packet length).
              6 + 0 + 7 + 0 + 0,
              0, # secondary header length
              false, # does not have operational control field
              false], # does not have frame error control
              :READ)
          end

          context "is not the last protocol in a chain" do
            before do
              # Second dummy protocol, since CcsdsTransferFrameProtocol should only
              # forward empty data if it is not the last protocol in the chain.
              @interface.add_protocol(Protocol, [], :READ)
            end

            context "no whole packets are ready" do
              context "receives an empty string" do
                before do
                  @packet_data = @interface.read_protocols[0].read_data("")
                end

                it "returns an empty string" do
                  expect(@packet_data).to eql ""
                end
              end
            end

            context "a whole packet is ready" do
              before do
                @interface.read_protocols[0].instance_variable_get(:@virtual_channels)[0].packet_queue =
                  ["\x01\x02\x03\x04\x00\x00\xDA"]
              end

              context "receives an empty string" do
                before do
                  @packet_data = @interface.read_protocols[0].read_data("")
                end

                it "returns the packet" do
                  expect(@packet_data).to eql "\x01\x02\x03\x04\x00\x00\xDA"
                end
              end
            end
          end

          context "is the last protocol in a chain" do
            context "no whole packets are ready" do
              context "receives an empty string" do
                before do
                  @packet_data = @interface.read_protocols[0].read_data("")
                end

                it "asks for more data" do
                  expect(@packet_data).to eql :STOP
                end
              end
            end

            context "a whole packet is ready" do
              before do
                @interface.read_protocols[0].instance_variable_get(:@virtual_channels)[0].packet_queue =
                  ["\x01\x02\x03\x04\x00\x00\xDA"]
              end

              context "receives an empty string" do
                before do
                  @packet_data = @interface.read_protocols[0].read_data("")
                end

                it "returns the packet" do
                  expect(@packet_data).to eql "\x01\x02\x03\x04\x00\x00\xDA"
                end
              end
            end
          end
        end

        context "is setup for a minimal transfer frame including a secondary header and frame error control" do
          before do
            @interface.add_protocol(CcsdsTransferFrameProtocol, [
              # Transfer frame length, 7 bytes data field (minimum space packet length).
              6 + 1 + 7 + 0 + 2,
              1, # secondary header length
              false, # does not have operational control field
              true], # has frame error control
              :READ)
          end

          context "receives a frame with a packet that fills the frame" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x02\x03\x02\x05\x08\x00" +
                "\x07" +
                "\x09\x02\x0B\x05\x00\x00\xDA" +
                "\x0F\x02")
            end
            it "returns the packet" do
              expect(@packet_data.length).to eql 7
              expect(@packet_data).to eql "\x09\x02\x0B\x05\x00\x00\xDA"
            end
          end
        end

        context "is setup for a tiny transfer frame including a secondary header and operational control field" do
          before do
            @interface.add_protocol(CcsdsTransferFrameProtocol, [
              # Transfer frame length, 7 bytes data field.
              6 + 2 + 7 + 4 + 0,
              2, # secondary header length
              true, # has operational control field
              false], # does not have frame error control
              :READ)
          end

          context "receives a frame with a packet that is incomplete and fills two frames" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x25\x76\x13\x44\x80\x00" +
                "\xF3\x3D" +
                "\x59\xAC\xE9\xAC\x00\x07\xDA" +
                "\x31\x11\x58\xC6")
            end

            it "asks for more data" do
              expect(@packet_data).to eql :STOP
            end

            context "recieves a frame which completes the packet" do
              before do
                @packet_data = @interface.read_protocols[0].read_data(
                  "\x26\x76\x14\x45\x87\xFF" +
                  "\xF4\x3E" +
                  "\xDA\xDA\xDA\xDA\xDA\xDA\xDA" +
                  "\x32\x12\x59\xC7")
              end

              it "returns the reassembled packet" do
                expect(@packet_data.length).to eql 7 + 7
                expect(@packet_data).to eql "\x59\xAC\xE9\xAC\x00\x07\xDA" +
                  "\xDA\xDA\xDA\xDA\xDA\xDA\xDA"
              end
            end
          end

          context "receives a frame with a packet that is incomplete and fills three frames" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x25\x77\x13\x44\x80\x00" +
                "\xF3\x3D" +
                "\x59\xAC\xE9\xAC\x00\x0E\xDA" +
                "\x31\x11\x58\xC6")
            end

            it "asks for more data" do
              expect(@packet_data).to eql :STOP
            end

            context "receives a frame with packet continuation which does not complete the packet" do
              before do
                @packet_data = @interface.read_protocols[0].read_data(
                  "\x26\x77\x14\x45\x87\xFF" +
                  "\xF4\x3E" +
                  "\xDA\xDA\xDA\xDA\xDA\xDA\xDA" +
                  "\x32\x12\x59\xC7")
              end

              it "asks for more data" do
                expect(@packet_data).to eql :STOP
              end

              context "recieves a frame which completes the packet" do
                before do
                  @packet_data = @interface.read_protocols[0].read_data(
                    "\x27\x77\x15\x46\x87\xFF" +
                    "\xF5\x3F" +
                    "\xDA\xDA\xDA\xDA\xDA\xDA\xDA" +
                    "\x33\x13\x5A\xC8")
                end

                it "returns the reassembled packet" do
                  expect(@packet_data.length).to eql 7 + 7 + 7
                  expect(@packet_data).to eql "\x59\xAC\xE9\xAC\x00\x0E\xDA" +
                    "\xDA\xDA\xDA\xDA\xDA\xDA\xDA" +
                    "\xDA\xDA\xDA\xDA\xDA\xDA\xDA"
                end
              end
            end
          end
        end

        context "is setup for a small transfer frame including a secondary header" do
          before do
            @interface.add_protocol(CcsdsTransferFrameProtocol, [
              # Transfer frame length, 27 bytes data field.
              6 + 3 + 27 + 0 + 0,
              3, # secondary header length
              false, # does not have operational control field
              false], # does not have frame error control
              :READ)
          end

          context "receives a frame with three packets" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x01\x02\x03\x04\x00\x00" +
                "\x05\x06\x07" +
                "\x08\x09\x10\x11\x00\x01\xDA\xDA" +
                "\x12\x13\x14\x15\x00\x03\xDA\xDA\xDA\xDA" +
                "\x16\x17\x18\x19\x00\x02\xDA\xDA\xDA")
            end

            it "returns the first packet" do
              expect(@packet_data.length).to eql 8
              expect(@packet_data).to eql "\x08\x09\x10\x11\x00\x01\xDA\xDA"
            end

            context "receives an empty string" do
              before do
                @packet_data = @interface.read_protocols[0].read_data("")
              end

              it "returns the second packet" do
                expect(@packet_data.length).to eql 10
                expect(@packet_data).to eql "\x12\x13\x14\x15\x00\x03\xDA\xDA\xDA\xDA"
              end

              context "receives an empty string" do
                before do
                  @packet_data = @interface.read_protocols[0].read_data("")
                end

                it "returns the third packet" do
                  expect(@packet_data.length).to eql 9
                  expect(@packet_data).to eql "\x16\x17\x18\x19\x00\x02\xDA\xDA\xDA"
                end
              end
            end
          end
        end

        context "is setup for a tiny transfer frame with one byte extra in the data field" do
          before do
            @interface.add_protocol(CcsdsTransferFrameProtocol, [
              # Transfer frame length, 8 bytes data field.
              6 + 8,
              0, # secondary header length
              false, # does not have operational control field
              false], # does not have frame error control
              :READ)
          end

          context "receives a frame with a complete packet and one byte from the next packet" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x02\x02\x03\x04\x00\x00" +
                "\x05\x06\x07\x08\x00\x00\xDA" +
                "\x09")
            end

            it "returns the first packet" do
              expect(@packet_data.length).to eql 7
              expect(@packet_data).to eql "\x05\x06\x07\x08\x00\x00\xDA"
            end

            context "receives a frame which completes the packet" do
              before do
                @packet_data = @interface.read_protocols[0].read_data(
                  "\x10\x02\x12\x13\x07\xFF" +
                  "\x14\x15\x16\x00\x02\xDA\xDA\xDA")
              end

              it "returns the reassembled second packet" do
                expect(@packet_data.length).to eql 9
                expect(@packet_data).to eql "\x09" + "\x14\x15\x16\x00\x02\xDA\xDA\xDA"
              end
            end

            context "receives a frame which does not provide any continuation and a second whole packet" do
              before do
                @packet_data = @interface.read_protocols[0].read_data(
                  "\x10\x02\x11\x12\x00\x00" +
                  "\x13\x14\x15\x16\x00\x01\xDA\xDA")
              end

              it "returns the continued packet cut short" do
                expect(@packet_data.length).to eql 1
                expect(@packet_data).to eql "\x09"
              end

              context "receives an empty string" do
                before do
                  @packet_data = @interface.read_protocols[0].read_data("");
                end

                it "returns the second packet" do
                  expect(@packet_data.length).to eql 8
                  expect(@packet_data).to eql "\x13\x14\x15\x16\x00\x01\xDA\xDA"
                end
              end
            end

            context "recieves a frame with insufficient continuation followed by a whole packet" do
              before do
                @packet_data = @interface.read_protocols[0].read_data(
                  "\x10\x02\x11\x12\x00\x01" +
                  "\x10\x13\x14\x15\x16\x00\x00\xDA")
              end

              it "returns the continued packet cut short" do
                expect(@packet_data.length).to eql 2
                expect(@packet_data).to eql "\x09\x10"
              end

              context "receives an empty string" do
                before do
                  @packet_data = @interface.read_protocols[0].read_data("");
                end

                it "returns the second packet" do
                  expect(@packet_data.length).to eql 7
                  expect(@packet_data).to eql "\x13\x14\x15\x16\x00\x00\xDA"
                end
              end
            end
          end

          context "receives a frame with an incomplete packet with one byte missing" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x01\x02\x03\x04\x00\x00" +
                "\x05\x06\x07\x08\x00\x02\xDA\xDA")
            end

            it "asks for more data" do
              expect(@packet_data).to eql :STOP
            end

            context "receives a frame which completes the packet and contains another complete packet" do
              before do
                @packet_data = @interface.read_protocols[0].read_data(
                  "\x10\x02\x12\x13\x00\x01" +
                  "\xDA" +
                  "\x14\x15\x16\x17\x00\x00\xDA")
              end

              it "returns the reassembled first packet" do
                expect(@packet_data.length).to eql 9
                expect(@packet_data).to eql "\x05\x06\x07\x08\x00\x02\xDA\xDA\xDA"
              end

              context "receives an empty string" do
                before do
                  @packet_data = @interface.read_protocols[0].read_data("")
                end

                it "returns the second packet" do
                  expect(@packet_data.length).to eql 7
                  expect(@packet_data).to eql "\x14\x15\x16\x17\x00\x00\xDA"
                end
              end
            end
          end

          context "receives a frame with no packet start" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x01\x02\x03\x04\x07\xFF" +
                "\xDA\xDA\xDA\xDA\xDA\xDA\xDA\xDA")
            end

            it "asks for more data" do
              expect(@packet_data).to eql :STOP
            end

            context "receives a frame with a packet start at second byte" do
              before do
                @packet_data = @interface.read_protocols[0].read_data(
                  "\x10\x02\x12\x13\x00\x01" +
                  "\xDA\x14\x15\x16\x17\x00\x00\xDA")
              end

              it "returns the packet" do
                expect(@packet_data.length).to eql 7
                expect(@packet_data).to eql "\x14\x15\x16\x17\x00\x00\xDA"
              end
            end
          end

          context "receives a frame with an incomplete packet with three bytes missing" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x01\x02\x03\x04\x00\x00" +
                "\x05\x06\x07\x08\x00\x04\xDA\xDA")
            end

            it "asks for more data" do
              expect(@packet_data).to eql :STOP
            end

            context "receives a frame which does not provide any continuation and a second whole packet" do
              before do
                @packet_data = @interface.read_protocols[0].read_data(
                  "\x10\x02\x11\x12\x00\x00" +
                  "\x13\x14\x15\x16\x00\x01\xDA\xDA")
              end

              it "returns the first packet cut short" do
                expect(@packet_data.length).to eql 8
                expect(@packet_data).to eql "\x05\x06\x07\x08\x00\x04\xDA\xDA"
              end

              context "receives an empty string" do
                before do
                  @packet_data = @interface.read_protocols[0].read_data("");
                end

                it "returns the second packet" do
                  expect(@packet_data.length).to eql 8
                  expect(@packet_data).to eql "\x13\x14\x15\x16\x00\x01\xDA\xDA"
                end
              end
            end

            context "receives a frame which provides insufficient continuation and a second whole packet" do
              before do
                @packet_data = @interface.read_protocols[0].read_data(
                  "\x10\x02\x11\x12\x00\x01" +
                  "\xDA\x13\x14\x15\x16\x00\x00\xDA")
              end

              it "returns the first packet cut short" do
                expect(@packet_data.length).to eql 9
                expect(@packet_data).to eql "\x05\x06\x07\x08\x00\x04\xDA\xDA\xDA"
              end

              context "receives an empty string" do
                before do
                  @packet_data = @interface.read_protocols[0].read_data("");
                end

                it "returns the second packet" do
                  expect(@packet_data.length).to eql 7
                  expect(@packet_data).to eql "\x13\x14\x15\x16\x00\x00\xDA"
                end
              end
            end
          end

          context "receives a frame with a complete packet" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x01\x02\x03\x04\x00\x00" +
                "\x05\x06\x07\x08\x00\x01\xDA\xDA")
            end

            it "returns the packet" do
              expect(@packet_data.length).to eql 8
              expect(@packet_data).to eql "\x05\x06\x07\x08\x00\x01\xDA\xDA"
            end

            context "receives a frame with one byte continuation and a second whole packet" do
              before do
                @packet_data = @interface.read_protocols[0].read_data(
                  "\x10\x02\x11\x12\x00\x01" +
                  "\xFF\x13\x14\x15\x16\x00\x00\xDA")
              end

              it "discards the continuation and returns the second packet" do
                expect(@packet_data.length).to eql 7
                expect(@packet_data).to eql "\x13\x14\x15\x16\x00\x00\xDA"
              end
            end
          end

          context "receives a frame with a complete packet and one byte from an incomplete idle packet" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x01\x02\x03\x04\x00\x00" +
                "\x05\x06\x07\x08\x00\x00\xDA" +
                "\x3F")
            end

            it "returns the first packet" do
              expect(@packet_data.length).to eql 7
              expect(@packet_data).to eql "\x05\x06\x07\x08\x00\x00\xDA"
            end

            context "recieves a frame which completes the idle packet" do
              before do
                @packet_data = @interface.read_protocols[0].read_data(
                  "\x01\x02\x03\x04\x07\xFF" +
                  "\xFF\x09\x0A\x00\x02\x5A\x5A\x5A")
              end

              it "skips the idle packet and asks for more data" do
                expect(@packet_data).to eql :STOP
              end
            end
          end

          context "receives a frame with an idle packet followed by one byte from an incomplete packet" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x01\x02\x03\x04\x00\x00" +
                "\x3F\xFF\x05\x06\x00\x00\x5A" +
                "\x07")
            end

            it "skips the idle packet and asks for more data" do
              expect(@packet_data).to eql :STOP
            end

            context "receives a frame which completes the packet" do
              before do
                @packet_data = @interface.read_protocols[0].read_data(
                  "\x01\x02\x03\x04\x07\xFF" +
                  "\x08\x09\x0A\x00\x02\xDA\xDA\xDA")
              end

              it "returns the reassembled second packet" do
                expect(@packet_data.length).to eql 9
                expect(@packet_data).to eql "\x07\x08\x09\x0A\x00\x02\xDA\xDA\xDA"
              end
            end
          end
        end

        context "is setup for a tiny transfer frame with two bytes extra in the data field" do
          before do
            @interface.add_protocol(CcsdsTransferFrameProtocol, [
              # Transfer frame length, 9 bytes data field.
              6 + 9,
              0, # secondary header length
              false, # does not have operational control field
              false], # does not have frame error control
              :READ)
          end

          context "receives a frame with an incomplete packet with one byte missing" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x01\x02\x03\x04\x00\x00" +
                "\x05\x06\x07\x08\x00\x03\xDA\xDA\xDA")
            end

            it "asks for more data" do
              expect(@packet_data).to eql :STOP
            end

            context "receives a frame which provides too much continuation and a second whole packet" do
              before do
                @packet_data = @interface.read_protocols[0].read_data(
                  "\x10\x02\x11\x12\x00\x02" +
                  "\xDA\xFF\x13\x14\x15\x16\x00\x00\xDA")
                expect(@packet_data.length).to eql 10
                expect(@packet_data).to eql "\x05\x06\x07\x08\x00\x03\xDA\xDA\xDA\xDA"
              end

              it "returns the reassembled first packet with no extra continuation" do
                expect(@packet_data.length).to eql 10
                expect(@packet_data).to eql "\x05\x06\x07\x08\x00\x03\xDA\xDA\xDA\xDA"
              end

              context "receives an empty string" do
                before do
                  @packet_data = @interface.read_protocols[0].read_data("");
                end

                it "returns the second packet (and discards the extra continuation)" do
                  expect(@packet_data.length).to eql 7
                  expect(@packet_data).to eql "\x13\x14\x15\x16\x00\x00\xDA"
                end
              end
            end
          end
        end

        context "is setup for a small transfer frame with 17 bytes data field" do
          before do
            @interface.add_protocol(CcsdsTransferFrameProtocol, [
              # Transfer frame length, 17 bytes data field.
              6 + 17,
              0, # secondary header length
              false, # does not have operational control field
              false], # does not have frame error control
              :READ)
          end

          context "receives a frame with a whole packet followed by a whole idle packet" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x01\x02\x03\x04\x00\x00" +
                "\x05\x06\x07\x08\x00\x01\xDA\xDA" +
                "\x3F\xFF\x09\x0A\x00\x02\x5A\x5A\x5A")
            end

            it "returns the first packet" do
              expect(@packet_data.length).to eql 8
              expect(@packet_data).to eql "\x05\x06\x07\x08\x00\x01\xDA\xDA"
            end

            context "receives an empty string" do
              before do
                @packet_data = @interface.read_protocols[0].read_data("")
              end

              it "skips the idle packet and asks for more data" do
                expect(@packet_data).to eql :STOP
              end
            end
          end

          context "receives a frame with a complete packet and one byte from the next packet" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x02\x02\x03\x04\x00\x00" +
                "\x05\x06\x07\x08\x00\x09\xDA\xDA\xDA\xDA\xDA\xDA\xDA\xDA\xDA\xDA" +
                "\x09")
            end

            it "returns the first packet" do
              expect(@packet_data.length).to eql 16
              expect(@packet_data).to eql "\x05\x06\x07\x08\x00\x09\xDA\xDA\xDA\xDA\xDA\xDA\xDA\xDA\xDA\xDA"
            end

            context "receives a frame which completes the packet followed by a third packet" do
              before do
                @packet_data = @interface.read_protocols[0].read_data(
                  "\x10\x02\x12\x13\x00\x08" +
                  "\x14\x15\x16\x00\x02\xDA\xDA\xDA" +
                  "\x17\x18\x19\x20\x00\x02\xDA\xDA\xDA")
              end

              it "returns the reassembled second packet" do
                expect(@packet_data.length).to eql 9
                expect(@packet_data).to eql "\x09" + "\x14\x15\x16\x00\x02\xDA\xDA\xDA"
              end

              context "recieves an empty string" do
                before do
                  @packet_data = @interface.read_protocols[0].read_data("")
                end

                it "returns the third packet" do
                  expect(@packet_data.length).to eql 9
                  expect(@packet_data).to eql "\x17\x18\x19\x20\x00\x02\xDA\xDA\xDA"
                end
              end
            end
          end

          context "receives a frame with a complete packet and five bytes from the next packet" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x02\x02\x03\x04\x00\x00" +
                "\x05\x06\x07\x08\x00\x05\xDA\xDA\xDA\xDA\xDA\xDA" +
                "\x09\x14\x15\x16\x00")
            end

            it "returns the first packet" do
              expect(@packet_data.length).to eql 12
              expect(@packet_data).to eql "\x05\x06\x07\x08\x00\x05\xDA\xDA\xDA\xDA\xDA\xDA"
            end

            context "receives a frame which completes the packet followed by a third packet" do
              before do
                @packet_data = @interface.read_protocols[0].read_data(
                  "\x10\x02\x12\x13\x00\x04" +
                  "\x02\xDA\xDA\xDA" +
                  "\x17\x18\x19\x20\x00\x06\xDA\xDA\xDA\xDA\xDA\xDA\xDA")
              end

              it "returns the reassembled second packet" do
                expect(@packet_data.length).to eql 9
                expect(@packet_data).to eql "\x09" + "\x14\x15\x16\x00\x02\xDA\xDA\xDA"
              end

              context "recieves an empty string" do
                before do
                  @packet_data = @interface.read_protocols[0].read_data("")
                end

                it "returns the third packet" do
                  expect(@packet_data.length).to eql 13
                  expect(@packet_data).to eql "\x17\x18\x19\x20\x00\x06\xDA\xDA\xDA\xDA\xDA\xDA\xDA"
                end
              end
            end
          end
        end

        context "is setup for a small transfer frame with 27 bytes data field" do
          before do
            @interface.add_protocol(CcsdsTransferFrameProtocol, [
              # Transfer frame length, 27 bytes data field.
              6 + 27,
              0, # secondary header length
              false, # does not have operational control field
              false], # does not have frame error control
              :READ)
          end

          context "receives a frame with a whole packet followed by a whole idle packet followed by a whole packet" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x01\x02\x03\x04\x00\x00" +
                "\x05\x06\x07\x08\x00\x01\xDA\xDA" +
                "\x3F\xFF\x09\x0A\x00\x02\x5A\x5A\x5A" +
                "\x0B\x0C\x0D\x0E\x00\x03\xDA\xDA\xDA\xDA")
            end

            it "returns the first packet" do
              expect(@packet_data.length).to eql 8
              expect(@packet_data).to eql "\x05\x06\x07\x08\x00\x01\xDA\xDA"
            end

            context "recieves an empty string" do
              before do
                @packet_data = @interface.read_protocols[0].read_data("")
              end

              it "skips the idle packet and returns the third packet" do
                expect(@packet_data.length).to eql 10
                expect(@packet_data).to eql "\x0B\x0C\x0D\x0E\x00\x03\xDA\xDA\xDA\xDA"
              end
            end
          end
        end

        context "is setup for a small transfer frame with 17 bytes data field and inclusion of idle packets" do
          before do
            @interface.add_protocol(CcsdsTransferFrameProtocol, [
              # Transfer frame length, 17 bytes data field.
              6 + 17,
              0, # secondary header length
              false, # does not have operational control field
              false, # does not have frame error control
              false, # no prefixing of packets (default)
              true], # include idle packets
              :READ)
          end

          context "receives a frame with a whole packet followed by a whole idle packet" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x01\x02\x03\x04\x00\x00" +
                "\x05\x06\x07\x08\x00\x01\xDA\xDA" +
                "\x3F\xFF\x09\x0A\x00\x02\x5A\x5A\x5A")
            end

            it "returns the first packet" do
              expect(@packet_data.length).to eql 8
              expect(@packet_data).to eql "\x05\x06\x07\x08\x00\x01\xDA\xDA"
            end

            context "receives an empty string" do
              before do
                @packet_data = @interface.read_protocols[0].read_data("")
              end

              it "returns the second idle packet" do
                expect(@packet_data).to eql "\x3F\xFF\x09\x0A\x00\x02\x5A\x5A\x5A"
              end
            end
          end
        end

        context "is setup for a small transfer frame with 27 bytes data field and inclusion of idle packets" do
          before do
            @interface.add_protocol(CcsdsTransferFrameProtocol, [
              # Transfer frame length, 27 bytes data field.
              6 + 27,
              0, # secondary header length
              false, # does not have operational control field
              false, # does not have frame error control
              false, # no prefixing of packets (default)
              true], # include idle packets
              :READ)
          end

          context "receives a frame with a whole packet followed by a whole idle packet followed by a whole packet" do
            before do
              @packet_data = @interface.read_protocols[0].read_data(
                "\x01\x02\x03\x04\x00\x00" +
                "\x05\x06\x07\x08\x00\x01\xDA\xDA" +
                "\x3F\xFF\x09\x0A\x00\x02\x5A\x5A\x5A" +
                "\x0B\x0C\x0D\x0E\x00\x03\xDA\xDA\xDA\xDA")
            end

            it "returns the first packet" do
              expect(@packet_data.length).to eql 8
              expect(@packet_data).to eql "\x05\x06\x07\x08\x00\x01\xDA\xDA"
            end

            context "recieves an empty string" do
              before do
                @packet_data = @interface.read_protocols[0].read_data("")
              end

              it "returns the second idle packet" do
                expect(@packet_data.length).to eql 9
                expect(@packet_data).to eql "\x3F\xFF\x09\x0A\x00\x02\x5A\x5A\x5A"
              end

              context "recieves an empty string" do
                before do
                  @packet_data = @interface.read_protocols[0].read_data("")
                end

                it "returns the third packet" do
                  expect(@packet_data.length).to eql 10
                  expect(@packet_data).to eql "\x0B\x0C\x0D\x0E\x00\x03\xDA\xDA\xDA\xDA"
                end
              end
            end
          end
        end

        it "Reads until a whole frame is received" do
          class PiecewiseTestStream < Stream
            def initialize
              @read_iteration = 0
            end

            def connect; end
            def connected?; true; end
            def disconnect; end

            def read
              i = @read_iteration
              @read_iteration += 1
              case i
              when 0
                return "\x01\x02\x03"
              when 1
                return "\x04\x00"
              when 2
                return "\x00" + "\x05\x06\x07"
              when 3
                return "\x08"
              when 4
                return "\x00\x00\xDA"
              else
                raise "read more than expected"
              end
            end
          end

          @interface.instance_variable_set(:@stream, PiecewiseTestStream.new)
          @interface.add_protocol(CcsdsTransferFrameProtocol, [
            # Transfer frame length, 7 bytes data field.
            6 + 7,
            0, # secondary header length
            false, # does not have operational control field
            false], # does not have frame error control
            :READ)

          # Should read repeatedly from piecewise stream until it has a whole
          # frame, then return the packet without reading anything more from the
          # stream.
          packet = @interface.read
          expect(packet.buffer.length).to eql 7
          expect(packet.buffer).to eql "\x05\x06\x07\x08\x00\x00\xDA"
        end

        it "Handles and prefixes a packet which fills a frame" do
          @interface.add_protocol(CcsdsTransferFrameProtocol, [
            # Transfer frame length, 7 bytes data field (minimum space packet length).
            6 + 1 + 7 + 0 + 2,
            1, # secondary header length
            false, # does not have operational control field
            true, # has frame error control
            true], # prefix packets
            :READ)

          packet_data = @interface.read_protocols[0].read_data(
            "\x02\x03\x02\x05\x08\x00" +
            "\x07" +
            "\x09\x02\x0B\x05\x00\x00\xDA" +
            "\x0F\x02")
          expect(packet_data.length).to eql  6 + 1 + 7
          expect(packet_data).to eql "\x02\x03\x02\x05\x08\x00" +
            "\x07" +
            "\x09\x02\x0B\x05\x00\x00\xDA"
        end

        it "Handles and prefixes packets which fills two frames" do
          @interface.add_protocol(CcsdsTransferFrameProtocol, [
            # Transfer frame length, 7 bytes data field.
            6 + 2 + 7 + 4 + 0,
            2, # secondary header length
            true, # has operational control field
            false, # does not have frame error control
            true], # prefix packets
            :READ)

          # should ask for more data
          packet_data = @interface.read_protocols[0].read_data(
            "\x25\x77\x13\x44\x80\x00" +
            "\xF3\x3D" +
            "\x59\xAC\xE9\xAC\x00\x07\xDA" +
            "\x31\x11\x58\xC6")
          expect(packet_data).to eql :STOP

          # Should then return the reassembled packet, prefixed with the frame
          # headers from the first frame.
          packet_data = @interface.read_protocols[0].read_data(
            "\x26\x77\x14\x45\x87\xFF" +
            "\xF4\x3E" +
            "\xDA\xDA\xDA\xDA\xDA\xDA\xDA" +
            "\x32\x12\x59\xC7")
          expect(packet_data.length).to eql 6 + 2 + 7 + 7
          expect(packet_data).to eql "\x25\x77\x13\x44\x80\x00" +
            "\xF3\x3D" +
            "\x59\xAC\xE9\xAC\x00\x07\xDA" +
            "\xDA\xDA\xDA\xDA\xDA\xDA\xDA"
        end

        it "Handles and prefixes packets which fills three frames" do
          @interface.add_protocol(CcsdsTransferFrameProtocol, [
            # Transfer frame length, 7 bytes data field.
            6 + 2 + 7 + 4 + 0,
            2, # secondary header length
            true, # has operational control field
            false, # does not have frame error control
            true], # prefix packets
            :READ)

          # should ask for more data
          packet_data = @interface.read_protocols[0].read_data(
            "\x25\x77\x13\x44\x80\x00" +
            "\xF3\x3D" +
            "\x59\xAC\xE9\xAC\x00\x0E\xDA" +
            "\x31\x11\x58\xC6")
          expect(packet_data).to eql :STOP

          # should then ask for more data again
          packet_data = @interface.read_protocols[0].read_data(
            "\x26\x77\x14\x45\x87\xFF" +
            "\xF4\x3E" +
            "\xDA\xDA\xDA\xDA\xDA\xDA\xDA" +
            "\x32\x12\x59\xC7")
          expect(packet_data).to eql :STOP

          # should then return the reassembled packet
          packet_data = @interface.read_protocols[0].read_data(
            "\x27\x77\x15\x46\x87\xFF" +
            "\xF5\x3F" +
            "\xDA\xDA\xDA\xDA\xDA\xDA\xDA" +
            "\x33\x13\x5A\xC8")
          expect(packet_data.length).to eql 6 + 2 + 7 + 7 + 7
          expect(packet_data).to eql "\x25\x77\x13\x44\x80\x00" +
            "\xF3\x3D" +
            "\x59\xAC\xE9\xAC\x00\x0E\xDA" +
            "\xDA\xDA\xDA\xDA\xDA\xDA\xDA" +
            "\xDA\xDA\xDA\xDA\xDA\xDA\xDA"
        end

        it "Handles and prefixes multiple packets from one frame" do
          @interface.add_protocol(CcsdsTransferFrameProtocol, [
            # Transfer frame length, 27 bytes data field.
            6 + 3 + 27 + 0 + 0,
            3, # secondary header length
            false, # does not have operational control field
            false, # does not have frame error control
            true], # prefix packets
            :READ)

          # should return the first packet
          packet_data = @interface.read_protocols[0].read_data(
            "\x01\x02\x03\x04\x00\x00" +
            "\x05\x06\x07" +
            "\x08\x09\x10\x11\x00\x01\xDA\xDA" +
            "\x12\x13\x14\x15\x00\x03\xDA\xDA\xDA\xDA" +
            "\x16\x17\x18\x19\x00\x02\xDA\xDA\xDA")
          expect(packet_data.length).to eql 6 + 3 + 8
          expect(packet_data).to eql "\x01\x02\x03\x04\x00\x00" +
            "\x05\x06\x07" +
            "\x08\x09\x10\x11\x00\x01\xDA\xDA"

          # should then return the second packet
          packet_data = @interface.read_protocols[0].read_data("")
          expect(packet_data.length).to eql 6 + 3 + 10
          expect(packet_data).to eql "\x01\x02\x03\x04\x00\x00" +
            "\x05\x06\x07" +
            "\x12\x13\x14\x15\x00\x03\xDA\xDA\xDA\xDA"

          # should then return the third packet
          packet_data = @interface.read_protocols[0].read_data("")
          expect(packet_data.length).to eql 6 + 3 + 9
          expect(packet_data).to eql "\x01\x02\x03\x04\x00\x00" +
            "\x05\x06\x07" +
            "\x16\x17\x18\x19\x00\x02\xDA\xDA\xDA"
        end

        it "Handles and prefixes packets which starts at the end of a frame and spans two frames" do
          @interface.add_protocol(CcsdsTransferFrameProtocol, [
            # Transfer frame length, 8 bytes data field.
            6 + 8,
            0, # secondary header length
            false, # does not have operational control field
            false, # does not have frame error control
            true], # prefix packets
            :READ)

          # should then return the first packet
          packet_data = @interface.read_protocols[0].read_data(
            "\x01\x02\x03\x04\x00\x00" +
            "\x05\x06\x07\x08\x00\x00\xDA" +
            "\x09")
          expect(packet_data.length).to eql 6 + 7
          expect(packet_data).to eql "\x01\x02\x03\x04\x00\x00" +
            "\x05\x06\x07\x08\x00\x00\xDA"

          # should then ask for more data
          packet_data = @interface.read_protocols[0].read_data("")
          expect(packet_data).to eql :STOP

          # should then return the reassembled packet with the first frame
          # headers as prefix
          packet_data = @interface.read_protocols[0].read_data(
            "\x10\x02\x12\x13\x07\xFF" +
            "\x14\x15\x16\x00\x02\xDA\xDA\xDA")
          expect(packet_data.length).to eql 6 + 9
          expect(packet_data).to eql "\x01\x02\x03\x04\x00\x00" +
            "\x09" +
            "\x14\x15\x16\x00\x02\xDA\xDA\xDA"
        end

        it "Handles and prefixes packets which spans two frames and ends before the end of a frame" do
          @interface.add_protocol(CcsdsTransferFrameProtocol, [
            # Transfer frame length, 8 bytes data field.
            6 + 8,
            0, # secondary header length
            false, # does not have operational control field
            false, # does not have frame error control
            true], # prefix packets
            :READ)

          # should ask for more data
          packet_data = @interface.read_protocols[0].read_data(
            "\x01\x02\x03\x04\x00\x00" +
            "\x05\x06\x07\x08\x00\x02\xDA\xDA")
          expect(packet_data).to eql :STOP

          # should then return the reassembled first packet with the first frame
          # headers as prefix
          packet_data = @interface.read_protocols[0].read_data(
            "\x10\x02\x12\x13\x00\x01" +
            "\xDA\x14\x15\x16\x17\x00\x00\xDA")
          expect(packet_data.length).to eql 6 + 9
          expect(packet_data).to eql "\x01\x02\x03\x04\x00\x00" +
            "\x05\x06\x07\x08\x00\x02\xDA\xDA\xDA"

          # should then return the second packet with the second frame headers as
          # prefix
          packet_data = @interface.read_protocols[0].read_data("")
          expect(packet_data.length).to eql 6 + 7
          expect(packet_data).to eql "\x10\x02\x12\x13\x00\x01" +
            "\x14\x15\x16\x17\x00\x00\xDA"
        end

        it "Uses the first header pointer to sync to an initial packet start and adds the correct prefix" do
          @interface.add_protocol(CcsdsTransferFrameProtocol, [
            # Transfer frame length, 8 bytes data field.
            6 + 8,
            0, # secondary header length
            false, # does not have operational control field
            false, # does not have frame error control
            true], # prefix packets
            :READ)

          # should ask for more data when no packet start is found
          packet_data = @interface.read_protocols[0].read_data(
            "\x01\x02\x03\x04\x07\xFF" +
            "\xDA\xDA\xDA\xDA\xDA\xDA\xDA\xDA")
          expect(packet_data).to eql :STOP

          # Should return the packet whose start is known, with the second frame
          # headers as prefix.
          packet_data = @interface.read_protocols[0].read_data(
            "\x10\x02\x12\x13\x00\x01" +
            "\xDA\x14\x15\x16\x17\x00\x00\xDA")
          expect(packet_data.length).to eql 6 + 7
          expect(packet_data).to eql "\x10\x02\x12\x13\x00\x01" +
            "\x14\x15\x16\x17\x00\x00\xDA"
        end

        it "Reads until a whole frame is received and prefixes correctly" do
          class PiecewiseTestStream < Stream
            def initialize
              @read_iteration = 0
            end

            def connect; end
            def connected?; true; end
            def disconnect; end

            def read
              i = @read_iteration
              @read_iteration += 1
              case i
              when 0
                return "\x01\x02\x03"
              when 1
                return "\x04\x00"
              when 2
                return "\x00" + "\x05\x06\x07"
              when 3
                return "\x08"
              when 4
                return "\x00\x00\xDA"
              else
                raise "read more than expected"
              end
            end
          end

          @interface.instance_variable_set(:@stream, PiecewiseTestStream.new)
          @interface.add_protocol(CcsdsTransferFrameProtocol, [
            # Transfer frame length, 7 bytes data field.
            6 + 7,
            0, # secondary header length
            false, # does not have operational control field
            false, # does not have frame error control
            true], # prefix packets
            :READ)

          # Should read repeatedly from piecewise stream until it has a whole
          # frame, then return the prefixed packet without reading anything more
          # from the stream
          packet = @interface.read
          expect(packet.buffer.length).to eql 6 + 7
          expect(packet.buffer).to eql "\x01\x02\x03\x04\x00\x00" +
            "\x05\x06\x07\x08\x00\x00\xDA"
        end

      end # "read"

    end # CcsdsTransferFrameProtocol
  end
end
