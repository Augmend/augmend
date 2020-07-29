require_relative 'helper'

class PRCommit
  include Helper

  def initialize(installation_client)
    @installation_client = installation_client
  end

  def handle_new_reply(payload)
    return unless payload['comment']['body'] == 'Yes'
    repo = payload['repository']['full_name']
    commit_id = payload['comment']['in_reply_to_id']
    branch = payload['pull_request']['head']['ref']
    file_path = payload['comment']['path']

    parent_comment = @installation_client.pull_request_comment(repo, commit_id)
    return unless parent_comment.user.login == "augmend[bot]"

    file_content_payload = @installation_client.contents(repo, :path => file_path, :ref => branch)

    variable_name = get_variable_names_with_block_words(parent_comment.diff_hunk).first
    process_file(@installation_client, repo, branch, file_content_payload, variable_name)
  end
end
