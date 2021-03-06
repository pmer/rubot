# requires Ruby 1.9, won't work on 1.8
if RUBY_VERSION < "1.9"
	abort "The Search plugin requires Ruby 1.9"
end

require 'json'
require 'open-uri'
require 'uri'

require 'rubygems'
require 'andand'
require 'nokogiri'

class Search < RubotPlugin
	@@actions = [
		[/:search\s*(.+)/i, :search1],
		[/^(w+(h+)?[ao]+t+|w+(h+)?o+|w+[dt]+[fh]+)(\s+(t+h+e+|i+n+|o+n+)\s+(.+?))?((\'+?)?s+|\s+i+s+|\s+a+r+e+)\s+(a+(n+)?\s+)?(.+?)(\/|\\|\.|\?|!|$)/i, :search11],
		[/^(t+e+l+l+)\s+(m+e+|u+s+|e+v+e+r+y+o+n+e+|h+i+m+|h+e+r+|t+h+e+m+)\s+(w+(h+)?a+t+|w+h+o+|(a+)?b+o+u+t+)\s+(i+s+|a+(n+)?|a+r+e+|)+(.+?)(\s+i+s+|\s+a+r+e+|\/|\\|\.|\?|!|$)/i, :search8],
		[/^jamer(\S*)?(:|,)?\s+(hi|hey|hello|sup|yo)/i, :say_hi],
		[/^(hi|hey|hello|sup|yo)(.+?)?\s+jamer/i, :say_hi],
	]

	def initialize
		super
		@cache = Hash.new
		@cooldown = IRCCooldown.new(self, 5, "You're searching too fast. Wait %d more second%s.")
	end

	def on_privmsg(user, source, msg)
		mkay(source) if msg.match(/#{@client.nick}/i) or msg.match(/jamerbot/)
		msg.gsub!(/^\s*#{@client.nick}:?\s+/, "")
		RegexJump::jump(@@actions, self, msg, [user.nick, source])
	end

	def search1(nick, source, term)
		search(nick, source, term) if @cooldown.trigger_err(source)
	end

	def search8(nick, source, *unused, term, x)
		search(nick, source, term) if @cooldown.trigger
	end

	def search11(nick, source, *unused, term, x)
		search(nick, source, term) if @cooldown.trigger
	end

	def search(nick, source, term)
		@cache[term] = lookup(term) if not @cache.include?(term)
		answer = @cache[term]
		say(source, answer)
	end

	def escape(term)
		term.gsub!('+', "%2B") # Handle pluses in input
		term.gsub!(' ', '+')
		query = URI::escape(term)
		query.gsub!("%252B", "%2B") # Unescape pluses
		return query
	end

	def lookup(term)
		query = escape(term)
		x = [
			proc {|query| custom(term) },
			proc {|query| ddg(query) },
			proc {|query| urban(query) },
			proc {|query| "I don't know." },
		].map_first {|p| p.call(query) }
		return x
	end

	def custom(term)
		return {
			"awesome" => "You're awesome."
		}[term]
	end

	def ddg(query)
		response = open("http://api.duckduckgo.com/?q=#{query}&o=json")
		lines = response.readlines
		return nil if lines.grep(/doctype/i).size > 0
		json = JSON::parse(lines.join('\n'))
		output = [
				json["Answer"],
				json["AbstractText"],
				json["RelatedTopics"].andand.at(0).andand["Text"],
		].find {|x| x && x.length > 0 }
		if output
			return nil if output.include?("Safe search")
			return output.gsub(/<.*?>/, ""). # strip HTML
				gsub("&nbsp;", ' ')
		else
			return nil
		end
	end

	def urban(query)
		html = open("http://www.urbandictionary.com/tooltip.php?term=#{query}")
		doc = Nokogiri::HTML(html)
		if doc.content.include?("isn't defined yet")
			return nil
		else
			definition = doc.xpath("//div[2]")[0].content
			first_line = definition.split(/[\r\n]+/)[1] # [0] is a blank line
			return first_line
		end
	end

	def say_hi(nick, source, *unused)
		say(source, "Hey #{nick}.")
	end

	def mkay(source)
		say(source, "Mkay.") if rand % 10 == 0
	end
end

