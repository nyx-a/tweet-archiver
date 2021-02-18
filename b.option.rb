
require 'toml'
require_relative 'b.structure.rb'

module B
end

class B::Option
  def initialize **hsh # { long => description }
    @bare     = [ ]
    @property = [ ] # Property
    @buffer   = { } # Property => "buffer"
    @value    = nil # Property => value
    hsh.each{ register Property.new long:_1, description:_2 }
  end

  def register *arr
    for p in arr.flatten
      raise "long key cannot be omitted" if p.long.nil?
      raise "long key `#{p.long}` duplicated" if find_l p.long
      raise "short key `#{p.short}` duplicated" if find_s p.short
      @property.push p
    end
  end

  def find_l str
    str = str.to_s
    @property.find{ _1.long == str }
  end
  private :find_l

  def find_s str
    str = str.to_s
    @property.find{ _1.short == str }
  end
  private :find_s

  def plong str
    find_l(str) or raise "invalid long option --#{str}"
  end

  def pshort str
    find_s(str) or raise "invalid short option -#{str}"
  end

  def [] l
    if @value.nil?
      raise "#{self.class} is not available until the make() is called"
    end
    @value[plong l]
  end

  def short **hsh # { long => short }
    hsh.each do
      p = plong _1
      if p.short
        raise "The key #{p.long}(#{p.short}) has already been set"
      end
      p.short = _2
    end
  end

  def boolean *arr # [ long ]
    arr.flatten.each{ plong(_1).boolean = true }
  end

  def essential *arr # [ long ]
    arr.flatten.each{ plong(_1).essential = true }
  end

  def normalizer **hsh # { long => normalizer }
    hsh.each{ plong(_1).normalizer = _2 }
  end

  def default **hsh # { long => default }
    hsh.each{ plong(_1).default = _2 }
  end

  # parse() raises an exception if there is an unknown key.
  def parse argv
    @bare.clear
    eoo = argv.index '--' # end of options
    if eoo
      tail = argv[eoo+1 ..      ]
      argv = argv[      .. eoo-1]
    end
    re = /^-{1,2}(?=[^-])/
    for first,second in argv.chunk_while{ _1 =~ re and _2 !~ re }
      case first
      when /^--(?i:no)-(?=[^-])/
        # --no-long
        p = plong $~.post_match
        raise "#{p.long} is not boolean" unless p.boolean
        @buffer[p] = false
        @bare.push second if second
      when /^--(?=[^-])/
        # --long
        p = plong $~.post_match
        if p.boolean
          @buffer[p] = true
          @bare.push second if second
        else
          @buffer[p] = second
        end
      when /^-(?=[^-])(?!.*[0-9])/
        # -short
        letters = $~.post_match.chars
        b,o = letters.map{ pshort _1 }.partition &:boolean
        b.each{ @buffer[_1] = true }
        o.each{ @buffer[_1] = nil }
        if second
          if o.empty?
            @bare.push second
          else
            @buffer[o.pop] = second
          end
        end
      else
        # bare
        @bare.push first
      end
    end
    @bare.concat tail if tail
  end

  # Flatten a nested hash and
  # change the keys to dot notation.
  def dn_flatten hash, ancestor=[ ]
    result = { }
    for key,value in hash
      present = ancestor + [key]
      if value.is_a? Hash and !value.empty?
        result.merge! dn_flatten value, present
      else
        result.merge! present.join('.') => value
      end
    end
    result
  end
  private :dn_flatten

  # underlay!() will ignore any unknown keys.
  def underlay! other
    for k,v in dn_flatten(other).slice(*@property.map(&:long))
      p = plong k
      unless @buffer.key? p
        @buffer[p] = v
      end
    end
  end

  # If the normalizer returns nil,
  # the original string will be used as is.
  # (Verification only, no conversion.)
  def normalize p
    bd = @buffer.fetch p, p.default
    return nil if bd.nil?
    begin
      p.normalizer&.call(bd) || bd
    rescue Exception => e
      raise %Q`verification failed --#{p.long} "#{bd}" #{e.message}`
    end
  end
  private :normalize

  def make
    @value = { } # <-- here

    if find_l('toml').nil?
      register Property.new(
        long:        'toml',
        description: 'TOML file to underlay',
      )
    end
    if find_l('help').nil?
      register Property.new(
        long:        'help',
        description: 'Show this help',
        boolean:     true,
      )
    end

    # overlay command line option
    parse ARGV

    # underlay TOML
    cfg = normalize plong :toml
    underlay! TOML.load_file cfg if cfg

    # normalize buffer/default
    for p in @property
      @value[p] = normalize p
    end
    blank = @property.select{ _1.essential and @value[_1].nil? }
    unless blank.empty?
      raise "cannot be omitted #{blank.map(&:long).join(',')}"
    end
    if self[:help]
      puts "Options:"
      puts help.gsub(/^/, '  ')
      puts
      exit
    end
  end

  def make!(...)
    make(...)
    ARGV.clear
  end

  def to_hash
    if @value.nil?
      raise "#{self.class} is not available until the make() is called"
    end
    @property.map{ [_1.long, @value[_1]] }.to_h
  end

  def slice *longkeys
    filter = longkeys.flatten.map{ plong _1 }
    @property.intersection(filter).map{ [_1.long.to_sym, @value[_1]] }.to_h
  end

  def except *longkeys
    mask = longkeys.flatten.map{ plong _1 }
    @property.difference(mask).map{ [_1.long.to_sym, @value[_1]] }.to_h
  end

  def bare
    @bare
  end

  def help
    matrix = @property.map do |p|
      [
        (p.short ? "-#{p.short}" : ''),
        "--#{p.long}",
        "#{p.description}#{(p.boolean ? ' (boolean)' : '')}",
      ]
    end
    longest = matrix.transpose.map{ _1.map(&:to_s).map(&:size).max }
    matrix.map do |row|
      "%-*s %-*s %-*s" % longest.zip(row).flatten
    end.join "\n"
  end

  def inspect
    a = @property.map do |p|
      "--#{p.long} #{@value&.[](p).inspect} <- #{(@buffer[p] || p.default).inspect}"
    end
    a.push "  Bare #{@bare.map(&:inspect).join ', '}"
    if @value.nil?
      a.push "This instance isn't available until the make() is called."
    end
    a.join "\n"
  end
end

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Option Element

class B::Option::Property < B::Structure
  attr_reader   :long        # String
  attr_reader   :short       # String ( single letter )
  attr_reader   :description # String
  attr_reader   :boolean     # true / false
  attr_reader   :essential   # true / false
  attr_reader   :normalizer  # any object that has a call() method
  attr_accessor :default     # anything

  def long= o
    @long = o.to_s
  end

  def short= o
    if o.length != 1
      raise "#{@long}: Mustbe a single letter `#{o}`"
    end
    if o =~ /[0-9]/
      raise "#{@long}: Numbers cannot be used for short option `#{o}`"
    end
    @short = o.to_s
  end

  def boolean= o
    unless o==true or o==false
      raise "#{@long}: boolean must be a true or false"
    end
    @boolean = o
  end

  def normalizer= o
    if o.is_a? Symbol or o.is_a? String
      unless B::Option::Normalizer.respond_to? o
        raise "#{@long}: invalid built-in normalizer #{o}"
      end
      @normalizer = B::Option::Normalizer.method o
    else
      unless o.respond_to? :call
        raise "#{@long}: normalizer must have a call() method"
      end
      @normalizer = o
    end
  end

  def essential= o
    unless o==true or o==false
      raise "#{@long}: essential must be a true or false"
    end
    @essential = o
  end

  def description= o
    @description = o.to_s
  end

  def hash
    @long.hash
  end

  def == other
    self.hash == other.hash
  end
end

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# built-in normalizers

module B::Option::Normalizer
  module_function

  def to_integer s
    return nil if s.is_a? Integer
    raise "Isn't String #{s}(#{s.class})" unless s.is_a? String
    raise "doesn't look like a Integer" if s !~ /^[+-]?\d+$/
    s.to_i
  end

  def to_float s
    return nil if s.is_a? Float
    raise "Isn't String #{s}(#{s.class})" unless s.is_a? String
    raise "doesn't look like a Float" if s !~ /^[+-]?\d+(?:\.\d+)?$/
    s.to_f
  end
end

