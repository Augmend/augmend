require 'sinatra'
require 'octokit'
require 'dotenv/load' # Manages environment variables
require 'json'
require 'openssl'     # Verifies the webhook signature
require 'jwt'         # Authenticates a GitHub App
require 'time'        # Gets ISO 8601 representation of a Time object
require 'logger'      # Logs debug statements
require 'open-uri'

class CodeScan
    REPLACEMENT_WORDS = {
        'whitelist' => 'enablelist',
        'blacklist' => 'blocklist',
        'master' => 'primary',
        'slave' =>'secondary'
    }

    def initialize(installation_client, repository)
        @installation_client = installation_client
        @repository = repository
    end

    def start
        create_branch
        contents = @installation_client.contents(@repository)
        contents.each do |content|
            if content.type === 'file'
                puts "Processing file #{content.name}"
                process_file(content)
            elsif content.type === 'dir'
                puts "Processing directory #{content.name}"
                process_directories(content)
            end
        end
    end

    def process_file(content)
        URI.open(content.download_url) {|f|
          line_number = 0
          lines = []
          f.each_line do |line|
            line_number += 1
            fixed_line = line
            REPLACEMENT_WORDS.keys.each do |word|
              if fixed_line.downcase.include?(word)
                fixed_line = fixed_line.gsub(word, REPLACEMENT_WORDS[word])
              end
            end
            lines.push(fixed_line)
          end

          @installation_client.update_contents(
              @repository,
              content.path,
              "Updating content",
              content.sha,
              lines.join(),
              :branch => "augmend-repo-scan")
        }
    end

    def process_directories(content)
    end

    def create_branch
        master = @installation_client.refs(@repository, "heads/master")
        base_branch_sha = master.object.sha
        
        puts "Creating a branch.."
        @installation_client.create_ref(@repository, "heads/augmend-repo-scan", base_branch_sha)
    end

    def delete_branch
        puts "Deleting the branch.."
    end
end