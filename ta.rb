
require 'mongo'
require 'twitter'


def blank? o
  o.nil? or o.is_a?(Twitter::NullObject) or (o.respond_to?(:empty?) and o.empty?)
end

def squeeze_tweet t
  {
    _id:                     t.id,
    uri:                     t.uri.to_s,
    user_id:                 t.user.id,
    user_name:               t.user.name,
    user_screen_name:        t.user.screen_name,
    filter_level:            t.filter_level,
    in_reply_to_tweet_id:    t.in_reply_to_tweet_id,
    in_reply_to_user_id:     t.in_reply_to_user_id,
    in_reply_to_screen_name: t.in_reply_to_screen_name,
    lang:                    t.lang,
    source:                  t.source,
    text:                    t.full_text,
    created_at:              t.created_at,
    hashtags:                t.hashtags.map(&:text), # Twitter::Entity::Hashtag
    symbols:                 t.symbols.map(&:text), # Twitter::Entity::Symbol
    media:                   t.media.map{{type:_1.type, id:_1.id}}, # Twitter::Media::***
    user_mentions:           t.user_mentions.map(&:id), # Twitter::Entity::UserMention
    uris:                    t.uris.map{_1.expanded_url.to_s}, # Twitter::Entity::URI
    retweeted_status_id:     t.retweeted_status.id,
    quoted_status_id:        t.quoted_status.id,
    favorite_count:          t.favorite_count,
    retweet_count:           t.retweet_count,
  }.reject{ blank? _2 }
end

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

class TA
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

  def get id, with_replies:true
    begin
      indb = find(_id:id).first
      id = if indb
             @log.d "already have: #{indb[:text].inspect}"
             indb[:in_reply_to_tweet_id]
           else
             tweet = status id
             save tweet
             sleep 1
             tweet&.in_reply_to_tweet_id
           end
    end while with_replies and !blank?(id)
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
      .map{ squeeze_tweet _1 }
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

