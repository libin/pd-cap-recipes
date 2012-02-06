require 'git'
require 'grit'

# Bump up grit limits since git.fetch can take a lot
Grit::Git.git_timeout = 600 # seconds
Grit::Git.git_max_size = 104857600 # 100 megs

Capistrano::Configuration.instance(:must_exist).load do |config|

  after  'deploy:symlink', 'git:update_tag_for_stage'

  namespace :git do

    task :cut_tag do
      repo = Grit::Repo.new('.')

      git = Grit::Git.new(File.join('.', '.git'))
      raise "You are currently in a detached head state. Cannot cut tag." if !repo.head

      git.fetch

      new_tag = "#{repo.head.name}-#{Time.now.utc.to_i}"
      git.tag({}, new_tag)
      git.push(:tags => true)

      Capistrano::CLI.ui.say "Your new tag is \e[1m\e[32m#{new_tag}\e[0m" 
      Capistrano::CLI.ui.say "You can deploy the tag by running:\n  bundle exec cap #{stage} deploy -s tag=#{new_tag}" 
    end

    set :branch do
      return config[:_git_branch] if config[:_git_branch]

      tag = config[:tag]
      if !config[:tag]
        tag = Capistrano::CLI.ui.ask "\e[1m\e[32mTag to deploy: \e[0m"
        tag = tag.to_s.strip
      end

      config[:_git_branch] = tag
      git_sanity_check(tag)

      config[:_git_branch]
    end

    task :update_tag_for_stage do
      git = Grit::Git.new(File.join('.', '.git'))

      # Clear previous pointer if exists. Ignore errors here.
      git.tag(:d => config[:stage])
      git.push({}, 'origin', ":refs/tags/#{config[:stage]}")

      # Set new pointer to current HEAD.
      git.tag({}, config[:stage])
      git.push(:tags => true)
    end
  end
end

def git_sanity_check(tag)
  repo = Grit::Repo.new('.')
  git  = Grit::Git.new(File.join('.', '.git'))

  if repo.tags.select {|t| t.name == tag }.size == 0
    raise "Invalid tag name: #{tag}" 
  end

  tag_sha = repo.commit(tag).id
  deploy_sha = repo.head.commit.id

  if tag_sha != deploy_sha
    raise "Cannot deploy tag #{tag}. Does not match head SHA of #{deploy_sha}." + \
        " Please checkout the tag with: `git checkout #{tag}` and deploy again."
  end

  # See this article for info on how this works:
  # http://stackoverflow.com/questions/3005392/git-how-can-i-tell-if-one-commit-is-a-descendant-of-another-commit
  if ENV['REVERSE_DEPLOY_OK'].nil?
    if git.merge_base({}, deploy_sha, current_revision).chomp != git.rev_parse({ :verify => true }, current_revision).chomp
      raise "You are trying to deploy #{deploy_sha}, which does not contain #{current_revision}," + \
          " the commit currently running.  Operation aborted for your safety." + \
          " Set REVERSE_DEPLOY_OK to override."
    end
  end
end