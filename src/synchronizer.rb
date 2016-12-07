require 'google/apis/drive_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'json'
require 'yaml'

require 'fileutils'
require './src/drive_manager'
require './src/file'
require './src/local_manager'
require './src/time'

include Log

APPLICATION_NAME = 'DriveSync'
LOCK_PATH = "/tmp/drivesync.lock"
CONFIG_PATH = "config.yml"

class Synchronizer

	def get_diff drive, local
	  diff = FileDiff.new
	  drive.files.each do |file|
      if local.find_by_path file.path
        diff.both << file
      else
	     diff.remote_ahead << file
     end
	  end

	  local.files.each do |file|
	    diff.local_ahead << file unless drive.find_by_path file
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
    @manifest[path]["remote_modified"] = file.modified_time.nil? ? file.created_time : file.modified_time
    @manifest[path]["local_modified"] = File.mtime(File.join(@config['drive_path'], path)).to_datetime
    write_manifest @config['manifest_path'] if @config['immediate_rewrite']
  end

  def remove_from_manifest path
    Log.log_notice "Removing file #{path} from manifest"
    @manifest[path] = nil
    write_manifest @config['manifest_path'] if @config['immediate_rewrite']
  end

	def load_manifest path
	  if !File.file? path
	    Log.log_notice 'Manifest not found. Creating...'
	    File.open(path, 'w') do |file|
	     file.puts '{}'
      end
	    @manifest = {}
    else
	    @manifest = JSON.parse(File.read path)
    end
	end

	def write_manifest path
	  File.open path, "w" do |f|
	    f.write @manifest.to_json
	  end
	end

	def sync diff, drive, local
    #Check for updated remote or local files
    diff.both.each do |file|
      latest_local = File.mtime(File.join(@config['drive_path'], file.path)).to_datetime
      latest_remote = file.modified_time
      stored_local = DateTime.parse @manifest[file.path]["local_modified"]
      stored_remote = DateTime.parse @manifest[file.path]["remote_modified"]

      #File has been modified remotely and locally. Resolve conflict according to selected strategy
      if latest_local.is_after? stored_local and latest_remote.is_after? stored_remote
        resolve_conflict file, drive, latest_local, latest_remote
        add_to_manifest file.path, file
      elsif latest_local.is_after? stored_local
        update_remote_file file, drive
        add_to_manifest file.path, file
      elsif latest_remote.is_after? stored_remote
        download_file file, drive, true
        add_to_manifest file.path, file
      end
    end

	  diff.remote_ahead.each do |file|
      #New file on drive => Download
	    if @manifest[file.path].nil?
        download_file file, drive
        add_to_manifest file.path, file
      #File has been deleted locally => Delete remotely or do nothing
      elsif @config['allow_remote_deletion']
        delete_remote_file file, drive
        remove_from_manifest file.path
      end
    end

    diff.local_ahead.each do |path|
      #New local file => Upload
      if @manifest[path].nil?
        drive_file = upload_file path, drive
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
      Log.log_message "There is already a sync in progress! - PID : #{pid}"
      true
    else
      false
    end
  end

  def write_lock
    Log.log_notice "Writing lock file #{LOCK_PATH} ..."
    File.open(LOCK_PATH, 'w') {|file| file.write Process.pid}
  end

  def load_config path
    return unless File.file? path

    @config = YAML.load_file path
    #Allow use of tilde
    @config['drive_path'] = File.expand_path @config['drive_path']
    @config['manifest_path'] = File.expand_path @config['manifest_path']
    @config['client_secret_path'] = File.expand_path @config['client_secret_path']
  end

	def run
    if check_lock
      Log.log_message "Exiting."
      return
    end

    begin
      write_lock
    rescue
      Log.log_error "Could not write lock file!"
      return
    end

    load_config CONFIG_PATH
    if @config.nil?
      Log.log_error "Could not read config file #{CONFIG_PATH}"
      return
    end

	  drive = DriveManager.new APPLICATION_NAME, @config
	  local = LocalManager.new @config

	  Log.log_notice "Getting local files..."
	  local.get_files
	  Log.log_notice "Getting remote files..."
	  drive.get_files
	  Log.log_notice 'Calculating diff...'
	  diff = get_diff drive, local
	  Log.log_message "Local folder is #{diff.remote_ahead.count} files behind and #{diff.local_ahead.count} files ahead of remote"
	  load_manifest @config['manifest_path']

    Log.log_message "Starting sync at #{Time.now}"
	  sync diff, drive, local

    Log.log_notice "Deleting lock file..."
    File.delete LOCK_PATH rescue nil
	end
end
