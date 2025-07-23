require 'open3'
require 'sequel'

def restore_by_dump(backup_path, database_name)
  puts "Restoring backup at #{Time.now} by dump #{backup_path}"
  default_db_url = ENV['DB_URL'] # postgres://settlements:settlements@settlements_settlements_db/settlements?sslmode=disable
  default_user_password = default_db_url.split('@').first.split('//').last
  default_db_user = default_user_password.split(':').first
  default_db_password = default_user_password.split(':').last
  default_db_name = default_db_url.split('?').first.split('/').last
  default_db_host_port = default_db_url.split('@').last.split('/').first
  db_host_port     = ENV['RESTORE_TARGET_HOST_PORT']
  db_host_port ||= default_db_host_port
  raise "Target database host and port are not specified" if db_host_port.nil?
  db_host = db_host_port.split(':').first
  db_port = db_host_port.split(':').last if db_host_port.split(':').size > 1
  db_user     = ENV['RESTORE_TARGET_USER']
  db_user     ||= default_db_user
  db_password = ENV['RESTORE_TARGET_PASSWORD']
  db_password ||= default_db_password
  db_name     = database_name || default_db_name
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

  if db_name == default_db_name
    # If the database name is the same as the default database name, we will restore the backup into a new database then rename it to the default database name
    puts "You specified the same database as the origin one. This dump will re-create the database and restore the backup into it"
    puts "Creating new database #{db_name + RESTORE_IN_ORIGIN_DB_SUFFIX} and restoring backup into it"
    drop_database(db_host, db_port, db_user, db_name + RESTORE_IN_ORIGIN_DB_SUFFIX)
    create_and_restore(db_host, db_port, db_user, db_name + RESTORE_IN_ORIGIN_DB_SUFFIX, backup_path)
    drop_database(db_host, db_port, db_user, db_name)
    rename_db(db_host_port, db_user, db_name + RESTORE_IN_ORIGIN_DB_SUFFIX, db_name)
  else
    # Drop database if it exists
    drop_database(db_host, db_port, db_user, db_name)
    create_and_restore(db_host, db_port, db_user, db_name, backup_path) if db_name != default_db_name
  end
end

def create_and_restore(db_host, db_port, db_user, db_name, backup_path)
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


def drop_database(db_host, db_port, db_user, db_name)
  drop_cmd = ['dropdb', '--force', '--if-exists', '-h', db_host, "--username=#{db_user}", '-e']
  drop_cmd += ['-p', db_port] if db_port
  drop_cmd += [db_name]
  puts "Dropping database #{db_name}..."
  drop_output, drop_err, drop_status = Open3.capture3(*drop_cmd)
  puts "Database #{db_name} dropped" if drop_status.success?
end

def rename_db(db_host_port, db_user, db_name, db_name_new)
  puts "Renaming database #{db_name} to #{db_name_new}"

  host, port = db_host_port.split(':')
  port ||= '5432'

  # Connect to the 'postgres' DB to manage the target DB
  db = Sequel.connect(
    adapter: 'postgres',
    host: host,
    port: port,
    user: db_user,
    database: 'postgres'
  # password: 'your_password' # optionally add authentication
  )

  begin
    db.transaction do
      puts "Locking database #{db_name} against new connections..."
      db.run("ALTER DATABASE #{db_name} WITH ALLOW_CONNECTIONS false;")

      puts "Terminating active connections to #{db_name}..."
      db.run(%Q(
        SELECT pg_terminate_backend(pid)
        FROM pg_stat_activity
        WHERE datname = '#{db_name}' AND pid <> pg_backend_pid();
      ))

      puts "Renaming database #{db_name} to #{db_name_new}..."
      db.run("ALTER DATABASE #{db_name} RENAME TO #{db_name_new};")
    end

    puts "Database #{db_name} successfully renamed to #{db_name_new}"

  rescue => e
    raise "Database renaming failed:\n#{e.message}"
  ensure
    begin
      puts "Re-enabling connections to #{db_name_new}..."
      db.run("ALTER DATABASE #{db_name_new} WITH ALLOW_CONNECTIONS true;")
    rescue => e
      raise "Failed to unlock database:\n#{e.message}"
    ensure
      db.disconnect
    end
  end
end