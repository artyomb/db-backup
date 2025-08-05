#!/usr/bin/env ruby
ENV['PERFORMANCE'] = 'true' unless ENV['DEBUG'] == "true"
require 'sinatra'
require 'json'
require 'zip'
require 'sinatra/reloader'
require 'stack-service-base'
require_relative 'utils/common_utils'
require_relative 'utils/backup_invocation_utils'
require_relative 'utils/restoring_utils'
require_relative 'utils/archive_utils'

$last_backup_report = { status_code: 0, message: '', error_message: '', time: Time.now }
$last_rsync_reports = []
RESTORE_IN_ORIGIN_DB_SUFFIX = "_temp"
OLD_DB_SUFFIX = "_old"

BACKUPS_DIR = ENV['DEBUG'].nil? ? '/backups' : File.join(Dir.pwd, './backups')
UPLOADED_BACKUPS_DIR = ENV['DEBUG'].nil? ? '/uploaded_backups' : File.join(Dir.pwd, './uploaded_backups')
puts "All backups will be stored in #{BACKUPS_DIR}"

get '/', &-> { slim :index }
get '/index', &-> { slim :index }
get '/file-in-archive/*' do
  backup_path = params[:splat][0]
  backup_path = '/' + backup_path if backup_path[0] != '/'
  content, stats = extract_sql_by_backup(backup_path)
  render_stats_and_content(content, stats, backup_path.split('/').last)
end

get '/dumps/*' do
  path_to_file = params[:splat][0]
  path_to_file = '/' + path_to_file if path_to_file[0] != '/'
  send_file(path_to_file)
end

delete '/dumps/*' do
  path_to_file = params[:splat][0]
  path_to_file = '/' + path_to_file if path_to_file[0] != '/'
  return [400, { message: "Only backup .sql.gz are available for deleting"}.to_json] unless path_to_file.end_with?('.sql.gz')
  FileUtils.rm_f(path_to_file)
  return [200, {message: "Backup file #{path_to_file} successfully deleted"}.to_json ]
end

post '/dumps' do
  params do
    requires :file, desc: '.zip, .rar, .gz or .sql file with SQL dump', type: File, documentation: { param_type: 'body' }
  end
  incoming_file = nil
  proc_file = nil
  status = 200
  basic_success_message = "You file successfully loaded"
  json_out = { message: basic_success_message }
  begin
    filename = params[:file][:filename]
    incoming_file = params[:file][:tempfile]
    proc_file = nil
    if (!(filename.end_with?('.sql')) && !(filename.end_with?('.zip')) && !(filename.end_with?('.rar')) && !(filename.end_with?('.gz')))
      json_out[:message] = "Unsupported file type: #{filename}"
      status = 400
      raise json_out[:message]
    end
    if filename.end_with?('.zip')
      entries = []
      Zip::File.open(incoming_file) do |zip_file|
        zip_file.each do |entry|
          entries << entry
        end
      end
      if entries.size != 1
        json_out[:message] = "Zip archive must contain exactly one file"
        status = 400
        raise json_out[:message]
      end
      if !(entries[0].name.end_with?('.sql'))
        json_out = { message: "File in archive must be .sql file" }.to_json
        status = 400
        raise json_out[:message]
      end
      # TODO: replace tempfile with actual .sql file
      temp_file = Tempfile.new(['extracted', '.sql'])
      puts 'Created temp file for extraction from zip'
      entries.each do |zip_file|
        zip_file.extract(temp_file.path) { true }
      end
      proc_file = temp_file
    elsif filename.end_with?('.rar')
      proc_file = extract_sql_from_rar(incoming_file)
    elsif filename.end_with?('.gz')
      proc_file = extract_sql_from_gz(incoming_file)
    else
      temp_file = Tempfile.new(['uploaded', '.sql'])
      temp_file.write(incoming_file.read)
      temp_file.rewind
      proc_file = temp_file
    end

    archive_into_gz(proc_file, "#{UPLOADED_BACKUPS_DIR}/#{filename.split('.').first}.sql.gz")

    # TODO: implement continue processing
  rescue => e
    json_out[:message] = e.message if json_out[:message] == basic_success_message
    status = 500 if status == 200
  ensure
    incoming_file&.close!
    proc_file&.close!
    puts "Temp file closed"
  end
  return [status, json_out.to_json]
end

post '/invoke-force-backup' do
  puts "Invoke force backup at #{Time.now}"
  perform_backup_pipeline
  response = [200, { 'Content-Type' => 'application/json' }, { status: "ok", message: "Backup pipeline performed successfully. Refresh page to see details in actual backup report." }.to_json] if $last_backup_report[:status_code] == 0
  response = [500, { 'Content-Type' => 'application/json' }, { status: "error", message: "Backup pipeline failed. Refresh page to see details in actual backup report." }.to_json] if $last_backup_report[:status_code] != 0
  response
end

post '/restore-by-dump/*' do
  begin
    path_to_file = params[:splat][0]
    path_to_file = '/' + path_to_file if path_to_file[0] != '/'
    request_body = JSON.parse(request.body.read)
    database_name = request_body["database_name"]
    replace_only_tables = request_body["replace_only_tables"]
    message = restore_by_dump(path_to_file, database_name, replace_only_tables)

    body = { status: "ok", message: message }
    [200, { 'Content-Type' => 'application/json' }, body.to_json]
  rescue Exception => e
    puts "Error during restore: #{e}"
    body = { status: "error", message: "Error during restore:\n#{e}" }
    [500, { 'Content-Type' => 'application/json' }, body.to_json]
  end
end


if ENV['DEBUG'] == "true"
  puts "DEBUG MODE"
  ENV['BACKUP_TARGET_HOST_PRIVATE_KEY'] = nil
  backup_name = "arinc_20250415_201035.sql.gz"
  # restore_by_dump(backup_name)
end

Thread.new { start_backups }
StackServiceBase.rack_setup self if self.respond_to? :use
run Sinatra::Application