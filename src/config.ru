#!/usr/bin/env ruby
require 'sinatra'
require 'json'
require 'sinatra/reloader'
require_relative 'utils/common_utils'

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
if ENV['DEBUG'] == "true"
  puts "DEBUG MODE"
end
BACKUPS_DIR = ENV['DEBUG'].nil? ? '/backups' : './backups'
Thread.new { system("/bin/bash #{Dir.pwd}/backup#{ENV['DEBUG'].nil? ? '' : '_debug'}.sh") }
run Sinatra::Application
