# Each IRCClient represents one connection to a server.
class IRCClient < IRCSocketListener
	attr_reader :nick, :username, :realname
	attr_reader :channels

	def initialize(ircsocket, nick, username, realname)
		@ircsocket = ircsocket
		@nick = nick
		@username = username
		@realname = realname

		@loggedin = false

		@channels = Hash.new
		@join_onlogin = Array.new
		@to_rejoin = Array.new

		@plugins = Hash.new
		@whois = Hash.new

		ircsocket.add_listener(self)
	end

	def connect
		# Connect to the IRC server
		@ircsocket.connect
		@ircsocket.nickname(@nick)
		@ircsocket.login(@username, "localhost", @ircsocket.host, @realname)
	end

	def add_plugin(name)
		if @plugins.include?(name)
			raise "Plugin #{name} already loaded in client"
		end
		Sources::require("plugins/#{name}.rb")
		plugin = Kernel::const_get(name).new
		plugin.client = self
		@plugins[name] = plugin
	end

	def remove_plugin(name)
		if not @plugins.include?(name)
			raise "Plugin #{name} not present in client"
		end
		@plugins.delete(name)
		if @plugins.empty?
			@ircsocket.quit
		end
	end

	def emit(sym, *params)
		@plugins.each do |name, obj|
			obj.send(sym, *params) if obj.respond_to?(sym)
		end
	end

	def say(recipient, message, action = :privmsg)
		# Pretty-print to a channel.
		raise "No recipient" if recipient.nil?
		return nil if message == ""

		case message
		when Array
			message.each do |item|
				say(recipient, item, action)
			end
		when Hash
			message.each do |key, value|
				say(recipient, "#{key} => #{value}", action)
			end
		when String
			message.each_line do |line|
				@ircsocket.send(action, recipient, message)
			end
		else
			say(recipient, message.to_s, action)
		end

		return nil
	end

	def join(name)
		if @channels.include?(name)
			log "Asked to join #{name} but I think I'm already in it."
		elsif not @loggedin
			@join_onlogin << name
		else
			@ircsocket.join(name)
		end
	end

	def part(name)
		if not @channels.include?(name)
			log "Asked to part #{name} but I don't think I'm in it."
		else
			@ircsocket.part(channel)
		end
	end

	def who
		@ircsocket.who
	end

	def whois(name)
		@ircsocket.whois(name)
	end

	def handle_network_idle(seconds)
		if @to_rejoin.size > 0
			@to_rejoin.each do |channel, time|
				join(channel) if Time.now > time
			end
			@to_rejoin.reject! {|channel, time| Time.now > time }
		elsif seconds == 10 and @channels.empty?
			log "Idle for 10 seconds without being in any channels. Leaving server."
			@ircsocket.quit
		end
	end

	def handle_welcome
		@loggedin = true
		@ircsocket.umode(@nick, "+B")
		@join_onlogin.each do |channel|
			join(channel)
		end
		@join_onlogin = nil
	end

	def handle_privmsg(user, target, message)
		private_message = (target == @nick)
		reply_to = private_message ? user.nick : target
		emit(:on_privmsg, user, reply_to, message.to_s)
	end

	def handle_someone_joined(user, channel)
		user.add_presence(channel)
		if user.nick == @nick
			@channels[channel] = Channel.new(channel)
		else
			@channels[channel].users[user.nick] = user
		end
		emit(:on_join, user, channel)
	end

	def handle_someone_parted(user, channel)
		emit(:on_part, user, channel)
		if user.nick == @nick # We are parting
			if not @channels.include?(channel)
				log "Server said I left #{channel} but I didn't think I was in it."
			else
				@to_rejoin << [channel, Time.now + 3] if @channels[channel].rejoin
				@channels[channel].users.each do |nick, user|
					handle_someone_parted(user, channel) if user.nick != @nick
				end
				@channels.delete(channel)
			end
		else # Another user is parting
			user.remove_presence(channel)
			@channels[channel].users.delete(user.nick)
		end
	end

	def handle_someone_changed_nick(user, new)
		# Update user's nickname
		old = user.nick
		user.nick = new

		# Update references to this user
		user.each_presence do |channel_name, _|
			channel = @channels[channel_name]
			channel.users[new] = user
			channel.users.delete(old)
		end
	end

	def handle_someone_kicked(src, channel, target, reason)
		handle_someone_parted(Users[target], channel)
	end

	def handle_invite(user, channel)
		# user has invited us to a channel
		emit(:on_invite, user, channel)
	end

	def handle_names_list(channel, line_of_names)
		ch = @channels[channel]
		names = line_of_names.split(" ")
		names.each do |name|
			sigil = name[0,1]
			sigil = "" if not sigil.match(/[~&@%+]/)
			name = name.sub(/^[~&@%+]/, "")
			user = Users[name]
			user.add_presence_as(channel, sigil)
			ch.new_users[name] = user
		end
	end

	def handle_names_list_end(channel)
		ch = @channels[channel]
		ch.users = ch.new_users
		ch.new_users = Hash.new
	end

	def handle_who(channel, username, host, nick, umode, realname)
		return if channel == "*" # Network services are listed here
		user = Users[nick]
		user.username = username
		user.host = host
		user.add_presence(channel)
		user.registered = true if umode.include?("r")
		emit(:on_who, user)
	end

	def handle_who_end
		# Remove users we think we see, yet that WHO didn't return?
		# Actually, we'll miss invisible users this way.
	end

	def handle_whois_user(nick, username, host, realname)
		@whois[:nick] = nick
		@whois[:username] = username
		@whois[:host] = host
	end

	def handle_whois_registered(nick)
		@whois[:nick] = nick
		@whois[:registered] = true
	end

	def handle_whois_channels(nick, channels_line)
		@whois[:nick] = nick
		channel_words = channels_line.split
		channels = channel_words.map {|word|
			sigil = word[0,1]
			sigil = "" if not sigil.match(/[~&@%+]/)
			name = word.sub(/^[~&@%+]/, "")
			[name, sigil]
		}
		@whois[:channels] = channels
	end

	def handle_whois_end
		nick = @whois[:nick]
		username = @whois[:username]
		host = @whois[:host]
		registered = @whois[:registered]
		channels = @whois[:channels]

		user = Users[nick]
		user.username = username
		user.host = host
		user.registered = registered if registered
		if channels
			channels.each do |name, sigil|
				user.add_presence_as(name, sigil)
			end
		end

		@whois = Hash.new

		emit(:on_whois, user)
	end
end
