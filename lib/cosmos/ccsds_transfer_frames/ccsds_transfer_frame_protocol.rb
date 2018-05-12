# encoding: ascii-8bit

# Copyright 2018 Fredrik Persson <u.fredrik.persson@gmail.com>
#                Martin Erik Werner <martinerikwerner@gmail.com>
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

require 'cosmos/config/config_parser'
require 'cosmos/packets/binary_accessor'
require 'cosmos/interfaces/protocols/protocol'
require 'thread'

module Cosmos
  module CcsdsTransferFrames
    # Given a stream of ccsds transfer frames, extract ccsds space packets based
    # on the first header pointer and packet lengths.
    #
    # Only read is supported.
    class CcsdsTransferFrameProtocol < Protocol
      FRAME_PRIMARY_HEADER_LENGTH = 6
      FIRST_HEADER_POINTER_OFFSET = 4
      # last 11 bits
      FIRST_HEADER_POINTER_MASK = [0b00000111, 0b11111111]
      IDLE_FRAME_FIRST_HEADER_POINTER = 0b11111111110
      NO_PACKET_START_FIRST_HEADER_POINTER = 0b11111111111
      FRAME_VIRTUAL_CHANNEL_BIT_OFFSET = 12
      FRAME_VIRTUAL_CHANNEL_BITS = 3
      VIRTUAL_CHANNEL_COUNT = 8
      FRAME_OPERATIONAL_CONTROL_FIELD_LENGTH = 4
      FRAME_ERROR_CONTROL_FIELD_LENGTH = 2
      SPACE_PACKET_HEADER_LENGTH = 6
      SPACE_PACKET_LENGTH_BIT_OFFSET = 4 * 8
      SPACE_PACKET_LENGTH_BITS = 2 * 8
      SPACE_PACKET_APID_BITS = 14
      SPACE_PACKET_APID_BIT_OFFSET = 2 * 8 - SPACE_PACKET_APID_BITS
      IDLE_PACKET_APID = 0b11111111111111

      # @param transfer_frame_length [Integer] Length of transfer frame in bytes
      # @param transfer_frame_secondary_header_length [Integer] Length of
      #        transfer frame secondary header in bytes
      # @param transfer_frame_has_operational_control_field [Boolean] Flag
      #        indicating if the transfer frame operational control field is
      #        present or not
      # @param transfer_frame_has_frame_error_control_field [Boolean] Flag
      #        indicating if the transfer frame error control field is present or
      #        not
      # @param prefix_packets [Boolean] Flag indicating if each space packet should
      #        be prefixed with the transfer frame headers from the frame where
      #        it started.
      # @param include_idle_packets [Boolean] Flag indicating if idle packets
      #        should be included or discarded.
      # @param allow_empty_data [true/false/nil] See Protocol#initialize
      def initialize(
        transfer_frame_length,
        transfer_frame_secondary_header_length,
        transfer_frame_has_operational_control_field,
        transfer_frame_has_frame_error_control_field,
        prefix_packets = false,
        include_idle_packets = false,
        allow_empty_data = nil)
        super(allow_empty_data)

        @frame_length = Integer(transfer_frame_length)

        @frame_headers_length = FRAME_PRIMARY_HEADER_LENGTH + Integer(transfer_frame_secondary_header_length)

        @frame_trailer_length = 0
        has_ocf = ConfigParser.handle_true_false(transfer_frame_has_operational_control_field)
        @frame_trailer_length += FRAME_OPERATIONAL_CONTROL_FIELD_LENGTH if has_ocf
        has_fecf = ConfigParser.handle_true_false(transfer_frame_has_frame_error_control_field)
        @frame_trailer_length += FRAME_ERROR_CONTROL_FIELD_LENGTH if has_fecf

        @frame_data_field_length = @frame_length - @frame_headers_length - @frame_trailer_length

        @packet_prefix_length = 0
        @prefix_packets = ConfigParser.handle_true_false(prefix_packets)
        @packet_prefix_length += @frame_headers_length if @prefix_packets

        @include_idle_packets = ConfigParser.handle_true_false(include_idle_packets)
      end

      def reset
        super()
        @data = ''
        @virtual_channels = Array.new(VIRTUAL_CHANNEL_COUNT) { VirtualChannel.new }
      end

      def read_data(data)
        @data << data

        if (@data.length >= @frame_length)
          frame = @data.slice!(0, @frame_length)
          process_frame(frame)
        end

        packet_data = get_packet()

        # Potentially allow blank string to be sent to other protocols if no
        # packet is ready in this one
        if (Symbol === packet_data && packet_data == :STOP && data.length <= 0)
          return super(data)
        end

        return packet_data
      end

      private

      VirtualChannel = Struct.new(:packet_queue, :pending_incomplete_packet_bytes_left) do
        def initialize(packet_queue: [], pending_incomplete_packet_bytes_left: 0)
          super(packet_queue, pending_incomplete_packet_bytes_left)
        end
      end

      # Get a packet from the virtual channel packet queues of stored packets
      # from processed frames.
      #
      # If idle packets are not included, extracted idle packets are discarded
      # and extraction is retried until a non-idle packet is found or no more
      # complete packets are left in any of the virtual channel packet queues.
      #
      # @return [String] Packet data, if the queues contained at least one
      #   complete packet.
      # @return [Symbol] :STOP, if the queues do not contain any complete
      #   packets.
      def get_packet
        @virtual_channels.each do |vc|
          loop do
            # Skip if there's only a single incomplete packet in the queue.
            break if (vc.packet_queue.length == 1 &&
                      vc.pending_incomplete_packet_bytes_left > 0)

            packet_data = vc.packet_queue.shift

            break if packet_data.nil?

            return packet_data if @include_idle_packets

            apid = get_space_packet_apid(packet_data[@packet_prefix_length, SPACE_PACKET_HEADER_LENGTH])
            return packet_data unless (apid == IDLE_PACKET_APID)
          end
        end
        # If the packet queues contains any more whole packets they will be
        # handled in subsequent calls to this method. Cosmos will ensure that
        # read_data() is called until it returns :STOP, which allows us to
        # clear all whole packets.

        # no complete packet for any virtual channel
        return :STOP
      end

      # Extract packets from a transfer frame and store them in the packet queue.
      #
      # First handles packet continuation of any incomplete packet and then
      # handles the rest of the packets in the frame.
      #
      # @param frame [String] Transfer frame data.
      def process_frame(frame)
        first_header_pointer =
          ((frame.bytes[FIRST_HEADER_POINTER_OFFSET] & FIRST_HEADER_POINTER_MASK[0]) << 8) |
          (frame.bytes[FIRST_HEADER_POINTER_OFFSET + 1] & FIRST_HEADER_POINTER_MASK[1])

        return if (first_header_pointer == IDLE_FRAME_FIRST_HEADER_POINTER)

        virtual_channel = BinaryAccessor.read(
          FRAME_VIRTUAL_CHANNEL_BIT_OFFSET,
          FRAME_VIRTUAL_CHANNEL_BITS,
          :UINT,
          frame,
          :BIG_ENDIAN)

        frame_data_field = frame[@frame_headers_length, @frame_data_field_length]

        handle_packet_continuation(virtual_channel, frame_data_field, first_header_pointer)

        return if (first_header_pointer == NO_PACKET_START_FIRST_HEADER_POINTER)

        frame_headers = frame[0, @frame_headers_length]
        store_packets(virtual_channel, frame_headers, frame_data_field)
      end

      # Handle packet continuation when processing a transfer frame.
      #
      # First ensures that any incomplete packet has enough data for the packet
      # header to determine its length and then tries to complete it.
      #
      # If the first header pointer indicates that a packet starts in this
      # frame, the frame_data_field parameter will be modified by removing
      # everything before the first header pointer.
      #
      # @param virtual_channel [Int] Transfer frame virtual channel.
      # @param frame_data_field [String] Transfer frame data field.
      # @param first_header_pointer [Int] First header pointer value.
      def handle_packet_continuation(virtual_channel, frame_data_field, first_header_pointer)
        vc = @virtual_channels[virtual_channel]

        if (vc.packet_queue.length == 0 ||
            vc.pending_incomplete_packet_bytes_left == 0)
          # no packet in queue to be continued

          return if (first_header_pointer == NO_PACKET_START_FIRST_HEADER_POINTER)

          frame_data_field.replace(frame_data_field[first_header_pointer..-1])
          return
        end

        packet_continuation = nil
        if (first_header_pointer == NO_PACKET_START_FIRST_HEADER_POINTER)
          packet_continuation = frame_data_field
        else
          packet_continuation = frame_data_field.slice!(0, first_header_pointer)
        end

        if (vc.packet_queue[-1].length < @packet_prefix_length + SPACE_PACKET_HEADER_LENGTH)
          # Pending incomplete packet does not yet heave header, try to
          # complete header and get length before processing further.
          rest_of_packet_header_length = vc.pending_incomplete_packet_bytes_left
          if (rest_of_packet_header_length > packet_continuation.length)
            # Not enough continuation to complete packet header, first header
            # pointer takes precedence and packet is cut short.
            vc.packet_queue[-1] << packet_continuation
            vc.pending_incomplete_packet_bytes_left = 0
            return
          end
          vc.packet_queue[-1] << packet_continuation.slice!(0, rest_of_packet_header_length)

          space_packet_length = get_space_packet_length(vc.packet_queue[-1][@packet_prefix_length..-1])
          throw "failed to get space packet length" if Symbol === space_packet_length && space_packet_length == :STOP

          vc.pending_incomplete_packet_bytes_left = space_packet_length - SPACE_PACKET_HEADER_LENGTH
        end

        if (first_header_pointer == NO_PACKET_START_FIRST_HEADER_POINTER)
          # packet continues past this frame or ends exactly at end of this
          # frame according to first header pointer

          if (vc.pending_incomplete_packet_bytes_left < packet_continuation.length)
            # Packet length is inconsistent with first header pointer, since it
            # indicates that the packet ends before the end of this frame.
            #
            # Complete the packet based on the packet length and ignore the
            # rest of the data in the frame (will use first header pointer to
            # re-sync with start of next packet in a later frame).
            vc.packet_queue[-1] << packet_continuation[0, vc.pending_incomplete_packet_bytes_left]
            vc.pending_incomplete_packet_bytes_left = 0
            return
          end

          # First header pointer and packet length are consistent, append whole frame.
          vc.packet_queue[-1] << packet_continuation
          vc.pending_incomplete_packet_bytes_left -= frame_data_field.length
          return
        end

        # packet ends before the end of this frame according to first header
        # pointer

        if (vc.pending_incomplete_packet_bytes_left < packet_continuation.length)
          # Packet length is inconsistent with first header pointer, since it
          # indicates that the packet ends before the first header pointer.
          #
          # Complete the packet based on the packet length and ignore the data
          # between the packet end and the first header pointer.
          packet_continuation.replace(packet_continuation[0, vc.pending_incomplete_packet_bytes_left])
        end

        # If the packet length is too long compared to the first header
        # pointer, the first header pointer takes precedence and the packet is
        # cut short.

        vc.packet_queue[-1] << packet_continuation
        vc.pending_incomplete_packet_bytes_left = 0
      end

      # Extract all packets from the remaining frame data field, and store them
      # in the packet queue.
      #
      # It is assumed that packet continuation data from any previously
      # unfinished packets has been removed from the frame data field prior, and
      # hence that the given remaining frame data field starts at a space packet
      # header.
      #
      # Handles both complete packets and unfinished packets which will be
      # finished in a later frame via handle_packet_continuation().
      #
      # @param virtual_channel [Int] Transfer frame virtual channel.
      # @param frame_headers [String] Transfer frame headers, only used if prefixing packets.
      # @param frame_data_field [String] (Remaining) transfer frame data field.
      def store_packets(virtual_channel, frame_headers, frame_data_field)
        vc = @virtual_channels[virtual_channel]
        while (frame_data_field.length > 0) do
          if (@prefix_packets)
            vc.packet_queue << frame_headers.clone
          else
            vc.packet_queue << ""
          end

          if (frame_data_field.length < SPACE_PACKET_HEADER_LENGTH)
            vc.packet_queue[-1] << frame_data_field
            vc.pending_incomplete_packet_bytes_left = SPACE_PACKET_HEADER_LENGTH - frame_data_field.length
            return
          end

          space_packet_length = get_space_packet_length(frame_data_field)
          throw "failed to get space packet length" if Symbol === space_packet_length && space_packet_length == :STOP

          if (space_packet_length > frame_data_field.length)
            vc.packet_queue[-1] << frame_data_field
            vc.pending_incomplete_packet_bytes_left = space_packet_length - frame_data_field.length
            return
          end

          vc.packet_queue[-1] << frame_data_field.slice!(0, space_packet_length)
        end
      end

      def get_space_packet_length(space_packet)
        # signal more data needed if we do not have enough to determine the
        # length of the space packet
        return :STOP if (space_packet.length < SPACE_PACKET_HEADER_LENGTH)

        # actual length in ccsds space packet is stored value plus one
        space_packet_data_field_length = BinaryAccessor.read(
          SPACE_PACKET_LENGTH_BIT_OFFSET,
          SPACE_PACKET_LENGTH_BITS,
          :UINT,
          space_packet,
          :BIG_ENDIAN) + 1
        space_packet_length = SPACE_PACKET_HEADER_LENGTH + space_packet_data_field_length
        return space_packet_length
      end

      def get_space_packet_apid(space_packet)
        # signal more data needed if we do not have enough of the header to
        # determine the apid of the space packet
        return :STOP if (space_packet.length < (SPACE_PACKET_APID_BIT_OFFSET + SPACE_PACKET_APID_BITS) / 8)

        # actual length in ccsds space packet is stored value plus one
        space_packet_apid = BinaryAccessor.read(
          SPACE_PACKET_APID_BIT_OFFSET,
          SPACE_PACKET_APID_BITS,
          :UINT,
          space_packet,
          :BIG_ENDIAN)
        return space_packet_apid
      end
    end
  end
end
