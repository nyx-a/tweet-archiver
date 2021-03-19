#! /usr/bin/env ruby

require 'pp'
require 'colorize'
require_relative 'b.option.rb'
require_relative 'b.path.rb'
require_relative 'b.log.rb'
require_relative 'ta.rb'

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
  'replies'                     => "trace upstream replies",
  'tweet'                       => "tweet(status) ID",
  'uid'                         => "user ID",
  'count'                       => "count",
  'uname'                       => "search user with screen_name",
  'known_users'                 => 'check all known users',
  'show'                        => 'show tweets',
  'repl'                        => "run Ruby REPL (irb)",
  'toml'                        => "Config File",
)
optn.boolean :repl, :known_users, :show, :replies
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
  uid:    'to_integer',
  tweet:  'to_integer',
)
optn.short(
  'replies'       => 'r',
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

ta = TA.new(
  host: optn['mongo.host'],
  db:   optn['mongo.db'],
  user: optn['mongo.user'],
  pw:   optn['mongo.pw'],
  auth: optn['mongo.auth'],
  log:  log,
  tw:   twitter,
)

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

if optn[:tweet]
  ta.get optn[:tweet], with_replies:optn[:replies]
end

if optn[:uid]
  ta.get_all optn[:uid], count:optn[:count]
end

if optn[:uname]
  u = twitter.user_search(optn[:uname]).find{
    _1.screen_name == optn[:uname]
  }
  if u
    puts [
      u.id.to_s.colorize(:yellow),
      "@#{u.screen_name}",
      u.name,
      u.description.inspect.colorize(:cyan),
    ].join(' ')
    ta.get_all u.id, count:optn[:count]
  end
end

if optn[:known_users]
  for uid in ta.known_users
    log.d uid
    ta.up uid, count:optn[:count], with_replies:optn[:replies]
    sleep 1
  end
end

if optn[:show]
  aoh = ta.find(
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
  # you can use object ta,      which is a instance of TA
  binding.irb
end

