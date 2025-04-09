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

def extract_backups_dir_structure
  root_path = BACKUPS_DIR
  structure = {}
  Dir.glob("#{root_path}/*").each do |path|
    if !File.directory?(path)
      structure[File.basename(path)] = { is_dir: false, size: File.size(path) }
      next
    end
    name = File.basename(path)
    structure[name] = { is_dir: true, size: calculate_dir_size(path) }

    Dir.glob("#{path}/**/*").each do |file_path|
      relative_path = file_path.sub("#{path}/", '')
      parts = relative_path.split('/')
      current = structure[name]

      parts.each_with_index do |part, index|
        if index == parts.size - 1
          if File.directory?(file_path)
            current[part] = { is_dir: true, size: calculate_dir_size(file_path) }
          else
            current[part] = { size: File.size(file_path) }
          end
        else
          current[part] ||= { is_dir: true, size: 0 }
          current = current[part]
        end
      end
    end
  end
  structure[:size] = calculate_dir_size(root_path)
  structure
end

def extract_sql_by_backup(backup_path)
  puts "Extracting SQL content from backup: #{backup_path}"
  begin
    gz_path = File.join(BACKUPS_DIR, backup_path)
    sql_content = nil

    Zlib::GzipReader.open(gz_path) do |gz|
      sql_content = gz.read
    end
    puts "SQL content extracted successfully."
    return sql_content
  rescue Exception => e
    puts "Error extracting SQL content: #{e}"
    return nil
  end
end