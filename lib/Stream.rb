#    Copyright 2009 Christoffer Lervag

# This file contains the Stream class, which handles all encoding to and
# decoding from binary strings. It is used by the other components of
# Ruby DICOM for tasks such as reading from file, writing to file,
# reading and writing network data packets. These operations have been
# gathered in this one class in an attemt to minimize code duplication.

module DICOM
  # Class for handling binary string operations:
  class Stream

    attr_accessor :endian, :explicit, :index, :string
    attr_reader :errors

    # Initialize the Stream instance.
    def initialize(string, str_endian, explicit, options={})
      # Set instance variables:
      @explicit = explicit # true or false
      @string = string # input binary string
      @string = "" unless @string # if nil, change it to an empty string
      @index = options[:index] || 0
      @errors = Array.new
      set_endian(str_endian) # true or false
    end


    # Adds a pre-encoded string to the end of this instance's string.
    def add_first(binary)
      @string = binary + @string if binary
    end


    # Adds a pre-encoded string to the beginning of this instance's string.
    def add_last(binary)
      @string = @string + binary if binary
    end


    # Decodes a section of the binary string and returns the formatted data.
    def decode(length, type, options = {})
      # Check if values are valid:
      if (@index + length) > @string.length
        # The index number is bigger then the length of the binary string.
        # We have reached the end and will return nil.
        value = nil
      else
        # Decode the string, unless the binary string itself is wanted:
        if options[:bin] == true
          # Return binary string:
          value = @string.slice(@index, length)
        else
          # Decode the binary string and return value:
          value = @string.slice(@index, length).unpack(vr_to_str(type))
          # If the result is an array of one element, return the element instead of the array.
          # If result is contained in a multi-element array, return the original array.
          value = value[0] if value.length == 1
        end
        # Update our position in the string:
        skip(length)
      end
      return value
    end


    # Decodes a tag from a binary string to our standard ascii format ("GGGG,EEEE").
    def decode_tag
      length = 4
      # Check if values are valid:
      if (@index + length) > @string.length
        # The index number is bigger then the length of the binary string.
        # We have reached the end and will return nil.
        tag = nil
      else
        # Decode and process:
        string = @string.slice(@index, length).unpack(@hex)[0].upcase
        if @endian
          tag = string[2..3] + string[0..1] + "," + string[6..7] + string[4..5]
        else
          tag = string[0..3] + "," + string[4..7]
        end
        # Update our position in the string:
        skip(length)
      end
      return tag
    end


    # Encodes content (string, number, array of numbers) and returns the binary string.
    def encode(value, type)
      bin = [value].pack(vr_to_str(type))
    end


    # Encodes content (string, number, array of numbers) to a binary string and pastes it to
    # the beginning of the @string variable of this instance.
    def encode_first(value, type)
      bin = [value].pack(vr_to_str(type))
      @string = bin + @string
    end


    # Encodes content (string, number, array of numbers) to a binary string and pastes it to
    # the end of the @string variable of this instance.
    def encode_last(value, type)
      bin = [value].pack(vr_to_str(type))
      @string = @string + bin
    end


    # Some of the strings that are passed along in the network communication are allocated a fixed length.
    # This method is used to encode such strings.
    def encode_string_with_trailing_spaces(string, target_length)
      length = string.length
      if length < target_length
        return [string].pack(@str)+["20"*(target_length-length)].pack(@hex)
      elsif length == target_length
        return [string].pack(@str)
      else
        raise "The string provided is longer than the allowed maximum length. (string: #{string}, target_length: #{target_length.to_s})"
      end
    end


    # Encodes a tag from its standard text format ("GGGG,EEEE"), to a proper binary string.
    def encode_tag(string)
      if @endian
        tag = string[2..3] + string[0..1] + string[7..8] + string[5..6]
      else
        tag = string[0..3] + string[5..8]
      end
      return [tag].pack(@hex)
    end


    # Encodes and returns a data element value. The reason for not using the encode()
    # method for this is that we may need to know the length of the encoded value before
    # we send it to the encode() method.
    # String values will be checked for possible odd length, and if so padded with an extra byte,
    # to comply with the DICOM standard.
    def encode_value(value, type)
      type = vr_to_str(type)
      if type == @str
        # String: Check length.
        if value.length[0] == 1
          # Odd length (add a zero byte, encode and return):
          return [value].pack(type)+["00"].pack(@hex)
        else
          # Even length (encode and return):
          return [value].pack(type)
        end
      elsif type == @hex
        return [value].pack(type)
      else
        # Number.
        return [value].pack(type)
      end
    end


    # Reset the string variable.
    def reset
      @string = ""
    end


    # Reset the string index variable:
    def reset_index
      @index = 0
    end


    # This method updates the endianness to be used for the binary string, and checks
    # the system endianness to determine which encoding/decoding flags to use.
    def set_endian(str_endian)
      # Update endianness variables:
      @str_endian = str_endian
      configure_endian
      set_string_formats
      set_format_hash
    end


    # Set the hash which is used to convert a data element type (VR) to a encode/decode string.
    def set_format_hash
      @format = {
        "UL" => @ul, # Unsigned long (4 bytes)
        "SL" => @sl, # Signed long (4 bytes)
        "US" => @us, # Unsigned short (2 bytes)
        "SS" => @ss, # Signed short (2 bytes)
        "FL" => @fs, # Floating point single (4 bytes)
        "FD" => @fd, # Floating point double (8 bytes)
        "OB" => @by, # Other byte string (1-byte integers)
        "OF" => @fs, # Other float string (4-byte floating point numbers)
        "OW" => @us, # Other word string (2-byte integers)
        "AT" => @hex, # Tag reference (4 bytes) NB: This may need to be revisited at some point...
        "UN" => @hex, # Unknown information (header element is not recognized from local database)
        "HEX" => @hex, # HEX
        # We have a number of VRs that are decoded as string:
        "AE" => @str,
        "AS" => @str,
        "CS" => @str,
        "DA" => @str,
        "DS" => @str,
        "DT" => @str,
        "IS" => @str,
        "LO" => @str,
        "LT" => @str,
        "PN" => @str,
        "SH" => @str,
        "ST" => @str,
        "TM" => @str,
        "UI" => @str,
        "UT" => @str,
        "STR" => @str
      }
    end


    # Sets the pack/unpack format strings that will be used for encoding/decoding.
    # Some of these will depend on the endianness of the system and file.
    def set_string_formats
      if @endian
        # System endian equals string endian:
        # Native byte order.
        @by = "C*" # Byte (1 byte)
        @us = "S*" # Unsigned short (2 bytes)
        @ss = "s*" # Signed short (2 bytes)
        @ul = "I*" # Unsigned long (4 bytes)
        @sl = "l*" # Signed long (4 bytes)
        @fs = "e*" # Floating point single (4 bytes)
        @fd = "E*" # Floating point double ( 8 bytes)
      else
        # System endian is opposite string endian:
        # Network byte order.
        @by = "C*"
        @us = "n*"
        @ss = "n*" # Not correct (gives US)
        @ul = "N*"
        @sl = "N*" # Not correct (gives UL)
        @fs = "g*"
        @fd = "G*"
      end
      # Format strings that are not dependent on endianness:
      @str = "a*"
      @hex = "H*" # (this may be dependent on endianness(?))
    end


    # Applies an offset (positive or negative) to the index variable.
    def skip(offset)
      @index += offset
    end


    # Following methods are private:
    private


    # Determine the endianness of the system.
    # Together with the specified endianness of the binary string,
    # this will decide what encoding/decoding flags to use.
    def configure_endian
      x = 0xdeadbeef
      endian_type = {
        Array(x).pack("V*") => false, #:little
        Array(x).pack("N*") => true   #:big
      }
      @sys_endian = endian_type[Array(x).pack("L*")]
      # Use a "relationship endian" variable to guide encoding/decoding options:
      if @sys_endian == @str_endian
        @endian = true
      else
        @endian = false
      end
    end


    # Convert a data element type (VR) to a encode/decode string.
    def vr_to_str(vr)
      str = @format[vr]
      if str == nil
        errors << "Warning: Element type #{vr} does not have a reading method assigned to it. Something is not implemented correctly or the DICOM data analyzed is invalid."
        str = @hex
      end
      return str
    end

  end # of class
end # of module