
require 'mongo'
require 'grape'
require_relative 'b.option.rb'
require_relative 'b.path.rb'

OP = B::Option.new(
  'mongo.host' => "Host",
  'mongo.db'   => "Database",
  'mongo.user' => "Username",
  'mongo.pw'   => "Password",
  'mongo.auth' => "Authentication database",
  'toml'       => "Config file",
)
OP.default(
  'mongo.host' => '127.0.0.1',
  'mongo.db'   => 'twitter',
)
OP.essential(
  'mongo.host',
  'mongo.db',
  'mongo.user',
  'mongo.pw',
)
OP.short(
  'mongo.host' => 'h',
  'mongo.db'   => 'd',
  'mongo.user' => 'u',
  'mongo.pw'   => 'p',
  'mongo.auth' => "a",
)
OP.default toml:B::Path.xdgattempt('tweet-archiver.toml', :config)
OP.make!

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

class Tapi < Grape::API
  format :json

  client = Mongo::Client.new(
    [OP['mongo.host']],
    database:    OP['mongo.db'],
    user:        OP['mongo.user'],
    password:    OP['mongo.pw'],
    auth_source: OP['mongo.auth'],
  )
  tweet = client['tweet']
  range = client['range']

  get '/' do
    tweet.find({}, {sort:{created_at:-1}, limit:3}).to_a
  end

  get 'users' do
    range.find({}, {projection:{_id:1}}).map{ _1[:_id] }
  end
end

