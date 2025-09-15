module BlobUtils
  # Constants from Viem
  BLOBS_PER_TRANSACTION = 2
  BYTES_PER_FIELD_ELEMENT = 32
  FIELD_ELEMENTS_PER_BLOB = 4096
  BYTES_PER_BLOB = BYTES_PER_FIELD_ELEMENT * FIELD_ELEMENTS_PER_BLOB
  MAX_BYTES_PER_TRANSACTION = BYTES_PER_BLOB * BLOBS_PER_TRANSACTION - 1 - (1 * FIELD_ELEMENTS_PER_BLOB * BLOBS_PER_TRANSACTION)

  # Error Classes
  class BlobSizeTooLargeError < StandardError; end
  class EmptyBlobError < StandardError; end
  class IncorrectBlobEncoding < StandardError; end

  # Adapted from Viem
  def self.to_blobs(data:)
    raise EmptyBlobError if data.empty?
    raise BlobSizeTooLargeError if data.bytesize > MAX_BYTES_PER_TRANSACTION
    
    if data =~ /\A0x([a-f0-9]{2})+\z/i
      data = [data].pack('H*')
    end

    blobs = []
    position = 0
    active = true

    while active && blobs.size < BLOBS_PER_TRANSACTION
      blob = []
      size = 0

      while size < FIELD_ELEMENTS_PER_BLOB
        bytes = data.byteslice(position, BYTES_PER_FIELD_ELEMENT - 1)

        # Push a zero byte so the field element doesn't overflow
        blob.push(0x00)

        # Push the current segment of data bytes
        blob.concat(bytes.bytes) unless bytes.nil?

        # If the current segment of data bytes is less than 31 bytes,
        # stop processing and push a terminator byte to indicate the end of the blob
        if bytes.nil? || bytes.bytesize < (BYTES_PER_FIELD_ELEMENT - 1)
          blob.push(0x80)
          active = false
          break
        end

        size += 1
        position += (BYTES_PER_FIELD_ELEMENT - 1)
      end

      blob.fill(0x00, blob.size...BYTES_PER_BLOB)
      
      blobs.push(blob.pack('C*').unpack1("H*"))
    end

    blobs
  end
  
  def self.from_blobs(blobs:)
    concatenated_hex = blobs.map do |blob|
      hex_blob = blob.sub(/\A0x/, '')
      
      sections = hex_blob.scan(/.{64}/m)
      
      last_non_empty_section_index = sections.rindex { |section| section != '00' * 32 }
      
      if last_non_empty_section_index.nil?
        non_empty_sections = []
      else
        non_empty_sections = sections.take(last_non_empty_section_index + 1)
        
        last_non_empty_section = non_empty_sections.last
        
        if last_non_empty_section == "0080" + "00" * 30
          non_empty_sections.pop
        else
          last_non_empty_section.gsub!(/80(00)*\z/, '')
        end
      end
      
      non_empty_sections = non_empty_sections.map do |section|
        unless section.start_with?('00')
          raise IncorrectBlobEncoding, "Expected the first byte to be zero"
        end
        
        section.delete_prefix("00")
      end
      
      non_empty_sections.join
    end.join
    
    [concatenated_hex].pack("H*")
  end
end
