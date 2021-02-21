
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

  def get_all user_id, count:nil
    cnt = 0
    begin
      result = up user_id, count:count
      @log.d result.size
      cnt += result.size
      sleep 2
    end until result.empty?
    begin
      result = down user_id, count:count
      @log.d result.size
      cnt += result.size
      sleep 2
    end until result.empty?
    return cnt
  end

  def reply_ids tweets
    tweets.map(&:in_reply_to_tweet_id).reject{ blank? _1 or has? _1 }
  end

  def up user_id, count:nil, with_replies:false
    tweets = begin
               @tclient.user_timeline user_id, {
                 tweet_mode:      'extended',
                 count:           count,
                 include_rts:     true,
                 exclude_replies: false,
                 since_id:        biggest(user_id),
               }.compact
             rescue Twitter::Error => e
               @log.e user_id, e.message
               [ ]
             end
    if tweets.empty?
      [ ]
    else
      update_biggest! user_id, s:tweets.last.id, b:tweets.first.id
      result = save tweets
      if with_replies
        until (rids = reply_ids tweets).empty?
          tweets = save rids.map{ sleep 1 ; status _1 }
        end
      end
      result
    end
  end

  def down user_id, count:nil
    tweets = @tclient.user_timeline user_id, {
      tweet_mode:      'extended',
      count:           count,
      include_rts:     true,
      exclude_replies: false,
      max_id:          smallest(user_id),
    }.compact
    if tweets.empty?
      [ ]
    else
      update_smallest! user_id, s:tweets.last.id, b:tweets.first.id
      save tweets
    end
  end

  def get id, with_replies:false
    begin
      tweet = status id
      save tweet
      id = if with_replies
             sleep 1
             tweet&.in_reply_to_tweet_id
           end
    end until blank?(id) or has?(id)
  end

  # -> nil or Tweet
  def status id
    blank?(id) ? nil : @tclient.status(id, {tweet_mode:'extended'})
  rescue Twitter::Error => e
    @log.e id, e.message
    nil
  end

  # expect [Twitter::Tweet]
  def save *tweets
    fltn = tweets.flatten.reject{ blank? _1 }
    fltn
      .map{ [_1, _1.retweeted_status, _1.quoted_status] }
      .flatten
      .grep_v(Twitter::NullObject)
      .map(&:squeeze)
      .each do |t|
        @log.d(
          t[:created_at].getlocal.strftime("%F %a %R"),
          t[:user_name],
          t[:user_id],
          t[:text].inspect,
          t[:_id],
        )
        @tweet.update_one(
          {_id: t[:_id]},
          t,
          {upsert:true}
        )
      end
    return fltn
  end

  def has? id
    not @tweet.find({_id:id},{limit:1}).none?
  end

  def find(...)
    @tweet.find(...)
  end

  def known_users
    @range.find({},{projection:{_id:1}}).map{ _1[:_id] }
  end

  def find_tweet id
    arr = [ ]
    while id
      twt = @tweet.find(_id:id).first
      arr.unshift twt
      id = twt[:in_reply_to_tweet_id]
    end
    return arr
  end
end

