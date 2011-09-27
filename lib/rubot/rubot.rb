# Rubot
# A simple, pluggable IRC bot framework.

require 'yaml'

class Rubot
	def initialize(configs)
		@sockets = []

		abort "no config files specified on command line" if configs.empty?
		configs.each do |file|
			spawn_client(file)
		end
	end

	def spawn_client(file)
		yaml = YAML::load_file(file)

		address = yaml["address"]
		port = yaml["port"]

		nick = yaml["nick"]
		username = yaml["username"]
		realname = yaml["realname"]

		channels = yaml["channels"]
		plugins = yaml["plugins"]

		abort "No channels found in config" if channels.nil?
		abort "No plugins found in config" if plugins.nil?

		socket = IRCSocket.new(address, port)
		client = IRCClient.new(socket, nick, username, realname)
		client.connect
		channels.each {|channel| client.join("##{channel}") }
		plugins.each {|plugin| client.add_plugin(plugin) }
		@sockets << socket
	end

	def main_loop
		# If we get an exception, then print it out and keep going
		# We do NOT want to disconnect unexpectedly!
		begin
			handle_input
		rescue Interrupt
			interrupt_sockets
		rescue SystemExit
		rescue Exception => detail
			puts "Exception caught - #{detail.class}(\"#{detail.message}\")"
			puts detail.backtrace.join("\n")
			puts
			retry
		end
	end

	# Read and handle all open sockets until they all disconnect.
	def handle_input
		while @sockets.size > 0 and sleep(1)
			@sockets.each do |socket|
				socket.readline while (socket.connected? and socket.peek)
			end
			@sockets = @sockets.find_all {|socket| socket.connected? }
		end
		log "No connections left, quitting."
	end

	def interrupt_sockets
		@sockets.each do |socket|
			socket.quit_msg("Interrupted") if socket.connected?
		end
	end
end

