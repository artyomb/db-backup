#!/usr/bin/env ruby
require 'sinatra'
require 'json'
require 'sinatra/reloader'
require_relative 'utils/common_utils'
require_relative 'utils/backup_invocation_utils'

get '/', &-> { slim :index }
get '/index', &-> { slim :index }
get '/file-in-archive/*' do
  backup_path = params[:splat][0]
  content = extract_sql_by_backup(backup_path)
  # extention = File.extname(backup_path).delete_prefix('.')
  extention = 'sql'
  escaped_content = CGI.escapeHTML(content)
  "<code class='language-#{extention}'>#{escaped_content}</code>"
end

get '/download-dump-archive/*' do
  path_to_file = params[:splat][0]
  send_file(File.join(BACKUPS_DIR, path_to_file))
end

if ENV['DEBUG'] == "true"
  puts "DEBUG MODE"
end
BACKUPS_DIR = ENV['DEBUG'].nil? ? '/backups' : './backups'
puts "All backups will be stored in #{BACKUPS_DIR}"
Thread.new { start_backups }
run Sinatra::Application
