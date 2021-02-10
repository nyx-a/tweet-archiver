#! /usr/bin/env ruby

require 'colorize'
require_relative 'b.option.rb'
require_relative 'b.path.rb'
require_relative 'b.log.rb'
require_relative 'extend.rb'
require_relative 'db.rb'

optn = B::Option.new(
  'twitter.consumer_key'        => "YOUR_CONSUMER_KEY",
  'twitter.consumer_secret'     => "YOUR_CONSUMER_SECRET",
  'twitter.access_token'        => "YOUR_ACCESS_TOKEN",
  'twitter.access_token_secret' => "YOUR_ACCESS_TOKEN_SECRET",
  'mongo.host'                  => "Host",
  'mongo.db'                    => "Database",
  'mongo.user'                  => "Username",
  'mongo.pw'                    => "Password",
  'mongo.auth'                  => "Authentication database",
  'tweet'                       => "tweet ID",
  'uname'                       => "user name",
  'uid'                         => "user ID",
  'count'                       => "count",
  'whois'                       => "user name",
  'trends'                      => "WOEID (tokyo is 1118370)",
  'irb'                         => "ruby REPL",
  'toml'                        => "Config File",
)
optn.boolean :irb
optn.default(
  'mongo.host' => '127.0.0.1',
  'mongo.db'   => 'twitter',
  'count'      => 200,
)
optn.essential(
  'twitter.consumer_key',
  'twitter.consumer_secret',
  'twitter.access_token',
  'twitter.access_token_secret',
)
optn.normalizer(
  count:  'to_integer',
  uid:    'to_integer',
  trends: 'to_integer',
)
optn.default toml:B::Path.xdgattempt('tweet-archiver.toml', :config)
optn.make!

twitter = Twitter::REST::Client.new(
  consumer_key:        optn['twitter.consumer_key'],
  consumer_secret:     optn['twitter.consumer_secret'],
  access_token:        optn['twitter.access_token'],
  access_token_secret: optn['twitter.access_token_secret'],
)

log = B::Log.new file:STDOUT, format:'%T.%1N'

db = DB.new(
  host: optn['mongo.host'],
  db:   optn['mongo.db'],
  user: optn['mongo.user'],
  pw:   optn['mongo.pw'],
  auth: optn['mongo.auth'],
  log:  log,
  tw:   twitter,
)

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

for f in optn.bare
  ids = open(f).each_line.map{ $&.to_i if _1 =~ /\d+/ }.compact
  ids.each do
    begin
      result = db.up _1, count:200
      log.d _1, result.size
      sleep 1
    end until result.empty?
    sleep rand 3..10
  end
end

if optn[:tweet]
  result = twitter.status optn[:tweet]
  pp result.to_h
  p db.save! result
end

if optn[:uid]
  db.get_all optn[:uid]
end

if optn[:whois]
  for i in twitter.user_search(optn[:whois])
    puts "#{i.screen_name} #{i.name} #{i.id.to_s.colorize :yellow} #{i.description.inspect}"
  end
end

if optn[:trends]
  db.save_trends optn[:trends]
end

if optn[:irb]
  binding.irb
end

