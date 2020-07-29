require 'sinatra'
require 'octokit'
require 'dotenv/load' # Manages environment variables
require 'json'
require 'openssl'     # Verifies the webhook signature
require 'jwt'         # Authenticates a GitHub App
require 'time'        # Gets ISO 8601 representation of a Time object
require 'logger'      # Logs debug statements
require 'open-uri'
require_relative 'helper'

class CodeScan
  include Helper

  def initialize(installation_client, repository)
    @installation_client = installation_client
    @repository = repository
    @base_branch = 'main'
    @new_branch = 'augmend-bot-scan'
    @repo_updated = false
  end

  # start() - main method called by the server
  #   1. creates a dummy branch to check-in any code changes
  #   2. scan the all the files in the repo iteratively & update the branch with code changes (if any)
  #   3. if the code changes have been made, create a pull request or delete the created dummy branch
  def start
    create_branch
    process(nil)
    if @repo_updated
      create_pull_request
    else
      delete_branch
    end
  end

  def process(content)
    contents = nil
    if content == nil
      contents = @installation_client.contents(@repository)
    else
      contents = @installation_client.contents(@repository, :path => content.path)
    end
    contents.each do |content|
      if content.type === 'file'
        puts "Processing file #{content.name}"
        @repo_updated = process_file(@installation_client, @repository, @new_branch, content, nil)
      elsif content.type === 'dir'
        puts "Processing directory #{content.name}"
        process(content)
      end
    end
  end

  def create_branch
    base_branch = @installation_client.refs(@repository, "heads/#{@base_branch}")
    sha = base_branch.object.sha

    puts "Creating a branch.."
    @installation_client.create_ref(@repository, "heads/#{@new_branch}", sha)
  end

  def delete_branch
    puts "Deleting the branch.."
    @installation_client.delete_branch(@repository, @new_branch)
  end

  def create_pull_request
    puts "Creating a pull request"
    @installation_client.create_pull_request(
      @repository,
      @base_branch,
      @new_branch,
      "[Augmend Bot] Suggested File Replacements",
      "Augmend bot replaced racially insensitive words in the repository")
  end
end
