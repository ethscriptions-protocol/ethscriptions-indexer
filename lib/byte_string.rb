class ByteString
  class InvalidByteLength < StandardError; end
  
  sig { params(bin: String).void }
  def initialize(bin)
    validate_bin!(bin)
    @bytes = bin.dup.freeze
  end

  sig { params(hex: String).returns(ByteString) }
  def self.from_hex(hex)
    bin = hex_to_bin(hex)
    enforce_length!(bin)
    new(bin)
  end

  sig { params(bin: String).returns(ByteString) }
  def self.from_bin(bin)
    enforce_length!(bin)
    new(bin)
  end
  
  sig { void }
  def to_s
    raise "to_s not implemented for #{self.class}"
  end
  
  sig { void }
  def to_json
    raise "to_json not implemented for #{self.class}"
  end

  sig { returns(String) }
  def to_hex
    "0x" + @bytes.unpack1('H*')
  end

  sig { returns(String) }
  def to_bin
    @bytes
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
    unless other.is_a?(ByteString)
      raise ArgumentError, "can't compare #{other.class} with #{self.class}"
    end
    
    other.to_bin == @bytes
  end
  alias eql? ==

  sig { returns(Integer) }
  def hash
    @bytes.hash
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class} len=#{@bytes.bytesize} hex=#{to_hex}>"
  end

  # subclasses can override to return an Integer byte-length to enforce
  sig { returns(T.nilable(Integer)) }
  def self.required_byte_length
    nil
  end
  
  sig { params(obj: T.untyped).returns(T.untyped) }
  def self.deep_hexify(obj)
    case obj
    when ByteString
      obj.to_hex
    when Array
      obj.map { |v| deep_hexify(v) }
    when Hash
      obj.transform_values { |v| deep_hexify(v) }
    else
      obj
    end
  end
  
  sig { returns(ByteString) }
  def keccak256
    ByteString.from_bin(Eth::Util.keccak256(self.to_bin))
  end

  private

  sig { params(bin: String).void }
  def validate_bin!(bin)
    unless bin.is_a?(String) && bin.encoding == Encoding::ASCII_8BIT
      raise ArgumentError, 'binary string with ASCII-8BIT encoding required'
    end
    self.class.enforce_length!(bin)
  end

  sig { params(hex: String).returns(String) }
  def self.hex_to_bin(hex)
    unless hex.start_with?('0x')
      raise ArgumentError, 'hex string must start with 0x'
    end
    
    cleaned = hex[2..]
    
    unless cleaned.match?(/\A[0-9a-fA-F]*\z/)
      raise ArgumentError, "invalid hex string: #{hex}"
    end
    unless cleaned.length.even?
      raise ArgumentError, "hex string length must be even: #{hex}"
    end
    [cleaned].pack('H*')
  end

  sig { params(bin: String).void }
  def self.enforce_length!(bin)
    len = required_byte_length
    return if len.nil?
    unless bin.bytesize == len
      raise InvalidByteLength, "#{name} expects #{len} bytes, got #{bin.bytesize}"
    end
  end

  sig { returns(String) }
  attr_reader :bytes
end
