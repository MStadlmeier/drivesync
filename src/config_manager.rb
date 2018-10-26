class ConfigManager
  require 'fileutils'
  require 'yaml'

  CONFIG_PATH = File.expand_path('~/.drivesync/config.yml')
  CONFIG_PATH_OLD = File.expand_path("..", File.dirname(__FILE__)) + "/config.yml"
  DEFAULT_CONFIG_PATH = File.dirname(__FILE__) + '/defaultconfig'
  CONFIG_VERSION = 1.3

  attr_accessor :config

  def initialize
    #Make sure new .drivesync folder exists
    FileUtils.mkdir_p(File.expand_path('~/.drivesync/'))

    #Check that config file exists in (new) folder
    if File.file? CONFIG_PATH_OLD and !File.file? CONFIG_PATH
      FileUtils.cp CONFIG_PATH_OLD, CONFIG_PATH
      puts "UPGRADE NOTICE: The location of the config file has been moved to #{CONFIG_PATH}. Your previous config has been moved there"
      FileUtils.rm CONFIG_PATH_OLD
    elsif !File.file? CONFIG_PATH
      Log.log_message "Warning: Could not find config file at #{CONFIG_PATH} . Creating default config..."
      write_default
    end

    @config = YAML.load_file CONFIG_PATH
    migrate if config['config_version'].nil? or CONFIG_VERSION > config['config_version']
    prepare_config
  end

  private

  #Restores the default config and saves it as config.yml
  def write_default
    if File.file? DEFAULT_CONFIG_PATH
      FileUtils.cp DEFAULT_CONFIG_PATH, CONFIG_PATH
      return true
    end
    Log.log_error "Could not find default config file at #{CONFIG_DEFAULT_PATH}"
    return false
  end

  def migrate
    old_version = config['config_version'].nil? ? 0 : config['config_version']
    added_lines = []
    removed_lines = []
    blacklist_contents = ''
    blacklist_contents = @config['ignored_files'].map{|ig| "\"" + ig + "\""}.join(',') unless @config['ignored_files'].nil?
    if @config['inclusion'].nil?
      added_lines << "#Determines which files will be synced.\n#blacklist => Every file except those included in 'ignored_files' below will be syced (default)\n#whitelist => Only files included in 'whitelist' will be synced\ninclusion: blacklist\n"
    end
    if @config['whitelist'].nil?
      added_lines << "#White and blacklist contain file paths relative to Drive root. Which will (whitelist) / won't (blacklist) be synced.\n#Globs [https://en.wikipedia.org/wiki/Glob_(programming)] are allowed\n#Examples: blacklist: [\"foo.bar\",\"secret_*.txt\",\"hidden/docs/*\"] / whitelist: [\"sync/*\", \"logs.tar.gz\"]\n\nblacklist: [#{blacklist_contents}]\nwhitelist: []\n"
    end
    removed_lines << 'config_version:'
    if @config['ignored_files'] != nil
      removed_lines << '#Add a list of comma separated file paths (relative to drive root) that should not be synced'
      removed_lines << '#Example: ignored_files:'
      removed_lines << 'ignored_files:'
    end

    if @config['sync_shared_in_drive'].nil?
      added_lines << "#If true, files that have been shared with you will be synced as well, as long as you added them to your Drive\n#Default: false\nsync_shared_in_drive: false"
    end

    if @config['follow_symlinks'].nil?
      added_lines << "#If true, symlinks inside your local drive folder will be followed\n#Default: false\nfollow_symlinks: false\n"
    end

    added_lines << "config_version: #{CONFIG_VERSION}"

    config_lines = File.read(CONFIG_PATH).split("\n")

    File.open(CONFIG_PATH, 'w') do |file|
      config_lines.each {|cl| file.puts cl unless removed_lines.any?{|rl| cl.start_with?(rl)} }
      file.puts "\n"
      added_lines.each {|al| file.puts "#{al}\n"}
    end
    @config = YAML.load_file CONFIG_PATH

    puts "Your config file has been updated from version #{old_version} to #{@config['config_version']}. Your settings have been preserved. Check out the new options here: #{CONFIG_PATH}"
  end

  def prepare_config
    @config['drive_path'] = File.expand_path @config['drive_path']
    @config['client_secret_path'] =  File.expand_path("..", File.dirname(__FILE__)) + '/client_secret.json'
  end
end