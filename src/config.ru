#!/usr/bin/env ruby
require 'sinatra'
require 'json'
require 'sinatra/reloader'
require_relative 'utils/common_utils'
require_relative 'utils/backup_invocation_utils'
require_relative 'utils/restoring_utils'

$last_backup_report = { status_code: 0, message: '', error_message: '', time: Time.now }
$last_rsync_reports = []
RESTORE_IN_ORIGIN_DB_SUFFIX = "_restore_in_origin_db"
OLD_DB_SUFFIX = "_old"

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

post '/invoke-force-backup' do
  puts "Invoke force backup at #{Time.now}"
  perform_backup_pipeline
  response = [200, { 'Content-Type' => 'application/json' }, { status: "ok", message: "Backup pipeline performed successfully. Refresh page to see details in actual backup report." }.to_json] if $last_backup_report[:status_code] == 0
  response = [500, { 'Content-Type' => 'application/json' }, { status: "error", message: "Backup pipeline failed. Refresh page to see details in actual backup report." }.to_json] if $last_backup_report[:status_code] != 0
  response
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

Thread.new { start_backups }
run Sinatra::Application
# TODO:
# 1. Rework backup policy: if backup for last hour exists, then backup for current hour will be skipped +
# 2, Change ENVIRONMENT variables +
# 3. Handle all errors and display them in UI +
# 4. Add more detailed logging +
# 5. Improve UI elements +