#! /usr/bin/env ruby

require 'pp'
require 'colorize'
require_relative 'b.option.rb'
require_relative 'b.path.rb'
require_relative 'b.log.rb'
require_relative 'b.indentedtext.rb'
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
  'user'                        => "user ID",
  'count'                       => "count",
  'whois'                       => "search user",
  'known_users'                 => 'check all known users',
  'repl'                        => "run Ruby REPL (irb)",
  'toml'                        => "Config File",
)
optn.boolean :repl, :known_users
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
  'mongo.host',
  'mongo.db',
  'mongo.user',
  'mongo.pw',
)
optn.normalizer(
  count:  'to_integer',
  user:   'to_integer',
)
optn.short(
  'known_users' => 'k',
)
optn.default toml:B::Path.xdgattempt('tweet-archiver.toml', :config)
optn.make!

twitter = Twitter::REST::Client.new(
  consumer_key:        optn['twitter.consumer_key'],
  consumer_secret:     optn['twitter.consumer_secret'],
  access_token:        optn['twitter.access_token'],
  access_token_secret: optn['twitter.access_token_secret'],
)

log = B::Log.new STDOUT, format:'%T.%1N'

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

unless optn.bare.empty?
  root = B::IndentedText.new.parse open(optn.bare.shift).read
  branch = optn.bare.shift
  if branch
    c = root[branch]&.children
    if c.nil?
      log.e "no such branch #{branch}"
    end
  else
    c = root.children.map(&:children).flatten
  end

  if c
    ids = c.map(&:string).map{ $&.to_i if _1 =~ /\d+/ }.compact
    ids.each do
      begin
        result = db.up _1, count:200
        log.d _1, result.size
        sleep 2
      end until result.empty?
      sleep 3
    end
  end
end

if optn[:tweet]
  db.get optn[:tweet], with_replies:true
end

if optn[:user]
  db.get_all optn[:user]
end

if optn[:whois]
  for i in twitter.user_search(optn[:whois])
    puts "#{i.id.to_s.colorize :yellow} @#{i.screen_name} #{i.name} #{i.description.inspect.colorize :cyan}"
  end
end

if optn[:known_users]
  for uid in db.known_users
    db.up uid, count:optn[:count]
    sleep 1
  end
end

if optn[:repl]
  # Hello.
  # you can use object twitter, which is a instance of Twitter::REST::Client
  # you can use object db,      which is a instance of DB
  binding.irb
end

