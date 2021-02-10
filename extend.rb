
require 'twitter'

def blank? o
  o.nil? or o.is_a?(Twitter::NullObject) or (o.respond_to?(:empty?) and o.empty?)
end

def h2s h
  l = h.keys.map(&:length).max
  h.map{ |k,v|
    "%*s %s" % [l, k, v.to_s.gsub(/(?!\A)^/, ' '*l)]
  }.join("\n")
end

module Twitter
  class Tweet
    def squeeze
      {
        _id:                     self.id,
        uri:                     self.uri.to_s,
        user_id:                 self.user.id,
        user_name:               self.user.name,
        user_screen_name:        self.user.screen_name,
        filter_level:            self.filter_level,
        in_reply_to_tweet_id:    self.in_reply_to_tweet_id,
        in_reply_to_user_id:     self.in_reply_to_user_id,
        in_reply_to_screen_name: self.in_reply_to_screen_name,
        lang:                    self.lang,
        source:                  self.source,
        text:                    self.full_text,
        created_at:              self.created_at,
        hashtags:                self.hashtags.map(&:text), # Twitter::Entity::Hashtag
        symbols:                 self.symbols.map(&:text), # Twitter::Entity::Symbol
        media:                   self.media.map{{type:_1.type, id:_1.id}}, # Twitter::Media::***
        user_mentions:           self.user_mentions.map(&:id), # Twitter::Entity::UserMention
        uris:                    self.uris.map{_1.expanded_url.to_s}, # Twitter::Entity::URI
        retweeted_status_id:     self.retweeted_status.id,
        quoted_status_id:        self.quoted_status.id,
      }.reject{ blank? _2 }
    end
  end
end

