
module B
  def self.callablize object
    case
    when object.respond_to?(:call)
      object
    when object.respond_to?(:to_proc)
      object.to_proc
    when object.respond_to?(:to_sym)
      object.to_sym.to_proc
    else
      raise "Can't make it callable #{object}(#{object.class})"
    end
  end

  # force call
  def self.fcall(object, ...)
    callablize(object).call(...)
  end
end


class B::Structure
  # Recursive
  def self.to_h structure, k:'to_sym', v:'itself'
    structure.to_h do |key,value|
      key = B.fcall k, key
      value = if value.is_a? B::Structure
                to_h value, k:k, v:v
              else
                B.fcall v, value
              end
      [key, value]
    end
  end

  def clear padding=nil
    for sym in public_methods(false).grep(/(?<!=)=$/)
      instance_variable_set "@#{sym[..-2]}", padding
    end
    return self
  end

  def initialize(...)
    clear
    set!(...)
  end

  def set! **hash
    for k,v in hash
      sym = "#{k}=".to_sym
      if respond_to? sym
        self.send sym, v # even if v is a nil
      else
        raise KeyError, "Unknown element #{k.inspect}"
      end
    end
    return self
  end

  # -> B::Structure // nil will overwrite
  def merge! *others
    others.inject self do |a,b|
      a.set!(**b)
    end
  end
  alias :update :merge!

  # -> B::Structure // nil will overwrite
  def merge(...)
    self.clone.merge!(...)
  end

  # -> B::Structure // nil is transparent
  def overlay! *others
    merge!(*others.map(&:compact))
  end

  # -> B::Structure // nil is transparent
  def overlay(...)
    self.clone.overlay!(...)
  end

  # -> B::Structure // nil is transparent
  def underlay *others
    r = others.reverse.push self
    t = self.class.new(**r.shift)
    t.overlay!(*r)
  end

  # -> B::Structure // nil is transparent
  def underlay!(...)
    set!(**underlay(...))
  end

  def keys m='to_sym'
    instance_variables.map{ B.fcall m, _1[1..] }
  end

  # -> Hash // exclude nil
  def slice *ks, k:'to_sym', v:'itself'
    nh = { }
    for i in ks.flatten
      at = "@#{i}"
      if instance_variable_defined? at
        value = instance_variable_get at
        unless value.nil?
          nh[B.fcall(k, i)] = B.fcall(v, value)
        end
      else
        raise KeyError, "Unknown element #{i}"
      end
    end
    return nh
  end

  # -> Hash // exclude nil
  def except *ks, k:'to_sym', v:'itself'
    ks = ks.flatten.map &:to_sym
    ks.each do
      unless instance_variable_defined? "@#{_1}"
        raise KeyError, "Unknown element #{_1}"
      end
    end
    nh = { }
    for i in self.keys - ks
      value = instance_variable_get "@#{i}"
      unless value.nil?
        nh[B.fcall(k, i)] = B.fcall(v, value)
      end
    end
    return nh
  end

  # -> Array
  def to_a k:'to_sym', v:'itself'
    instance_variables.map do |key|
      [
        B.fcall(k, key[1..]),
        B.fcall(v, instance_variable_get(key)),
      ]
    end
  end

  # -> Enumerator
  def map k:'to_sym', v:'itself', &b
    to_a(k:k, v:v).map(&b)
  end

  # -> Hash
  def to_h k:'to_sym', v:'itself', &b
    to_a(k:k, v:v).to_h(&b)
  end
  alias :to_hash :to_h

  # -> Hash
  def compact(...)
    to_h(...).compact
  end

  def inspect indent:2
    stuff = self.map do |k,v|
      i = v.is_a?(B::Structure) ? v.inspect(indent:indent) : v.inspect
      "#{k} = #{i}"
    end.join("\n").gsub(/^/, ' '*indent)
    "<#{self.class.name}>\n#{stuff}"
  end
end

