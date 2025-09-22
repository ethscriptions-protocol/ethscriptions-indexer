class Hash32 < ByteString
  sig { override.returns(Integer) }
  def self.required_byte_length
    32
  end
end
