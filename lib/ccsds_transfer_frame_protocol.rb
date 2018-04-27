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

    def get_packet
      # Signal more data needed if there's a single incomplete packet in the queue.
      return :STOP if (@packet_queue.length == 1 && @pending_incomplete_packet_bytes_left > 0)

      packet_data = @packet_queue.shift
      return packet_data unless packet_data.nil?
      # If the packet queue contains any more whole packets they will be
      # handled in subsequent calls to this method. Cosmos will ensure that
      # read_data() is called until it returns :STOP, which allows us to
      # clear all whole packets.

      # no whole packet was completed with the given data
      return :STOP
    end

    def process_frame(frame)
      first_header_pointer =
        ((frame.bytes[FIRST_HEADER_POINTER_OFFSET] & FIRST_HEADER_POINTER_MASK[0]) << 8) |
        (frame.bytes[FIRST_HEADER_POINTER_OFFSET + 1] & FIRST_HEADER_POINTER_MASK[1])

      return if (first_header_pointer == IDLE_FRAME_FIRST_HEADER_POINTER)

      frame_data_field = frame[@frame_headers_length, @frame_data_field_length]

      if (@packet_queue.length > 0 &&
          @packet_queue[-1].length < @packet_prefix_length + SPACE_PACKET_HEADER_LENGTH)
        # pending incomplete packet does not have header yet
        rest_of_packet_header_length = @packet_prefix_length + SPACE_PACKET_HEADER_LENGTH - @packet_queue[-1].length
        @packet_queue[-1] << frame_data_field.slice!(0, rest_of_packet_header_length)

        space_packet_length = get_space_packet_length(@packet_queue[-1][@packet_prefix_length..-1])
        throw "failed to get space packet length" if Symbol === space_packet_length && space_packet_length == :STOP

        if (!@include_idle_packets &&
            get_space_packet_apid(@packet_queue[-1][@packet_prefix_length, SPACE_PACKET_HEADER_LENGTH]) == IDLE_PACKET_APID)
          # discard this packet
          @packet_queue.pop
          if (@pending_incomplete_packet_bytes_left >= frame_data_field.length)
            # The idle packet exactly fills this frame or continues in the next
            # frame, the current frame can be skipped.

            # If the idle packet spans over two frames, the continuation of the
            # packet in the next frame will be discarded since there is no
            # pending incomplete packet.
            @pending_incomplete_packet_bytes_left = 0
            return
          else
            # The idle packet ends before the end of this frame, discard it
            # and handle the rest of the frame.
            frame_data_field.replace(frame_data_field[@pending_incomplete_packet_bytes_left..-1])
            @pending_incomplete_packet_bytes_left = 0
          end
        else
          # keep idle packet
          @pending_incomplete_packet_bytes_left = space_packet_length - SPACE_PACKET_HEADER_LENGTH
        end
      end

      if (@pending_incomplete_packet_bytes_left >= frame_data_field.length)
        # continuation of a packet
        @packet_queue[-1] << frame_data_field
        @pending_incomplete_packet_bytes_left -= frame_data_field.length
        return
      end

      if (first_header_pointer == NO_PACKET_START_FIRST_HEADER_POINTER)
        # This was not a continuation of a packet (or it was a continuation of
        # an ignored idle packet), wait for another frame to find a packet
        # start.
        return
      end

      if (@pending_incomplete_packet_bytes_left > 0)
        rest_of_packet = frame_data_field.slice!(0, @pending_incomplete_packet_bytes_left)
        @packet_queue[-1] << rest_of_packet
        @pending_incomplete_packet_bytes_left = 0
      end

      if (frame_data_field.length == @frame_data_field_length)
        # No continuation packet was completed, and a packet starts in this
        # frame. Utilise the first header pointer to re-sync to a packet start.
        frame_data_field.replace(frame_data_field[first_header_pointer..-1])
      end

      frame_headers = frame[0, @frame_headers_length].clone

      while (frame_data_field.length > 0) do
        if @prefix_packets
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
          if (!@include_idle_packets && 
              get_space_packet_apid(frame_data_field) == IDLE_PACKET_APID)
            # discard this packet
            @packet_queue.pop
            # Idle packet spans over two frames, the continuation of the packet
            # in the next frame will be discarded since there is no pending
            # incomplete packet.
            return
          end

          @packet_queue[-1] << frame_data_field
          @pending_incomplete_packet_bytes_left = space_packet_length - frame_data_field.length
          return
        end

        space_packet = frame_data_field.slice!(0, space_packet_length)
        if (!@include_idle_packets && 
            get_space_packet_apid(space_packet) == IDLE_PACKET_APID)
          # discard this packet
          @packet_queue.pop
        else
          @packet_queue[-1] << space_packet
        end
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
