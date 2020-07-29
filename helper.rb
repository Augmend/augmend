module Helper

  REPLACEMENT_WORDS = {
    'whitelist' => 'enable_list',
    'blacklist' => 'block_list',
    'master' => 'main',
    'slave' =>'secondary'
  }

  REGEX = {
    'whitelist' => "(white[-|_]*list)",
    'blacklist' => "(black[-|_]*list)",
    'master' => "(master)",
    'slave' => "(secondary)",
  }

  def replace_block_words(original_line)
    fixed_line = original_line
    # get all blocked words
    REPLACEMENT_WORDS.keys.each do |word|
      # if it contains the normalized block word
      if contains_block_word(original_line, word)
        # find array of words to replace
        block_words = get_all_block_words(original_line, word)
        block_words.each do |block_word|
          replacement = match_casing(block_word)
          fixed_line = fixed_line.gsub(block_word, replacement)
        end
      end
    end
    fixed_line
  end

  def contains_block_word(line, word)
    line = line.gsub(/_|-/, "")
    return line.downcase.include?(word)
  end

  def get_all_block_words(line, word)
    matches = Regexp.new(REGEX[word], "i").match(line)
    return matches.captures unless matches.nil?
    return []
  end

  def get_variable_names_with_block_words(line)
    tokenized = line.split(/\b/)
    terms_with_block_words = []
    tokenized.each do |token|
      REGEX.values.each do |regex_key|
        match = Regexp.new(regex_key, "i").match(token)
        terms_with_block_words.push(token) unless match.nil?
      end
    end
    return terms_with_block_words
  end

  def match_casing(original_word)
    # all lowercase, no special chars
    if !original_word.include?("-") && !original_word.include?("_") && is_downcase?(original_word)
      replacement = REPLACEMENT_WORDS[original_word]
      replacement = replacement.gsub(/_/, "")
      return replacement.downcase
      # all uppercase, no special chars
    elsif !original_word.include?("-") && !original_word.include?("_") && is_uppercase?(original_word)
      normalized = original_word.downcase
      replacement = REPLACEMENT_WORDS[normalized]
      replacement = replacement.gsub(/_/, "")
      return replacement.upcase
      # snake case
    elsif is_snakecase?(original_word)
      normalized = original_word.gsub(/_/, "")
      if is_downcase?(normalized)
        return REPLACEMENT_WORDS[normalized].downcase
      elsif is_uppercase?(normalized)
        return REPLACEMENT_WORDS[normalized].upcase
      end
      # hyphenated words
    elsif is_hyphenated?(original_word)
      normalized = original_word.gsub(/-/, "")
      if is_downcase?(normalized)
        replacement = REPLACEMENT_WORDS[normalized].downcase
      elsif is_uppercase?(normalized)
        replacement = REPLACEMENT_WORDS[normalized].upcase
      end
      return replacement.dasherize()
      # camel case
    else
      normalized = original_word.downcase
      replacement = REPLACEMENT_WORDS[normalized]
      if is_downcase?(original_word[0])
        replacement = replacement.split('_').collect(&:capitalize).join
        replacement[0] = replacement[0].downcase
        return replacement
      else
        return replacement.split('_').collect(&:capitalize).join
      end
    end
  end

  def is_hyphenated?(word)
    word.include?("-")
  end

  def is_snakecase?(word)
    word.include?("_")
  end

  def is_downcase?(word)
    word == word.downcase
  end

  def is_uppercase?(word)
    word == word.upcase
  end
end
