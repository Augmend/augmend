require 'sinatra'
require 'octokit'
require 'dotenv/load' # Manages environment variables
require 'json'
require 'openssl'     # Verifies the webhook signature
require 'jwt'         # Authenticates a GitHub App
require 'time'        # Gets ISO 8601 representation of a Time object
require 'logger'      # Logs debug statements
require 'open-uri'

require_relative "repo_scan"

set :port, 3000
set :bind, '0.0.0.0'


# This is template code to create a GitHub App server.
# You can read more about GitHub Apps here: # https://developer.github.com/apps/
#
# On its own, this app does absolutely nothing, except that it can be installed.
# It's up to you to add functionality!
# You can check out one example in advanced_server.rb.
#
# This code is a Sinatra app, for two reasons:
#   1. Because the app will require a landing page for installation.
#   2. To easily handle webhook events.
#
# Of course, not all apps need to receive and process events!
# Feel free to rip out the event handling code if you don't need it.
#
# Have fun!
#

class GHAapp < Sinatra::Application

  # Expects that the private key in PEM format. Converts the newlines
  PRIVATE_KEY = OpenSSL::PKey::RSA.new(ENV['GITHUB_PRIVATE_KEY'].gsub('\n', "\n"))

  # Your registered app must have a secret set. The secret is used to verify
  # that webhooks are sent by GitHub.
  WEBHOOK_SECRET = ENV['GITHUB_WEBHOOK_SECRET']

  # The GitHub App's identifier (type integer) set when registering an app.
  APP_IDENTIFIER = ENV['GITHUB_APP_IDENTIFIER']

  REPLACEMENT_WORDS = {
    'whitelist' => 'enablelist',
    'blacklist' => 'blocklist',
    'master' => 'primary',
    'slave' =>'secondary'
  }

  # Turn on Sinatra's verbose logging during development
  configure :development do
    set :logging, Logger::DEBUG
  end


  # Before each request to the `/event_handler` route
  before '/event_handler' do
    get_payload_request(request)
    verify_webhook_signature
    authenticate_app
    # Authenticate the app installation in order to run API operations
    authenticate_installation(@payload)
  end


  post '/event_handler' do
    # listen for open pull requests
    case request.env['HTTP_X_GITHUB_EVENT']
    # when 'pull_request'
    #   if !(["locked", "closed"].include? @payload['action'])
    #     handle_new_pull_request(@payload)
    #   end
    when 'installation'
      if @payload['action'] === 'created'
        @payload['repositories'].each do |repository|
          scanObj = CodeScan.new(@installation_client, repository['full_name'])
          scanObj.start
        end
      end
    end

    # 
    # # # # # # # # # # # #
    # ADD YOUR CODE HERE  #
    # # # # # # # # # # # #

    200 # success status
  end


  helpers do

    # # # # # # # # # # # # # # # # #
    # ADD YOUR HELPER METHODS HERE  #
    # # # # # # # # # # # # # # # # #
    def handle_new_pull_request(payload)
      logger.debug 'A PR was opened!'

      repo = payload['repository']['full_name']
      pr_number = payload['pull_request']['number']
      sha = payload['pull_request']['head']['sha']

      to_update = {}
      changed_files = @installation_client.pull_request_files(repo, pr_number)
      changed_files.each do |item|
        file_raw_url = item.raw_url
        file_name = item.filename # path
        comments_array = []

        # puts item.to_yaml_properties()

        URI.open(file_raw_url) {|f|
          line_number = 0
          f.each_line do |line|
            line_number += 1
            REPLACEMENT_WORDS.keys.each do |word|
              if line.downcase.include?(word)
                # contents[line_number + 1] = line
                body = "revisit this line to fix culturally insensitive language #{line_number}"

                # @installation_client.add_comment("Augmend/test-repo", 3, "testing this")

                # @installation_client.create_pull_request_comment(
                #   repo,
                #   pr_number,
                #   body,
                #   sha,
                #   file_name,
                #   line_number,
                # )

                fixed_line = line.gsub(word, REPLACEMENT_WORDS[word])
                puts fixed_line

                comments_array += [{
                  :path => file_name,
                  :line => line_number,
                  :body => "test this text\n```suggestion\n#{fixed_line}```",
                }]
              end
            end
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

    # Saves the raw payload and converts the payload to JSON format
    def get_payload_request(request)
      # request.body is an IO or StringIO object
      # Rewind in case someone already read it
      request.body.rewind
      # The raw text of the body is required for webhook signature verification
      @payload_raw = request.body.read
      begin
        @payload = JSON.parse @payload_raw
      rescue => e
        fail  "Invalid JSON (#{e}): #{@payload_raw}"
      end
    end

    # Instantiate an Octokit client authenticated as a GitHub App.
    # GitHub App authentication requires that you construct a
    # JWT (https://jwt.io/introduction/) signed with the app's private key,
    # so GitHub can be sure that it came from the app an not altererd by
    # a malicious third party.
    def authenticate_app
      payload = {
          # The time that this JWT was issued, _i.e._ now.
          iat: Time.now.to_i,

          # JWT expiration time (10 minute maximum)
          exp: Time.now.to_i + (10 * 60),

          # Your GitHub App's identifier number
          iss: APP_IDENTIFIER
      }

      # Cryptographically sign the JWT.
      jwt = JWT.encode(payload, PRIVATE_KEY, 'RS256')

      # Create the Octokit client, using the JWT as the auth token.
      @app_client ||= Octokit::Client.new(bearer_token: jwt)
    end

    # Instantiate an Octokit client, authenticated as an installation of a
    # GitHub App, to run API operations.
    def authenticate_installation(payload)
      @installation_id = payload['installation']['id']
      @installation_token = @app_client.create_app_installation_access_token(@installation_id)[:token]
      @installation_client = Octokit::Client.new(bearer_token: @installation_token)
    end

    # Check X-Hub-Signature to confirm that this webhook was generated by
    # GitHub, and not a malicious third party.
    #
    # GitHub uses the WEBHOOK_SECRET, registered to the GitHub App, to
    # create the hash signature sent in the `X-HUB-Signature` header of each
    # webhook. This code computes the expected hash signature and compares it to
    # the signature sent in the `X-HUB-Signature` header. If they don't match,
    # this request is an attack, and you should reject it. GitHub uses the HMAC
    # hexdigest to compute the signature. The `X-HUB-Signature` looks something
    # like this: "sha1=123456".
    # See https://developer.github.com/webhooks/securing/ for details.
    def verify_webhook_signature
      their_signature_header = request.env['HTTP_X_HUB_SIGNATURE'] || 'sha1='
      method, their_digest = their_signature_header.split('=')
      our_digest = OpenSSL::HMAC.hexdigest(method, WEBHOOK_SECRET, @payload_raw)
      halt 401 unless their_digest == our_digest

      # The X-GITHUB-EVENT header provides the name of the event.
      # The action value indicates the which action triggered the event.
      logger.debug "---- received event #{request.env['HTTP_X_GITHUB_EVENT']}"
      logger.debug "----    action #{@payload['action']}" unless @payload['action'].nil?
    end

  end

  # Finally some logic to let us run this server directly from the command line,
  # or with Rack. Don't worry too much about this code. But, for the curious:
  # $0 is the executed file
  # __FILE__ is the current file
  # If they are the same—that is, we are running this file directly, call the
  # Sinatra run method
  run! if __FILE__ == $0
end
