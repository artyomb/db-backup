require 'open3'

def restore_by_dump(backup_path)
  puts "Restoring backup at #{Time.now} by dump #{backup_path}"
  db_host_port     = ENV['RESTORE_TARGET_HOST_PORT']
  raise "Target database host and port are not specified" if db_host_port.nil?
  db_host = db_host_port.split(':').first
  db_port = db_host_port.split(':').last if db_host_port.split(':').size > 1
  db_user     = ENV['RESTORE_TARGET_USER']
  db_password = ENV['RESTORE_TARGET_PASSWORD']
  db_name     = ENV['RESTORE_TARGET_DB_NAME'] || "temporary_db"
  missing_vars = []
  missing_vars << 'RESTORE_TARGET_HOST_PORT' if db_host_port.nil?
  missing_vars << 'RESTORE_TARGET_USER' if db_user.nil?
  missing_vars << 'RESTORE_TARGET_PASSWORD' if db_password.nil?
  missing_vars << 'RESTORE_TARGET_DB_NAME' if db_name.nil?
  exception_message = "Following environment variables are not set: #{missing_vars.join(', ')}" unless missing_vars.empty?
  raise exception_message if exception_message
  pg_path = File.expand_path('~/.pgpass')
  File.write(pg_path, "#{db_host_port}:*:#{db_user}:#{db_password}\n")
  File.chmod(0600, pg_path)
  ENV['PGPASSFILE'] = pg_path
  # usr = system("whoami")

  # check_cmd = ['psql', '-h', db_host_port.split(':').first]
  # check_cmd += ['-p', db_host_port.split(':').last] if db_host_port.split(':').size > 1
  # check_cmd += ['-U', db_user, '-tAc', "SELECT 1 FROM pg_database WHERE datname='#{db_name}'"]
  # exists_output, exists_err, exists_status = Open3.capture3(*check_cmd)
  # puts "Database is already exists" if exists_output.strip == '1'
  # unless exists_output.strip == '1'
  #   puts "Database #{db_name} does not exist, creating..."
  #   create_cmd = ['createdb', '-h', db_host_port.split(':').first]
  #   create_cmd += ['-p', db_host_port.split(':').last] if db_host_port.split(':').size > 1
  #   create_cmd += ['-U', db_user, db_name]
  #   create_output, create_err, create_status = Open3.capture3(*create_cmd)
  #   unless create_status.success?
  #     raise 'Database creation failed'
  #   end
  # end

  # Drop database if it exists
  drop_cmd = ['dropdb', '--force', '--if-exists', '-h', db_host, "--username=#{db_user}", '-e']
  drop_cmd += ['-p', db_port] if db_port
  drop_cmd += [db_name]
  puts "Dropping database #{db_name}..."
  drop_output, drop_err, drop_status = Open3.capture3(*drop_cmd)
  puts "Database #{db_name} dropped" if drop_status.success?

  # Create database again
  puts "Creating fresh database #{db_name}..."
  create_cmd = ['createdb', '-h', db_host, '-U', db_user, db_name]
  create_cmd += ['-p', db_port] if db_port
  create_output, create_err, create_status = Open3.capture3(*create_cmd)
  puts "Database #{db_name} created" if create_status.success?
  unless create_status.success?
    raise "Database creation failed: #{create_err}"
  end

  # Extract SQL file from backup .gz
  begin
    gzip_file_path = File.join(BACKUPS_DIR, backup_path)
    sql_file = File.join(BACKUPS_DIR, File.basename(backup_path, '.gz'))
    system("gzip -d #{gzip_file_path} -c > #{sql_file}")
    unless $?.success?
      raise "Error extracting SQL file from backup"
    end
    # Restore SQL file
    restore_cmd = ['psql', '-h', db_host]
    restore_cmd += ['-p', db_port] if db_port
    restore_cmd += ['-U', db_user, '-d', db_name, '-f', sql_file]
    puts "Restoring database..."
    restore_out, restore_err, restore_status = Open3.capture3(*restore_cmd)

    if restore_status.success?
      message = "Database restored successfully"
      puts message
      return message
    else
      puts "Error restoring database: #{restore_err}"
      raise 'Error restoring database'
    end
  rescue Exception => e
    puts "Error restoring database: #{e.message}"
    raise e
  ensure
    # Remove the SQL file
    puts "Temporary SQL file removed"
    system("rm #{sql_file}")
  end
end
