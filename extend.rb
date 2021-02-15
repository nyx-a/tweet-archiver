
require 'twitter'

def blank? o
  o.nil? or o.is_a?(Twitter::NullObject) or (o.respond_to?(:empty?) and o.empty?)
end

module Twitter
  class Tweet
    def squeeze
      {
        _id:                     id,
        uri:                     uri.to_s,
        user_id:                 user.id,
        user_name:               user.name,
        user_screen_name:        user.screen_name,
        filter_level:            filter_level,
        in_reply_to_tweet_id:    in_reply_to_tweet_id,
        in_reply_to_user_id:     in_reply_to_user_id,
        in_reply_to_screen_name: in_reply_to_screen_name,
        lang:                    lang,
        source:                  source,
        text:                    full_text,
        created_at:              created_at,
        hashtags:                hashtags.map(&:text), # Twitter::Entity::Hashtag
        symbols:                 symbols.map(&:text), # Twitter::Entity::Symbol
        media:                   media.map{{type:_1.type, id:_1.id}}, # Twitter::Media::***
        user_mentions:           user_mentions.map(&:id), # Twitter::Entity::UserMention
        uris:                    uris.map{_1.expanded_url.to_s}, # Twitter::Entity::URI
        retweeted_status_id:     retweeted_status.id,
        quoted_status_id:        quoted_status.id,
        favorite_count:          favorite_count,
        retweet_count:           retweet_count,
      }.reject{ blank? _2 }
    end
  end
end

