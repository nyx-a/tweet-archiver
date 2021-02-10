
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
    @trend = mc['trend']
  end

  def update_biggest! user_id, b
    @range.update_one(
      {_id:user_id},
      {'$set':{biggest:b}, '$setOnInsert':{smallest:b}},
      {upsert:true}
    )
  end

  def update_smallest! user_id, s
    @range.update_one(
      {_id:user_id},
      {'$set':{smallest:s}, '$setOnInsert':{biggest:s}},
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
      tweet_mode:  :extended,
      count:       count,
      include_rts: true,
      exclude_replies: false,
      since_id:    biggest(user_id),
    }.compact
    if tweets.empty?
      [ ]
    else
      update_biggest! user_id, tweets.first.id
      save! tweets
    end
  end

  def down user_id, count:nil
    tweets = @tclient.user_timeline user_id, {
      tweet_mode:  :extended,
      count:       count,
      include_rts: true,
      exclude_replies: false,
      max_id:      smallest(user_id),
    }.compact
    if tweets.empty?
      [ ]
    else
      update_smallest! user_id, tweets.last.id
      save! tweets
    end
  end

  # expect user_timeline [Twitter::Tweet]
  def save! *tweets
    tweets = tweets.flatten
    tweets = tweets.map{ [_1, _1.retweeted_status, _1.quoted_status] }
      .flatten
      .grep_v Twitter::NullObject
    for t in (tweets).map &:squeeze
      @log.d(
        t[:created_at].getlocal.strftime("%F %a %R"),
        t[:user_name],
        t[:user_screen_name],
        t[:text].inspect,
      )
      @tweet.update_one(
        {_id: t[:_id]},
        {'$setOnInsert':t},
        {upsert:true}
      )
    end
  end

  def query(...)
    @tweet.find(...)
  end

  def save_trends woeid
    arr = @tclient.trends(woeid).map{ _1.name }
    @log.d arr.inspect
    @trend.insert_one(
      date:   Time.now,
      woeid:  woeid,
      trends: arr,
    )
  end
end

