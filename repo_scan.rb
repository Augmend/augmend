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
    @base_branch = find_default_branch(repository)
    @new_branch = "augmend-bot-scan#{Time.now.strftime("%Y-%m-%d-%H-%M-%S")}"
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
    contents = if content.nil?
                 puts "Processing repository..."
                 contents = @installation_client.contents(@repository)
               else
                 contents = @installation_client.contents(@repository, :path => content.path)
               end
    contents.each do |content|
      if content.type === 'file'
        result = process_file(@installation_client, @repository, @new_branch, content, nil)
        @repo_updated ||= result
      elsif content.type === 'dir'
        process(content)
      end
    end
  end

  def find_default_branch(repository_name)
    repo = @installation_client.repository(repository_name)
    repo.default_branch
  end

  def create_branch
    puts @base_branch
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
