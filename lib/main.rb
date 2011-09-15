#!/usr/bin/env ruby

require "./lib/sources.rb"

source_dirs = [
	"./lib/",
	"./lib/ext/",
	"./lib/irc/",
]


# Load all our source files.
source_dirs.each do |dir| 
	files = Dir.glob("#{dir}/*.rb").reject {|f| f == __FILE__ }
	Sources.require_all(files)
end

#set_trace_func proc { |event, file, line, id, binding, classname|
#	printf "%8s %s:%-2d %10s %8s\n", event, file, line, id, classname
#}

# Start the program.
bot = Rubot.new(ARGV)
bot.main_loop
