
require 'logger'

module B
  # for namespace
end

class B::Log
  def initialize(
    file,
    age:       3,
    size:      1_000_000,
    format:    '%F %T.%1N',
    separator: ' | '
  )
    @logger     = Logger.new file, age, size
    @format     = format
    @separator  = separator
    @padding    = ' ' * Time.now.strftime(@format).length
    @inactive   = { }
  end

  def output *message
    unless @inactive[__callee__]
      @logger << make(__callee__, Time.now, message.join(' '))
    end
  end
  LEVELS = 'diwef'.freeze
  LEVELS.each_char { |c| alias_method c, :output }
  undef :output

  def loglevel= letter
    i = LEVELS.index letter.to_s.downcase.chr
    if i.nil?
      return nil
    end
    for x in LEVELS[...i].each_char
      @inactive[x.to_sym] = true
    end
    for x in LEVELS[i..].each_char
      @inactive[x.to_sym] = false
    end
    LEVELS[i]
  end

  def blank
    @logger << "- #{@padding}#{@separator}\n"
  end

  def gap
    @logger << "\n"
  end

  def close
    @logger.close
  end

  private

  def make severity, time, message
    tm = time.strftime @format
    h1 = [severity.upcase,   tm      ].join(' ')
    h2 = [severity.downcase, @padding].join(' ')
    [
      h1,
      @separator,
      message.gsub("\n", "\n#{h2}#{@separator}"),
      "\n"
    ].join
  end
end

