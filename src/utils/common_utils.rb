def represent_size(bytes)
  begin
    # bytes.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')
    units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB']
    return '0 B' if bytes == 0

    exp = (Math.log(bytes) / Math.log(1024)).to_i
    exp = units.size - 1 if exp > units.size - 1
    size = bytes.to_f / (1024 ** exp)

    format('%.2f %s', size, units[exp])
  rescue Exception => e
    puts "Error in size representing: #{e}"
    '-'
  end
end

def calculate_dir_size(dir_path)
  total_size = 0
  Dir.glob("#{dir_path}/**/*").each do |path|
    total_size += File.size(path) unless File.directory?(path)
  end
  total_size
end

def extract_backups_dir_structure(root_path)
  structure = { size: 0 }
  children = Dir.children(root_path)
  children.each do |child|
    path = File.join(root_path, child)
    next if File.directory?(path) || !path.end_with?(".sql.gz")
    name = File.basename(path)
    structure[name] = { is_dir: false, size: File.size(path), path: path }
    structure[:size] += structure[name][:size]
  end
  structure
end

def extract_sql_by_backup(full_backup_path)
  puts "Extracting SQL content from backup: #{full_backup_path}"
  upper_limit = 100000
  stats = []
  begin
    gz_path = full_backup_path
    sql_content = nil

    Zlib::GzipReader.open(gz_path) do |gz|
      sql_content = gz.read
    end
    stats = extract_sql_stats(sql_content)
    puts "SQL content extracted successfully."
    content = sql_content[0..(upper_limit-1)] + "\n#{'*' * 150}\nYour content size is too big: #{sql_content.size} chars. It was reduced to #{upper_limit} characters\n#{'*' * 150}" if sql_content.length > upper_limit
    return [content, stats]
  rescue Exception => e
    puts "Error extracting SQL content: #{e}"
    return nil
  end
end

def extract_sql_stats(sql_content)
  stats = []
  tables = []

  # Step 1: Extract table names from CREATE TABLE statements
  create_table_regex = /CREATE TABLE\s+(?:\w+\.)?"?(\w+)"?\s*\(/i
  sql_content.scan(create_table_regex) do |match|
    tables << match[0]
  end

  # Step 2: For each table, search for COPY statement and count data lines
  tables.each do |table_name|
    copy_regex = /COPY\s+(?:\w+\.)?"?#{Regexp.escape(table_name)}"?\s+\(.*?\)\s+FROM\s+stdin;\s*(.*?)\\\.\s*/m
    match = sql_content.match(copy_regex)
    if match
      data_block = match[1]
      line_count = data_block.lines.reject { |line| line.strip.empty? }.size
      stats << { table_name: table_name, number_of_records: line_count }
    else
      stats << { table_name: table_name, number_of_records: 0 }
    end
  end

  stats
end

def log_service_environment_variables
  puts "Service-specific environment variables:"
  keys_for_logging = [
    "DEBUG",
    "BACKUPS_DIR",
    "BACKUP_INTERVAL",
    "DB_URL",
    "TABLES",
    "BACKUP_TARGET_HOST",
    "BACKUP_TARGET_HOST_PRIVATE_KEY",
    "BACKUP_TARGET_PATH",
    "RESTORE_TARGET_HOST_PORT",
    "RESTORE_TARGET_USER",
    "RESTORE_TARGET_PASSWORD",
    "RESTORE_TARGET_DB_NAME"
  ]
  ENV.each do |key, value|
    if keys_for_logging.include?(key)
      if key != "BACKUP_TARGET_HOST_PRIVATE_KEY"
        puts "#{key}: #{value}"
      else
        puts "#{key}: #{'*' * ENV["BACKUP_TARGET_HOST_PRIVATE_KEY"].size}" unless ENV["BACKUP_TARGET_HOST_PRIVATE_KEY"].nil?
        puts "#{key}: #{value}" if ENV["BACKUP_TARGET_HOST_PRIVATE_KEY"].nil?
      end
    end
  end
end



def determine_backup_time(filename)
  date_time_string = filename.split('_')[-2..-1].join('').split('.').first
  year, month, day, hour, minute, second = date_time_string[0..3], date_time_string[4..5], date_time_string[6..7], date_time_string[8..9], date_time_string[10..11], date_time_string[12..13]
  Time.new(year, month, day, hour, minute, second, "+00:00")
end

def render_stats_and_content(content, stats, backup_name)
  # extention = File.extname(backup_path).delete_prefix('.')
  extention = 'sql'
  escaped_content = CGI.escapeHTML(content)

  html = '<div style="display: flex;flex-direction: column">'

  html += '<table class="stats-table">'
  html += '<thead>'
  html += '<tr style="background-color: #efef97">'
  html += "<td style=\"text-align: center\" colspan=\"2\">Backup #{backup_name} stats</td>"
  html += '</tr>'

  html += '<tr>'
  html += '<td>Table name</td>'
  html += "<td style=\"text-align: right\">Number of records</td>"
  html += '</tr>'
  html += '</thead>'
  html += '<tbody>'
  stats.each do |stat|
    html += "<tr><td>#{stat[:table_name]}</td><td style=\"text-align: right\">#{stat[:number_of_records]}</td></tr>"
  end
  html += '</tbody>'
  html += '</table>'

  html +="<code class='language-#{extention}'>#{escaped_content}</code>"
  html += '</div>'
  html
end