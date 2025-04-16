#!/usr/bin/env ruby
require 'sinatra'
require 'json'
require 'sinatra/reloader'
require_relative 'utils/common_utils'
require_relative 'utils/backup_invocation_utils'
require_relative 'utils/restoring_utils'

BACKUPS_DIR = ENV['DEBUG'].nil? ? '/backups' : './backups'
puts "All backups will be stored in #{BACKUPS_DIR}"

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

post '/restore-by-dump/:backup_name' do
  begin
    database_name = JSON.parse(request.body.read)["database_name"]
    message = restore_by_dump(params[:backup_name], database_name)

    body = { status: "ok", message: message }
    [200, { 'Content-Type' => 'application/json' }, body.to_json]
  rescue Exception => e
    puts "Error during restore: #{e}"
    body = { status: "error", message: "Error during restore:\n#{e}" }
    [500, { 'Content-Type' => 'application/json' }, body.to_json]
  end
end

# post '/test-restore-by-dump/:backup_name' do
#   puts "Test restoring backup at #{Time.now} by dump #{params[:backup_name]}"
  # restore_by_dump(params[:backup_name])
  # body = { status: "ok", message: "Restore performed successfully" }
  # [200, { 'Content-Type' => 'application/json' }, body.to_json]
  # Simulating error response
  # body = { status: "error", message: "Error during restore" }
  # [500, { 'Content-Type' => 'application/json' }, body.to_json]
# end

log_service_environment_variables
if ENV['DEBUG'] == "true"
  puts "DEBUG MODE"
  ENV['BACKUP_TARGET_HOST_PRIVATE_KEY'] = nil
  backup_name = "arinc_20250415_201035.sql.gz"
  # restore_by_dump(backup_name)
end

# Thread.new { start_backups }
run Sinatra::Application
