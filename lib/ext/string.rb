class String
	def scrape!(regex)
		# Scrapes off a regex from a string, and returns the captures.
		# If the regex is found inside the string, it is removed.
		if m = match(regex)
			gsub!(regex, "")
			return m.captures
		else
			return nil
		end
	end

	def capitalize_each_word!
		capitalize!
		for i in (1...length)
			self[i] -= 32 if self[i-1] == 32
		end
		return self
	end
end
