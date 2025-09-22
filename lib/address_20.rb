class Address20 < ByteString
  sig { override.returns(Integer) }
  def self.required_byte_length
    20
  end
end
