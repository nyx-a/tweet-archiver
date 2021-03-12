#! /usr/bin/env ruby

require 'pp'
require 'colorize'
require_relative 'b.option.rb'
require_relative 'b.path.rb'
require_relative 'b.log.rb'
require_relative 'b.indentedtext.rb'
require_relative 'db.rb'

optn = B::Option.new(
  'twitter.consumer_key'        => "consumer key",
  'twitter.consumer_secret'     => "consumer secret",
  'twitter.access_token'        => "access token",
  'twitter.access_token_secret' => "access token secret",
  'mongo.host'                  => "Host",
  'mongo.db'                    => "Database",
  'mongo.user'                  => "Username",
  'mongo.pw'                    => "Password",
  'mongo.auth'                  => "Authentication database",
  'trace_replies'               => "trace upstream replies",
  'tweet'                       => "tweet ID",
  'user'                        => "user ID",
  'count'                       => "count",
  'whois'                       => "search user",
  'known_users'                 => 'check all known users',
  'show'                        => 'show tweets',
  'repl'                        => "run Ruby REPL (irb)",
  'toml'                        => "Config File",
)
optn.boolean :repl, :known_users, :show, :trace_replies
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
  'trace_replies' => 'r',
  'tweet'         => 't',
  'known_users'   => 'k',
  'count'         => 'c',
  'show'          => 's',
)
optn.default toml:B::Path.xdgattempt('tweet-archiver.toml', :config)
optn.make!

twitter = Twitter::REST::Client.new(
  consumer_key:        optn['twitter.consumer_key'],
  consumer_secret:     optn['twitter.consumer_secret'],
  access_token:        optn['twitter.access_token'],
  access_token_secret: optn['twitter.access_token_secret'],
)
twitter.timeouts = {
  connect: 60,
  read:    60,
  write:   60,
}

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
    db.up uid, count:optn[:count], with_replies:optn[:trace_replies]
    sleep 1
  end
end

if optn[:show]
  aoh = db.find(
    { },
    sort:{ _id:-1 },
    projection:{ _id:1, created_at:1, user_screen_name:1, text:1 },
    limit:optn[:count]
  )
  for h in aoh
    i = h[:_id].to_s.colorize :red
    d = h[:created_at].getlocal.strftime('%a %H:%M:%S').colorize :cyan
    u = h[:user_screen_name].colorize(color: :black, background: :green)
    t = h[:text].gsub(/\n/, ' ')
    if t =~ /^RT @/
      t = t.colorize :yellow
    end
    puts "#{d} #{u} #{t} #{i}"
  end
end

if optn[:repl]
  # Hello.
  # you can use object twitter, which is a instance of Twitter::REST::Client
  # you can use object db,      which is a instance of DB
  binding.irb
end

