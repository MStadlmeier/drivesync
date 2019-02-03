class Helper
  def self.file_ignored? path, config
    if config['inclusion'] == 'whitelist'
      config['whitelist'].each do |entry|
        return false if File.fnmatch entry, path
      end
      return true
    else
      config['blacklist'].each do |entry|
        return true if File.fnmatch entry, path
      end
      return false
    end
  end

  #Returns true if the path looks ok to delete(not empty, root or home directory)
  def self.safe_path? path
    return false if path.nil?
    path = path.strip
    return false if path == ''
    return false if path == '/'
    return false if path == Dir.home
    return false if path == Dir.home + '/'
    true
  end

  #Dir.glob replacement with follow_symlinks support
  def self.dir_glob pattern, follow_symlinks = false, flags = 0
    files = Array.new

    Dir.glob(pattern).each do |file|
      files.push(file)

      if follow_symlinks && File.symlink?(file) && File.directory?(file)
        files.push(dir_glob(File.join(file, '**', '*'), follow_symlinks, flags))
      end
    end

    return files.flatten
  end
end