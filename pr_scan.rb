require_relative 'helper'

class PRScan
  include Helper

  def initialize(installation_client)
    @installation_client = installation_client
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

      URI.open(file_raw_url) {|f|
        line_number = 0
        f.each_line do |line|
          line_number += 1
          fixed_line = replace_block_words(line)
          next if fixed_line == line

          # TODO: update body text
          comments_array += [{
            :path => file_name,
            :line => line_number,
            :body => "test this text\n```suggestion\n#{fixed_line.strip}\n```",
          }]
        end

        options = {
          :body => "overall body",
          :commit_id => sha,
          :event => "REQUEST_CHANGES",
          :comments => comments_array
        }

        @installation_client.post("/repos/#{repo}/pulls/#{pr_number}/reviews", options)
      }
    end
  end
end
