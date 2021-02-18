
# node of indented text tree

module B
  # namespace
end

class B::IndentedText
  attr_accessor :string
  attr_accessor :children

  def initialize string:nil, children:nil
    @string   = string
    @children = [children].flatten if children
  end

  def parse raw
    take_lines! self.class.scan_lines raw
  end

  def take_lines! aoh
    return if aoh.empty?
    @children = [ ]
    min = aoh.map{ _1[:indent] }.min
    aoh = aoh.clone
    while i = aoh.rindex{ _1[:indent] == min }
      head = aoh.slice!(i)
      rest = aoh.slice!(i..)
      newitem = self.class.new
      newitem.string = head[:string]
      newitem.take_lines! rest
      @children.unshift newitem
    end
    unless aoh.empty?
      raise SyntaxError,
        "broken indent:\n#{aoh.map{_1[:string]}.join("\n")}"
    end
    self
  end
  protected :take_lines!

  def [] s
    @children.find{ s === _1.string }
  end

  def inspect indent:2
    self.class.to_s self, indent:indent
  end

  #
  #* class methods
  #

  def self.single_path *list
    list.flatten.reverse.inject nil do |b,a|
      new string:a, children:b
    end
  end

  def self.to_s o, indent:2
    l = "#{String === o.string ? o.string : o.string.inspect}\n"
    if o.children
      l += o.children
        .map{ to_s _1, indent:indent }
        .join
        .gsub(/^/, ' ' * indent)
    end
    l
  end

  def self.scan_lines raw
    raw.each_line.map do
      i = (_1 =~ /[^ ]/)
      l = _1.strip
      { indent:i, string:l } unless l.empty?
    end.compact
  end
end

#
#*
#

if __FILE__ == $0
  root = B::IndentedText.new
  root.parse ARGF.read
  p root
end

