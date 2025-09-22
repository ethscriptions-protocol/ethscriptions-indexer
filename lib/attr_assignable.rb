module AttrAssignable
  extend T::Sig

  sig { params(attrs: T::Hash[Symbol, T.untyped]).void }
  def assign_attributes(attrs)
    attrs.each do |k, v|
      setter = "#{k}=".to_sym
      if respond_to?(setter)
        send(setter, v)
      else
        raise NoMethodError, "Unknown attribute #{k} for #{self.class}"
      end
    end
  end
end
