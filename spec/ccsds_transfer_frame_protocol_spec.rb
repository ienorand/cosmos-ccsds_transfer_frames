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
require 'ccsds_transfer_frame_protocol'

module Cosmos
  describe CcsdsTransferFrameProtocol do
    before(:each) do
      @interface = StreamInterface.new
      allow(@interface).to receive(:connected?) { true }
    end

    describe "initialize" do
      it "initialises attributes" do
        @interface.add_protocol(
          CcsdsTransferFrameProtocol,
          [1115, 0, true, true],
          :READ)

        expect(@interface.read_protocols[0].instance_variable_get(:@data)).to eq ''
        expect(@interface.read_protocols[0].instance_variable_get(:@virtual_channels).length).to eq 8
        @interface.read_protocols[0].instance_variable_get(:@virtual_channels).each do |vc|
          expect(vc.packet_queue).to eq []
          expect(vc.pending_incomplete_packet_bytes_left).to eq 0
        end
        expect(@interface.read_protocols[0].instance_variable_get(:@frame_length)).to eq 1115
        expect(@interface.read_protocols[0].instance_variable_get(:@frame_headers_length)).to eq 6 + 0
        expect(@interface.read_protocols[0].instance_variable_get(:@frame_trailer_length)).to eq 4 + 2
        expect(@interface.read_protocols[0].instance_variable_get(:@prefix_packets)).to eq false
        expect(@interface.read_protocols[0].instance_variable_get(:@include_idle_packets)).to eq false
      end

      it "initialises optional attributes" do
        @interface.add_protocol(
          CcsdsTransferFrameProtocol,
          [1115, 7, false, false, true, true],
          :READ)

        expect(@interface.read_protocols[0].instance_variable_get(:@data)).to eq ''
        expect(@interface.read_protocols[0].instance_variable_get(:@virtual_channels).length).to eq 8
        @interface.read_protocols[0].instance_variable_get(:@virtual_channels).each do |vc|
          expect(vc.packet_queue).to eq []
          expect(vc.pending_incomplete_packet_bytes_left).to eq 0
        end
        expect(@interface.read_protocols[0].instance_variable_get(:@frame_length)).to eq 1115
        expect(@interface.read_protocols[0].instance_variable_get(:@frame_headers_length)).to eq 6 + 7
        expect(@interface.read_protocols[0].instance_variable_get(:@frame_trailer_length)).to eq 0 + 0
        expect(@interface.read_protocols[0].instance_variable_get(:@prefix_packets)).to eq true
        expect(@interface.read_protocols[0].instance_variable_get(:@include_idle_packets)).to eq true
      end
    end

    describe "read" do
      it "Handles packets which fills a frame" do
        @interface.add_protocol(CcsdsTransferFrameProtocol, [
          # Transfer frame length, 7 bytes data field (minimum space packet length).
          6 + 1 + 7 + 0 + 2,
          1, # secondary header length
          false, # does not have operational control field
          true], # has frame error control
          :READ)

        packet_data = @interface.read_protocols[0].read_data(
          "\x02\x03\x02\x05\x08\x00" +
          "\x07" +
          "\x09\x02\x0B\x05\x00\x00\xDA" +
          "\x0F\x02")
        expect(packet_data.length).to eql 7
        expect(packet_data).to eql "\x09\x02\x0B\x05\x00\x00\xDA"
      end

      it "Handles packets which fills two frames" do
        @interface.add_protocol(CcsdsTransferFrameProtocol, [
          # Transfer frame length, 7 bytes data field.
          6 + 2 + 7 + 4 + 0,
          2, # secondary header length
          true, # has operational control field
          false], # does not have frame error control
          :READ)

        # should ask for more data
        packet_data = @interface.read_protocols[0].read_data(
          "\x25\x76\x13\x44\x80\x00" +
          "\xF3\x3D" +
          "\x59\xAC\xE9\xAC\x00\x07\xDA" +
          "\x31\x11\x58\xC6")
        expect(packet_data).to eql :STOP

        # should then return the reassembled packet
        packet_data = @interface.read_protocols[0].read_data(
          "\x26\x76\x14\x45\x87\xFF" +
          "\xF4\x3E" +
          "\xDA\xDA\xDA\xDA\xDA\xDA\xDA" +
          "\x32\x12\x59\xC7")
        expect(packet_data.length).to eql 7 + 7
        expect(packet_data).to eql "\x59\xAC\xE9\xAC\x00\x07\xDA" +
          "\xDA\xDA\xDA\xDA\xDA\xDA\xDA"
      end

      it "Handles packets which fills three frames" do
        @interface.add_protocol(CcsdsTransferFrameProtocol, [
          # Transfer frame length, 7 bytes data field.
          6 + 2 + 7 + 4 + 0,
          2, # secondary header length
          true, # has operational control field
          false], # does not have frame error control
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
        expect(packet_data.length).to eql 7 + 7 + 7
        expect(packet_data).to eql "\x59\xAC\xE9\xAC\x00\x0E\xDA" +
          "\xDA\xDA\xDA\xDA\xDA\xDA\xDA" +
          "\xDA\xDA\xDA\xDA\xDA\xDA\xDA"
      end

      it "Extracts multiple packets from one frame" do
        @interface.add_protocol(CcsdsTransferFrameProtocol, [
          # Transfer frame length, 27 bytes data field.
          6 + 3 + 27 + 0 + 0,
          3, # secondary header length
          false, # does not have operational control field
          false], # does not have frame error control
          :READ)

        # should return the first packet
        packet_data = @interface.read_protocols[0].read_data(
          "\x01\x02\x03\x04\x00\x00" +
          "\x05\x06\x07" +
          "\x08\x09\x10\x11\x00\x01\xDA\xDA" +
          "\x12\x13\x14\x15\x00\x03\xDA\xDA\xDA\xDA" +
          "\x16\x17\x18\x19\x00\x02\xDA\xDA\xDA")
        expect(packet_data.length).to eql 8
        expect(packet_data).to eql "\x08\x09\x10\x11\x00\x01\xDA\xDA"

        # should then return the second packet
        packet_data = @interface.read_protocols[0].read_data("")
        expect(packet_data.length).to eql 10
        expect(packet_data).to eql "\x12\x13\x14\x15\x00\x03\xDA\xDA\xDA\xDA"

        # should then return the third packet
        packet_data = @interface.read_protocols[0].read_data("")
        expect(packet_data.length).to eql 9
        expect(packet_data).to eql "\x16\x17\x18\x19\x00\x02\xDA\xDA\xDA"
      end

      it "Handles packets which starts at the end of a frame and spans two frames" do
        @interface.add_protocol(CcsdsTransferFrameProtocol, [
          # Transfer frame length, 8 bytes data field.
          6 + 8,
          0, # secondary header length
          false, # does not have operational control field
          false], # does not have frame error control
          :READ)

        # should return the first packet
        packet_data = @interface.read_protocols[0].read_data(
          "\x02\x02\x03\x04\x00\x00" +
          "\x05\x06\x07\x08\x00\x00\xDA" +
          "\x09")
        expect(packet_data.length).to eql 7
        expect(packet_data).to eql "\x05\x06\x07\x08\x00\x00\xDA"

        # should then return the reassembled second packet
        packet_data = @interface.read_protocols[0].read_data(
          "\x10\x02\x12\x13\x07\xFF" +
          "\x14\x15\x16\x00\x02\xDA\xDA\xDA")
        expect(packet_data.length).to eql 9
        expect(packet_data).to eql "\x09" + "\x14\x15\x16\x00\x02\xDA\xDA\xDA"
      end

      it "Handles packets which spans two frames and ends before the end of a frame" do
        @interface.add_protocol(CcsdsTransferFrameProtocol, [
          # Transfer frame length, 8 bytes data field.
          6 + 8,
          0, # secondary header length
          false, # does not have operational control field
          false], # does not have frame error control
          :READ)

        # should ask for more data
        packet_data = @interface.read_protocols[0].read_data(
          "\x01\x02\x03\x04\x00\x00" +
          "\x05\x06\x07\x08\x00\x02\xDA\xDA")
        expect(packet_data).to eql :STOP

        # should then return the reassembled first packet
        packet_data = @interface.read_protocols[0].read_data(
          "\x10\x02\x12\x13\x00\x01" +
          "\xDA" +
          "\x14\x15\x16\x17\x00\x00\xDA")
        expect(packet_data.length).to eql 9
        expect(packet_data).to eql "\x05\x06\x07\x08\x00\x02\xDA\xDA\xDA"

        # should then return the second packet
        packet_data = @interface.read_protocols[0].read_data("")
        expect(packet_data.length).to eql 7
        expect(packet_data).to eql "\x14\x15\x16\x17\x00\x00\xDA"
      end

      it "Uses the first header pointer to sync to an initial packet start" do
        @interface.add_protocol(CcsdsTransferFrameProtocol, [
          # Transfer frame length, 8 bytes data field.
          6 + 8,
          0, # secondary header length
          false, # does not have operational control field
          false], # does not have frame error control
          :READ)

        # should ask for more data when no packet start is found
        packet_data = @interface.read_protocols[0].read_data(
          "\x01\x02\x03\x04\x07\xFF" +
          "\xDA\xDA\xDA\xDA\xDA\xDA\xDA\xDA")
        expect(packet_data).to eql :STOP

        packet_data = @interface.read_protocols[0].read_data(
          "\x10\x02\x12\x13\x00\x01" +
          "\xDA\x14\x15\x16\x17\x00\x00\xDA")
        # should then return the packet whose start is known
        expect(packet_data.length).to eql 7
        expect(packet_data).to eql "\x14\x15\x16\x17\x00\x00\xDA"
      end

      it "Discards idle packets" do
        @interface.add_protocol(CcsdsTransferFrameProtocol, [
          # Transfer frame length, 17 bytes data field.
          6 + 17,
          0, # secondary header length
          false, # does not have operational control field
          false], # does not have frame error control
          :READ)

        # should return the first packet
        packet_data = @interface.read_protocols[0].read_data(
          "\x01\x02\x03\x04\x00\x00" +
          "\x05\x06\x07\x08\x00\x01\xDA\xDA" +
          "\x3F\xFF\x09\x0A\x00\x02\x5A\x5A\x5A")
        expect(packet_data.length).to eql 8
        expect(packet_data).to eql "\x05\x06\x07\x08\x00\x01\xDA\xDA"

        # should then skip the idle packet and ask for more data
        expect(@interface.read_protocols[0].read_data("")).to eql :STOP
      end

      it "Discards idle packets in between normal packets" do
        @interface.add_protocol(CcsdsTransferFrameProtocol, [
          # Transfer frame length, 27 bytes data field.
          6 + 27,
          0, # secondary header length
          false, # does not have operational control field
          false], # does not have frame error control
          :READ)

        # should return the first packet
        packet_data = @interface.read_protocols[0].read_data(
          "\x01\x02\x03\x04\x00\x00" +
          "\x05\x06\x07\x08\x00\x01\xDA\xDA" +
          "\x3F\xFF\x09\x0A\x00\x02\x5A\x5A\x5A" +
          "\x0B\x0C\x0D\x0E\x00\x03\xDA\xDA\xDA\xDA")
        expect(packet_data.length).to eql 8
        expect(packet_data).to eql "\x05\x06\x07\x08\x00\x01\xDA\xDA"

        # should then skip the idle packet and return the last packet
        packet_data = @interface.read_protocols[0].read_data("")
        expect(packet_data.length).to eql 10
        expect(packet_data).to eql "\x0B\x0C\x0D\x0E\x00\x03\xDA\xDA\xDA\xDA"
      end

      it "Discards idle packets which spans multiple frames" do
        @interface.add_protocol(CcsdsTransferFrameProtocol, [
          # Transfer frame length, 8 bytes data field.
          6 + 8,
          0, # secondary header length
          false, # does not have operational control field
          false], # does not have frame error control
          :READ)

        # should return the first packet
        packet_data = @interface.read_protocols[0].read_data(
          "\x01\x02\x03\x04\x00\x00" +
          "\x05\x06\x07\x08\x00\x00\xDA" +
          "\x3F")
        expect(packet_data.length).to eql 7
        expect(packet_data).to eql "\x05\x06\x07\x08\x00\x00\xDA"

        # should then skip the idle packet and ask for more data
        packet_data = @interface.read_protocols[0].read_data(
          "\x01\x02\x03\x04\x07\xFF" +
          "\xFF\x09\x0A\x00\x02\x5A\x5A\x5A")
        expect(packet_data).to eql :STOP
      end

      it "Handles and idle packet followed by a packet that spans two frames" do
        @interface.add_protocol(CcsdsTransferFrameProtocol, [
          # Transfer frame length, 8 bytes data field.
          6 + 8,
          0, # secondary header length
          false, # does not have operational control field
          false], # does not have frame error control
          :READ)

        # should not return the idle packet and ask for more data
        packet_data = @interface.read_protocols[0].read_data(
          "\x01\x02\x03\x04\x00\x00" +
          "\x3F\xFF\x05\x06\x00\x00\x5A" +
          "\x07")
        expect(packet_data).to eql :STOP

        # should then return the finished packet
        packet_data = @interface.read_protocols[0].read_data(
          "\x01\x02\x03\x04\x07\xFF" +
          "\x08\x09\x0A\x00\x02\xDA\xDA\xDA")
        expect(packet_data.length).to eql 9
        expect(packet_data).to eql "\x07\x08\x09\x0A\x00\x02\xDA\xDA\xDA"
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

        #should then ask for more data again
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

        packet_data = @interface.read_protocols[0].read_data("")
        # should then return the second packet with the second frame headers as
        # prefix
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
