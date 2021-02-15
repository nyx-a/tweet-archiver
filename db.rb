
require 'mongo'

class DB
  def initialize host:, db:, user:, pw:, auth:, tw:, log:nil
    @log = log
    @tclient = tw # Twitter::REST::Client
    mc = Mongo::Client.new(
      [host],
      database:    db,
      user:        user,
      password:    pw,
      auth_source: auth,
    )
    @tweet = mc['tweet']
    @range = mc['range']
  end

  def update_biggest! user_id, s:, b:
    @range.update_one(
      {_id:user_id},
      {'$set':{biggest:b}, '$setOnInsert':{smallest:s}},
      {upsert:true}
    )
  end

  def update_smallest! user_id, s:, b:
    @range.update_one(
      {_id:user_id},
      {'$set':{smallest:s}, '$setOnInsert':{biggest:b}},
      {upsert:true}
    )
  end

  def biggest user_id
    @range.find(_id:user_id).first&.[](:biggest)&.+(1)
  end

  def smallest user_id
    @range.find(_id:user_id).first&.[](:smallest)&.-(1)
  end

  def get_all user_id
    cnt = 0
    begin
      result = up user_id, count:200
      @log.d result.size
      cnt += result.size
      sleep 1
    end until result.empty?
    begin
      result = down user_id, count:200
      @log.d result.size
      cnt += result.size
      sleep 1
    end until result.empty?
    return cnt
  end

  def up user_id, count:nil
    tweets = @tclient.user_timeline user_id, {
      tweet_mode:      :extended,
      count:           count,
      include_rts:     true,
      exclude_replies: false,
      since_id:        biggest(user_id),
    }.compact
    if tweets.empty?
      [ ]
    else
      update_biggest! user_id, s:tweets.last.id, b:tweets.first.id
      save! tweets.map{ expand_reply _1 }
    end
  end

  def down user_id, count:nil
    tweets = @tclient.user_timeline user_id, {
      tweet_mode:      :extended,
      count:           count,
      include_rts:     true,
      exclude_replies: false,
      max_id:          smallest(user_id),
    }.compact
    if tweets.empty?
      [ ]
    else
      update_smallest! user_id, s:tweets.last.id, b:tweets.first.id
      save! tweets.map{ expand_reply _1 }
    end
  end

  def get tweet_id
    save! expand_reply status tweet_id
  end

  def expand_reply t
    r = unless blank?(t.in_reply_to_tweet_id) or has_tweet(t.in_reply_to_tweet_id)
          status t.in_reply_to_tweet_id
        end
    r ? [expand_reply(r), t].flatten : [t]
  end

  # -> nil or Tweet
  def status id
    blank?(id) ? nil : @tclient.status(id)
  rescue Twitter::Error => e
    @log.e e.message
    nil
  end

  # expect user_timeline [Twitter::Tweet]
  def save! *tweets
    tweets = tweets
      .flatten
      .map{ [_1, _1.retweeted_status, _1.quoted_status] }
      .flatten
      .grep_v Twitter::NullObject
    for t in (tweets).map &:squeeze
      @log.d(
        t[:created_at].getlocal.strftime("%F %a %R"),
        t[:user_name],
        t[:user_id],
        t[:text].inspect,
        t[:_id],
      )
      @tweet.update_one(
        {_id: t[:_id]},
        {
          '$setOnInsert':t.except(:favorite_count, :retweet_count),
          '$set':        t.slice( :favorite_count, :retweet_count),
        },
        {upsert:true}
      )
    end
  end

  def has_tweet id
    @tweet.find(_id:id).count != 0
  end

  def find(...)
    @tweet.find(...)
  end
end

