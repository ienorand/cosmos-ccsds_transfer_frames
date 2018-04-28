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
  # Given a stream of ccsds transfer frames, extract ccsds space packets based
  # on the first header pointer and packet lengths.
  class CcsdsTransferFrameProtocol < Protocol
    FRAME_PRIMARY_HEADER_LENGTH = 6
    FIRST_HEADER_POINTER_OFFSET = 4
    # last 11 bits
    FIRST_HEADER_POINTER_MASK = [0b00000111, 0b11111111]
    IDLE_FRAME_FIRST_HEADER_POINTER = 0b11111111110
    NO_PACKET_START_FIRST_HEADER_POINTER = 0b11111111111
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
      @packet_queue = []
      @pending_incomplete_packet_bytes_left = 0
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

    # Get a packet from the queue of stored packets from processed frames.
    #
    # If idle packets are not included, extracted idle packets are discarded
    # and extraction is retried until a non-idle packet is found or no more
    # complete packets are left in the queue.
    #
    # @return [String] Packet data, if the queue contained at least one
    #   complete packet.
    # @return [Symbol] :STOP, if the queue does not contain any complete
    #   packets.
    def get_packet
      loop do
        # Signal more data needed if there's a single incomplete packet in the queue.
        return :STOP if (@packet_queue.length == 1 && @pending_incomplete_packet_bytes_left > 0)

        packet_data = @packet_queue.shift

        return :STOP if packet_data.nil?

        return packet_data if @include_idle_packets

        apid = get_space_packet_apid(packet_data[@packet_prefix_length, SPACE_PACKET_HEADER_LENGTH])
        return packet_data unless (apid == IDLE_PACKET_APID)
      end
      
      # If the packet queue contains any more whole packets they will be
      # handled in subsequent calls to this method. Cosmos will ensure that
      # read_data() is called until it returns :STOP, which allows us to
      # clear all whole packets.
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

      frame_data_field = frame[@frame_headers_length, @frame_data_field_length]

      status = handle_packet_continuation(frame_data_field, first_header_pointer)
      return if (Symbol === status && status == :STOP)

      if (frame_data_field.length == @frame_data_field_length)
        # No continuation packet was completed, and a packet starts in this
        # frame. Utilise the first header pointer to re-sync to a packet start.
        frame_data_field.replace(frame_data_field[first_header_pointer..-1])
      end

      frame_headers = frame[0, @frame_headers_length].clone
      store_packets(frame_headers, frame_data_field)
    end

    # Handle packet continuation when processing a transfer frame.
    #
    # Ensures that any incomplete packet first has enough data for the packet
    # header to determine its length and then ensures that it has enough data
    # to be complete based on its length.
    #
    # @param frame [String] Transfer frame data.
    def handle_packet_continuation(frame_data_field, first_header_pointer)
      if (@packet_queue.length > 0 &&
          @packet_queue[-1].length < @packet_prefix_length + SPACE_PACKET_HEADER_LENGTH)
        # pending incomplete packet does not have header yet
        rest_of_packet_header_length = @packet_prefix_length + SPACE_PACKET_HEADER_LENGTH - @packet_queue[-1].length
        @packet_queue[-1] << frame_data_field.slice!(0, rest_of_packet_header_length)

        space_packet_length = get_space_packet_length(@packet_queue[-1][@packet_prefix_length..-1])
        throw "failed to get space packet length" if Symbol === space_packet_length && space_packet_length == :STOP

        @pending_incomplete_packet_bytes_left = space_packet_length - SPACE_PACKET_HEADER_LENGTH
      end

      if (@pending_incomplete_packet_bytes_left >= frame_data_field.length)
        # continuation of a packet
        @packet_queue[-1] << frame_data_field
        @pending_incomplete_packet_bytes_left -= frame_data_field.length
        return :STOP
      end

      if (first_header_pointer == NO_PACKET_START_FIRST_HEADER_POINTER)
        # This was not a continuation of a packet (or it was a continuation of
        # an ignored idle packet), wait for another frame to find a packet
        # start.
        return :STOP
      end

      if (@pending_incomplete_packet_bytes_left > 0)
        rest_of_packet = frame_data_field.slice!(0, @pending_incomplete_packet_bytes_left)
        @packet_queue[-1] << rest_of_packet
        @pending_incomplete_packet_bytes_left = 0
      end
    end

    def store_packets(frame_headers, frame_data_field)
      while (frame_data_field.length > 0) do
        if (@prefix_packets)
          @packet_queue << frame_headers.clone
        else
          @packet_queue << ""
        end

        if (frame_data_field.length < SPACE_PACKET_HEADER_LENGTH)
          @packet_queue[-1] << frame_data_field
          @pending_incomplete_packet_bytes_left = SPACE_PACKET_HEADER_LENGTH - frame_data_field.length
          return
        end

        space_packet_length = get_space_packet_length(frame_data_field)
        throw "failed to get space packet length" if Symbol === space_packet_length && space_packet_length == :STOP

        if (space_packet_length > frame_data_field.length)
          @packet_queue[-1] << frame_data_field
          @pending_incomplete_packet_bytes_left = space_packet_length - frame_data_field.length
          return
        end

        @packet_queue[-1] << frame_data_field.slice!(0, space_packet_length)
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
