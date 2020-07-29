require_relative 'helper'

class PRScan
  include Helper

  def initialize(installation_client)
    @installation_client = installation_client
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

  def handle_new_pull_request(payload)
    repo = payload['repository']['full_name']
    pr_number = payload['pull_request']['number']
    sha = payload['pull_request']['head']['sha']

    to_update = {}
    changed_files = @installation_client.pull_request_files(repo, pr_number)
    changed_files.each do |item|
      file_raw_url = item.raw_url
      file_name = item.filename # path
      comments_array = []

      # create a variable occurence map to keep track of multiple usages of the same block word
      variable_occurences_map = {}
      URI.open(file_raw_url) {|f|
        line_number = 0
        f.each_line do |line|
          line_number += 1

          fixed_line = replace_block_words(line)
          next if fixed_line == line

          variable_names = get_variable_names_with_block_words(line)
          variable_names.each do |var_name|
            occurences = variable_occurences_map[var_name]
            if occurences.nil?
              occurences = []
            end

            occurences.push({
              :line_number => line_number,
              :fixed_line => fixed_line
            })
            variable_occurences_map[var_name] = occurences
          end
        end
      }

      # depending on the number of occurences of the variable, add a regular or an interactive comment to the PR
      variable_occurences_map.keys.each do |var_name|
        occurences = variable_occurences_map[var_name]
        if occurences.length() > 2
          first_occurence = occurences[0]
          body_text = "Augmend bot discovered multiple usages of this term. Reply `Yes` to this comment if you'd like us to make the changes everywhere else."
          comments_array += [{
            :path => file_name,
            :line => first_occurence[:line_number],
            :body => "#{body_text}\n```suggestion\n#{first_occurence[:fixed_line].strip}\n```",
          }]
        else
           body_text = "Augmend bot recommends the following changes:"
           occurences.each do |occurence|
            comments_array += [{
              :path => file_name,
              :line => occurence[:line_number],
              :body => "#{body_text}\n```suggestion\n#{occurence[:fixed_line].strip}\n```",
            }]
           end
        end
      end

      options = {
        :body => "Augmend bot scan results: \n",
        :commit_id => sha,
        :event => "REQUEST_CHANGES",
        :comments => comments_array
      }
      @installation_client.post("/repos/#{repo}/pulls/#{pr_number}/reviews", options)
    end
  end
end
