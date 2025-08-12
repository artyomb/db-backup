require 'open3'
require 'sequel'

def restore_by_dump(backup_path, database_name, replace_only_tables=false)
  message = nil
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
  # puts "PGPASSFILE updated: #{File.read(ENV['PGPASSFILE'])}"
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

  # Create admin Sequel connection
  if db_port && !db_port.empty?
    db_url = "postgres://#{db_user}:#{db_password}@#{db_host}:#{db_port}/#{db_name}"
    admin_db_url = "postgres://#{db_user}:#{db_password}@#{db_host}:#{db_port}/postgres"
  else
    db_url = "postgres://#{db_user}:#{db_password}@#{db_host}/#{db_name}"
    admin_db_url = "postgres://#{db_user}:#{db_password}@#{db_host}/postgres"
  end
  # Connect to 'postgres' so we can drop the target DB
  puts "Creating sequel connection to #{admin_db_url}"
  sequel_connection = Sequel.connect(admin_db_url)
  puts "Connection created with options #{sequel_connection.opts}"
  begin
    if db_name == default_db_name
      if !replace_only_tables
        # If the database name is the same as the default database name, we will restore the backup into a new database then rename it to the default database name
        puts "You specified the same database as the origin one. Dump will replace original database"
        drop_database_sequel(sequel_connection, db_name + RESTORE_IN_ORIGIN_DB_SUFFIX)
        create_message = create_and_restore_sequel(sequel_connection, db_name + RESTORE_IN_ORIGIN_DB_SUFFIX, db_password, backup_path)
        existing_tables = get_existing_tables(sequel_connection, db_name + RESTORE_IN_ORIGIN_DB_SUFFIX)
        tables_in_backup = extract_tables_by_backup_path(backup_path)
        not_existing_tables = tables_in_backup.select { |t| !existing_tables.include?(t) }
        if not_existing_tables.size > 0
          drop_database_sequel(sequel_connection, db_name + RESTORE_IN_ORIGIN_DB_SUFFIX)
          raise "Couldn't restore database properly: tables (#{not_existing_tables.join(', ')}) were not created.\nCreating database by dump message:\n#{create_message}"
        end
        sequel_connection.transaction do
          rename_db_sequel(sequel_connection, db_name, db_name + OLD_DB_SUFFIX)
          rename_db_sequel(sequel_connection, db_name + RESTORE_IN_ORIGIN_DB_SUFFIX, db_name)
        end
        drop_database_sequel(sequel_connection, db_name + OLD_DB_SUFFIX)
        message = "Creating DB message:\n#{create_message}\nSuccessfully restored dump into #{db_name}"
      else
        puts "Option \"replace_only_tables\" is used for current restore. Original database will be affected after that action"
        replace_tables_in_original_db(db_url, backup_path, db_name)
      end
    else
      drop_database_sequel(sequel_connection, db_name)
      create_message = create_and_restore_sequel(sequel_connection, db_name, db_password, backup_path)
      message = "Creating DB message:\n#{create_message}\nSuccessfully restored dump into #{db_name}"
    end
  rescue => e
    message = "Failed to restore #{db_name}:\n#{e.message}"
    raise message
  ensure
    sequel_connection.disconnect
    message
  end
end

def create_and_restore_sequel(sequel_connection, db_name, db_password, backup_path)
  # Create the database using SQL instead of createdb command
  puts "Creating fresh database #{db_name}..."
  begin
    sequel_connection.run("CREATE DATABASE #{db_name};")
    puts "Database #{db_name} created successfully."
  rescue Sequel::DatabaseError => e
    raise "Database creation failed: #{e.message}"
  end

  # # Connect to the newly created database and install postgis extention
  # new_db_url = sequel_connection.opts[:uri].sub(%r{/[^/]+$}, "/#{db_name}")
  # puts "Connecting to new database #{db_name} to install PostGIS..."
  # begin
  #   new_db_connection = Sequel.connect(new_db_url)
  #   new_db_connection.run("CREATE EXTENSION IF NOT EXISTS postgis;")
  #   puts "PostGIS extension created successfully in #{db_name}."
  # rescue Sequel::DatabaseError => e
  #   raise "Failed to create PostGIS extension: #{e.message}"
  # ensure
  #   new_db_connection.disconnect if new_db_connection
  # end

  # Extract and restore the backup
  begin
    gzip_file_path = backup_path
    sql_file = File.join(File.dirname(backup_path), File.basename(backup_path.split('/').last, '.gz'))

    # Extract .gz file to .sql
    puts "Extracting backup file #{backup_path}..."
    system("gzip -d #{gzip_file_path} -c > #{sql_file}")
    raise "Error extracting SQL file from backup" unless $?.success?

    # Prepare psql restore command
    puts "Restoring database #{db_name} from #{sql_file}..."
    db_opts = sequel_connection.opts
    db_host = db_opts[:host] || 'localhost'
    db_port = db_opts[:port]
    db_user = db_opts[:user]

    restore_cmd = ['psql', '-h', db_host]
    restore_cmd += ['-p', db_port.to_s] if db_port
    restore_cmd += ['-U', db_user, '-d', db_name, '-f', sql_file]
    # Run restore
    env = ENV.to_h.merge('PGPASSWORD' => db_password)
    restore_out, restore_err, restore_status = Open3.capture3(env, *restore_cmd)
    restore_out = restore_out[0, 1000]
    restore_err = restore_err[0, 1000]

    if restore_status.success?
      message = "Database restored successfully." + (restore_err.empty? ? '' : "\nWARN MESSAGE AFTER RESTORE:\n#{restore_err}")
      puts message
      return message
    else
      puts"Restore out:\n#{restore_out}"
      puts "Error restoring database: #{restore_err}"
      raise "Restore failed: #{restore_err}"
    end

  rescue => e
    puts "Exception occurred during restore: #{e.message}"
    raise e

  ensure
    # Clean up temp .sql file
    if sql_file && File.exist?(sql_file)
      puts "Removing temporary SQL file #{sql_file}..."
      system("rm #{sql_file}")
    end
  end
end

def drop_database_sequel(sequel_connection, db_name)
  # Terminate existing sessions
  puts "Terminating active connections to #{db_name}..."
  sequel_connection.run(%Q(
    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE datname = '#{db_name}' AND pid <> pg_backend_pid();
  )) rescue nil

  # Drop the database
  puts "Dropping database #{db_name}..."
  sequel_connection.run("DROP DATABASE IF EXISTS #{db_name};")
end

def rename_db_sequel(sequel_connection, db_name, db_name_new)
  begin
    puts "Locking database #{db_name} against new connections..."
    sequel_connection.run("ALTER DATABASE #{db_name} WITH ALLOW_CONNECTIONS false;")

    puts "Terminating active connections to #{db_name}..."
    sequel_connection.run(%Q(
      SELECT pg_terminate_backend(pid)
      FROM pg_stat_activity
      WHERE datname = '#{db_name}' AND pid <> pg_backend_pid();
    ))

    puts "Renaming database #{db_name} to #{db_name_new}..."
    sequel_connection.run("ALTER DATABASE #{db_name} RENAME TO #{db_name_new};")
    puts "Database #{db_name} successfully renamed to #{db_name_new}"

  rescue => e
    raise "Database renaming failed:\n#{e.message}"
  ensure
    begin
      puts "Re-enabling connections to #{db_name_new}..."
      sequel_connection.run("ALTER DATABASE #{db_name_new} WITH ALLOW_CONNECTIONS true;")
    rescue => e
      raise "Failed to unlock database:\n#{e.message}"
    end
  end
end

def replace_tables_in_original_db(db_url, backup_path, db_name)
  begin
    gzip_file_path = backup_path
    sql_file = File.join(File.dirname(backup_path), File.basename(backup_path, '.gz'))
    new_db_connection = Sequel.connect(db_url)

    # Step 1: Extract .gz file to .sql
    puts "Extracting backup file #{backup_path}..."
    system("gzip -d #{gzip_file_path} -c > #{sql_file}")
    raise "Error extracting SQL file from backup" unless $?.success?

    # Step 2: Extract table names from the SQL dump
    sql_content = File.read(sql_file)
    table_names = extract_table_names_from_sql(sql_content)

    # Step 3: Clear each table using DELETE
    puts "Clearing existing data from #{table_names.size} tables in #{db_name}..."
    new_db_connection.transaction do
      table_names.each do |table|
        puts "Deleting from table #{table}..."
        new_db_connection.run("DELETE FROM #{Sequel.lit(table)}")
      end
    end

    # Step 4: Prepare data-only SQL file from COPY blocks
    data_only_file = "#{sql_file}.dataonly.sql"
    File.open(data_only_file, 'w') do |f|
      f.puts "SET session_replication_role = replica;"  # Disable constraints

      inside_copy = false
      sql_content.each_line do |line|
        if line =~ /^COPY\b/i
          inside_copy = true
          f.puts line
        elsif inside_copy
          f.puts line
          inside_copy = false if line.strip == '\\.'
        end
      end

      f.puts "SET session_replication_role = DEFAULT;"  # Re-enable constraints
    end

    # Step 5: Run the COPY data insert via psql
    db_opts = new_db_connection.opts
    db_host = db_opts[:host] || 'localhost'
    db_port = db_opts[:port]
    db_user = db_opts[:user]
    db_password = db_opts[:password]

    restore_cmd = ['psql', '-h', db_host, '-U', db_user, '-d', db_name]
    restore_cmd += ['-p', db_port.to_s] if db_port

    puts "Restoring data into #{db_name} (with constraints temporarily disabled)..."
    env = { 'PGPASSWORD' => db_password.to_s }
    stdout, stderr, status = Open3.capture3(env, *restore_cmd, stdin_data: File.read(data_only_file))
    unless status.success?
      puts "Restore failed:\nSTDERR: #{stderr[0,1000]}"
      raise "psql restore failed"
    end

    message = "Tables #{table_names.join(', ')} replaced in #{db_name} successfully (constraints were temporarily disabled during restoring)"
    puts message
    message

  rescue => e
    puts "Exception occurred during restore: #{e.message}"
    raise e

  ensure
    # Clean up temp files
    [sql_file, "#{sql_file}.dataonly.sql"].each do |f|
      if f && File.exist?(f)
        puts "Removing temporary file #{f}..."
        File.delete(f)
      end
    end

    new_db_connection.disconnect if new_db_connection
  end
end

# Utility: Extracts table names from CREATE TABLE statements
def extract_table_names_from_sql(sql_content)
  table_names = []
  create_table_regex = /CREATE TABLE\s+(?:\w+\.)?"?(\w+)"?\s*\(/i
  sql_content.scan(create_table_regex) do |match|
    table_names << match[0]
  end
  table_names.uniq
end

def get_existing_tables(sequel_connection, db_name)
  # Build a connection to the target DB using the same connection opts but with db_name replaced
  db_opts = sequel_connection.opts.dup
  db_opts[:database] = db_name

  target_connection = Sequel.connect(db_opts)
  begin
    # Fetch table names from information_schema
    rows = target_connection.fetch("
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public'
        AND table_type = 'BASE TABLE'
      ORDER BY table_name
    ").map { |r| r[:table_name] }

    rows
  ensure
    target_connection.disconnect
  end
end

def extract_tables_by_backup_path(backup_path)
  begin
    gzip_file_path = backup_path
    sql_file = File.join(File.dirname(backup_path), File.basename(backup_path, '.gz'))

    # Step 1: Extract .gz file to .sql
    puts "Extracting backup file #{backup_path}..."
    system("gzip -d #{gzip_file_path} -c > #{sql_file}")
    raise "Error extracting SQL file from backup" unless $?.success?

    # Step 2: Extract table names from the SQL dump
    sql_content = File.read(sql_file)
    table_names = extract_table_names_from_sql(sql_content)
  rescue => e
    puts "Exception occurred during extracting tables from dump: #{e.message}"
    raise e
  ensure
    if sql_file && File.exist?(sql_file)
      puts "Removing temporary file #{sql_file}..."
      File.delete(sql_file)
    end
  end
  table_names
end

