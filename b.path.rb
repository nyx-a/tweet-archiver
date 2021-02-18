
module B
  # Reinvention
end

class B::Path < String

  def self.dig p, base:'.'
    new = allocate.replace File.expand_path p, base
    new.split(File::SEPARATOR).inject do |stack,iter|
      stack = File.join stack, iter
      Dir.mkdir stack unless Dir.exist? stack
      stack
    end
    new.raise_unless 'writable'
    return new.tail
  end

  def initialize p, base:'.', confirm:'exist'
    replace File.expand_path p, base
    raise_unless confirm if confirm
    self.tail! if [confirm].flatten.any? %r/directory/
  end

  def +(...)
    self.class.allocate.replace super(...)
  end

  def dig base:'.'
    replace self.class.dig self, base:base
  end

  #
  # '/' at the right end
  #

  def tail
    self.class.allocate.replace(
      sub %r`#{File::SEPARATOR}*$`, File::SEPARATOR
    )
  end

  def tail!
    self.replace tail
  end

  def untail
    self.class.allocate.replace(
      sub %r`#{File::SEPARATOR}+$`, ''
    )
  end

  def untail!
    self.replace untail
  end

  #
  # File Test
  #

  # Converse Non-Implication (other - self)
  def cni *other
    other.flatten.reject{ File.public_send "#{_1}?", self }
  end

  def confirm(...)
    cni(...).empty?
  end

  def aint(...)
    not confirm(...)
  end

  def raise_unless(...)
    n = cni(...)
    unless n.empty?
      raise "#{self.class}(#{self}) is not #{n.join(',')}"
    end
    self
  end
  alias :undoubtedly :raise_unless
  alias :expect :raise_unless

  #
  # Method Pass through
  #

  def method_missing sym, *args, &block
    if File.respond_to? sym
      File.send sym, self, *args, &block
    else
      super
    end
  end

  def respond_to_missing? sym, include_private
    if File.respond_to? sym
      true
    else
      super
    end
  end

end

#
# XDG Base Directory Support
#

class B::Path
  XDGConfig = [
    ENV['XDG_CONFIG_HOME'],             # 1
    "#{ENV['HOME']}/.config",           # 2
    ENV['XDG_CONFIG_DIRS']&.split(':'), # 3
    '/etc/xdg',                         # 4
  ].flatten.compact
  XDGConfig.map!{ B::Path.new(_1, confirm:nil).tail }

  XDGCache = [ "#{ENV['HOME']}/.cache" ] # 2
  if ENV.key? 'XDG_CACHE_HOME'
    XDGCache.unshift ENV['XDG_CACHE_HOME'] # 1
  end
  XDGCache.map!{ B::Path.new(_1, confirm:nil).tail }

  def self.xdgfind fname, kind
    literal = Object.const_get "B::Path::XDG#{kind.capitalize}"
    list = literal.map{ _1 + fname }
    list.unshift B::Path.new(fname, confirm:nil).tail
    list.find{ _1.confirm :exist }
  end

  def self.xdgvisit fname, kind
    literal = Object.const_get "B::Path::XDG#{kind.capitalize}"
    p = literal.first + fname
    B::Path.dig p.dirname
    p
  end

  def self.xdgattempt fname, kind
    literal = Object.const_get "B::Path::XDG#{kind.capitalize}"
    literal.map{ _1 + fname }.find &:exist?
  end
end

