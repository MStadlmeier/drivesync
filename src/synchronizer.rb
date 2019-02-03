require 'google/apis/drive_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'json'
require 'yaml'
require 'fileutils'
require 'io/console'

require_relative './drive_manager'
require_relative './file'
require_relative './local_manager'
require_relative './time'
require_relative './helper'

include Log

class Synchronizer
  APPLICATION_NAME = 'DriveSync'
  USER_NAME=ENV['USER']
  LOCK_PATH = "/tmp/#{USER_NAME}-drivesync.lock"
  MANIFEST_PATH = File.expand_path "~/.drivesync/manifest"
  MANIFEST_PATH_OLD = File.expand_path "~/.drivesync_manifest"

  def initialize
    if check_lock
      Log.log_message "Exiting."
      exit 1
    end
    begin
      write_lock
    rescue
      Log.log_error "Could not write lock file!"
       exit 1
    end

    config_manager = ConfigManager.new
    @config = config_manager.config
    @drive = DriveManager.new APPLICATION_NAME, @config
    @local = LocalManager.new @config

    #If local Drive path doesn't exist even though there has been a previous sync (manifest exists), drive has likely moved locally and a forced sync might delete entire remote Drive
    if !File.exist?(@config['drive_path']) and (File.exist?(MANIFEST_PATH) or File.exist?(MANIFEST_PATH_OLD))
      Log.log_error("Could not find your local drive folder at #{@config['drive_path']} although there has been a previous sync. Please make sure that the drive path specified in the config file (found at #{ConfigManager::CONFIG_PATH}) is correct.\n\nHow do you want to procede (cancel/reset/force)?\n'cancel' - Stop the sync, giving you a chance to check your configuration and drive folder\n'reset' - Starts a fresh sync with the new local drive folder\n'force' - Forces the sync to proceede. WARNING: This will delete any previously synced files on your Google Drive because they will be considered locally deleted (unless remote deletion isn't enabled in your config).")
      answer = STDIN.gets.chomp
      case answer.strip.downcase
      when 'reset'
        puts "Deleting manifest and performing fresh sync..."
        FileUtils.rm MANIFEST_PATH if File.exist?(MANIFEST_PATH)
        FileUtils.rm MANIFEST_PATH_OLD if File.exist?(MANIFEST_PATH_OLD)
      when 'force'
        puts "WARNING: Forcing sync with empty local Drive folder #{@config['drive_path']}"
      when 'cancel'
        puts 'Cancelling sync'
        delete_lock
        exit 1
      else
        puts 'Invalid input. Cancelling sync'
        delete_lock
        exit 1
      end
    end
  end

  def run
    begin
      get_files
      Log.log_message "Local folder is #{@diff.remote_ahead.count} files behind and #{@diff.local_ahead.count} files ahead of remote"
      load_manifest

      Log.log_message "Starting sync at #{Time.now}"
      sync
    rescue SystemExit, Interrupt
      Log.log_message "Interrupted by system. Exiting gracefully..."
    ensure
      Log.log_notice "Deleting lock file..."
      File.delete LOCK_PATH rescue nil
    end
  end

  def get_files
      FileUtils.mkdir_p @config['drive_path']
      Log.log_notice "Getting local files..."
      @local.get_files
      Log.log_notice "Getting remote files..."
      @drive.get_files
      Log.log_notice 'Calculating diff...'
      @diff = get_diff
  end

  def print_diff
    begin
      get_files
      Log.log_message "Local folder is #{@diff.remote_ahead.count} files behind and #{@diff.local_ahead.count} files ahead of remote"
      puts "Local Ahead:"
      @diff.local_ahead.each do |f| puts "#{f}" end
      puts ""
      puts "Remote Ahead:"
      @diff.remote_ahead.each do |f| puts "#{f.path}" end
    ensure
      Log.log_notice "Deleting lock file..."
      delete_lock
    end
  end

  def reset
    puts "Resetting DriveSync will delete... \nLocal Drive folder: #{@config['drive_path']}"
    puts "Manifest file: #{MANIFEST_PATH}"
    puts "Google Drive Authorization: #{@drive.credentials_path}"
    puts "Proceed? (y/n)"
    input = STDIN.getch
    unless input.downcase == 'y'
      puts "Cancelled"
      delete_lock
      return
    end

    paths = [@config['drive_path'], MANIFEST_PATH, MANIFEST_PATH_OLD, @drive.credentials_path]
    paths.each do |path|
      begin
        FileUtils.rm_r path if Helper::safe_path? path
      rescue Errno::ENOENT
      end
    end
    puts "Reset complete"
    delete_lock
  end

  private def get_diff
    diff = FileDiff.new
    @drive.files.each do |file|
      if @local.find_by_path file.path
        diff.both << file
      else
        diff.remote_ahead << file
      end
    end

    @local.files.each do |file|
      diff.local_ahead << file unless @drive.find_by_path file
    end

    diff
  end

  def download_file file, drive, update = false
    Log.log_message "#{update ? 'Updating' : 'Downloading'} file #{file.path} ..."
    #Make folder if it doesn't exist yet
    path = file.path.sub(file.path.split('/')[-1], '')
    FileUtils.mkdir_p File.join(@config['drive_path'], path)

    drive.download file, File.join(@config['drive_path'], file.path)
  end

  def delete_local_file path
    Log.log_message "Deleting file #{path} locally..."
    FileUtils.rm(File.join @config['drive_path'], path)
  end

  def delete_remote_file file, drive
    Log.log_message "Deleting file #{file.path} remotely"
    drive.trash_file file
  end

  def upload_file path, drive
    Log.log_message "Uploading file #{path} ..."
    drive.upload @config['drive_path'], path
  end

  def update_remote_file file, drive
    Log.log_message "Updating remote file #{file.path} ..."
    drive.update @config['drive_path'], file
  end

  def resolve_conflict file, drive, latest_local, latest_remote
    Log.log_message "Resolving conflict for #{file.path}"
    strategy = @config['update_conflict_strategy'].to_sym
    case strategy
    when :ignore
      return
    when :keep_local
      update_remote_file file, drive
    when :keep_remote
      download_file file, drive, true
    when :keep_latest
      if latest_local.is_after? latest_remote
        update_remote_file file, drive
      else
        download_file file, drive, true
      end
    else
      Log.log_error "Unrecognized update conflict strategy : #{strategy}"
    end
  end

  def add_to_manifest path, file
    Log.log_notice "Adding file #{path} to manifest"

    @manifest[path] = {}
    @manifest[path]["remote_modified"] = file.modified_time.nil? ? file.created_time : file.modified_time.to_s
    @manifest[path]["local_modified"] = File.mtime(File.join(@config['drive_path'], path)).to_datetime.to_s
    write_manifest MANIFEST_PATH
  end

  def remove_from_manifest path
    Log.log_notice "Removing file #{path} from manifest"
    @manifest[path] = nil
    write_manifest MANIFEST_PATH
  end

	def load_manifest
	  if !File.file? MANIFEST_PATH
      if File.file? MANIFEST_PATH_OLD
        FileUtils.cp MANIFEST_PATH_OLD, MANIFEST_PATH
        FileUtils.rm MANIFEST_PATH_OLD
        @manifest = JSON.parse(File.read MANIFEST_PATH)
      else
  	    Log.log_notice 'Manifest not found. Creating...'
  	    File.open(MANIFEST_PATH, 'w') do |file|
  	     file.puts '{}'
        end
  	    @manifest = {}
      end
    else
	    @manifest = JSON.parse(File.read MANIFEST_PATH)
    end

    #Remove ignored files from manifest
    @manifest.keys.each do |path|
      @manifest.delete path if Helper.file_ignored? path, @config
    end
	end

	def write_manifest path
	  File.open path, "w" do |f|
	    f.write @manifest.to_json
	  end
	end

	def sync
    #Check for updated remote or local files
    @diff.both.each do |file|
      latest_local = File.mtime(File.join(@config['drive_path'], file.path)).to_datetime
      latest_remote = file.modified_time

      #For whatever reason, file is found locally but wasn't written to manifest
      if @manifest[file.path].nil?
        Log.log_notice "#{file.path} was found on local Drive but not in manifest"
        add_to_manifest file.path, file
      end

      stored_local = DateTime.parse @manifest[file.path]["local_modified"]
      stored_remote = DateTime.parse @manifest[file.path]["remote_modified"]

      #File has been modified remotely and locally. Resolve conflict according to selected strategy
      if latest_local.is_after? stored_local and latest_remote.is_after? stored_remote
        resolve_conflict file, @drive, latest_local, latest_remote
        add_to_manifest file.path, file
      elsif latest_local.is_after? stored_local
        update_remote_file file, @drive
        add_to_manifest file.path, file
      elsif latest_remote.is_after? stored_remote
        download_file file, @drive, true
        add_to_manifest file.path, file
      end
    end

	  @diff.remote_ahead.each do |file|
      #New file on drive => Download
	    if @manifest[file.path].nil?
        download_file file, @drive
        add_to_manifest file.path, file
      #File has been deleted locally => Delete remotely or do nothing
      elsif @config['allow_remote_deletion']
        delete_remote_file file, @drive
        remove_from_manifest file.path
      end
    end

    @diff.local_ahead.each do |path|
      #New local file => Upload
      if @manifest[path].nil?
        drive_file = upload_file path, @drive
        add_to_manifest path, drive_file
      #File has been deleted on drive => delete locally
      else
        delete_local_file path
        remove_from_manifest path
      end
    end

    Log.log_message "\nSync complete."
	end

  #Returns true if there is currently a sync going on
  def check_lock
    if File.file? LOCK_PATH
      pid = File.read LOCK_PATH
      #Check if process actually exists or if lock was left accidentally
      begin
        Process.kill(0, pid.to_i)
        Log.log_message "There is already a sync in progress! - PID : #{pid}"
        return true
      rescue Errno::ESRCH => e
        delete_lock
        return false

      end
    else
      false
    end
  end

  def write_lock
    Log.log_notice "Writing lock file #{LOCK_PATH} ..."
    File.open(LOCK_PATH, 'w') {|file| file.write Process.pid}
  end

  def delete_lock
    File.delete LOCK_PATH rescue nil
  end

  def load_config path
    return unless File.file? path

    @config = YAML.load_file path
    #Allow use of tilde
    @config['drive_path'] = File.expand_path @config['drive_path']
    @config['client_secret_path'] =  File.expand_path("..", File.dirname(__FILE__)) + '/client_secret.json'
  end
end
