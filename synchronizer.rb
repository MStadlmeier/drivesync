require 'google/apis/drive_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'json'

require 'fileutils'
require './drive_manager'
require './file'
require './local_manager'
require './time'
require './ignore_list'

include Log

APPLICATION_NAME = 'DriveSync'
LOCAL_ROOT = "/home/max/Documents/drive"
MANIFEST_PATH = "/home/max/.drivesync_manifest"
IGNORE_LIST_PATH = "/home/max/Documents/drive/.ignore_list.txt"
LOCK_PATH = "/tmp/drivesync.lock"

#If set to true, DriveSync will delete files from your drive if they have been deleted locally
ALLOW_REMOTE_DELETION = true

#If set to true, changes to manifest will always be saved immediately. Slower, but safer
IMMEDIATE_REWRITE = true

#Determines what happens when a file is modified locally and remotely.
#:keep_latest keeps whichever version has been modified last
#:keep_remote always downloads the remote version
#:keep_local always pushes the local version
#:ignore keeps both versions separate and updates the manifest
UPDATE_CONFLICT_STRATEGY = :keep_latest

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
    FileUtils.mkdir_p File.join(LOCAL_ROOT, path)

    drive.download file, File.join(LOCAL_ROOT, file.path)
  end

  def delete_local_file path
    Log.log_message "Deleting file #{path} locally..."
    FileUtils.rm(File.join LOCAL_ROOT, path)
  end

  def delete_remote_file file, drive
    Log.log_message "Deleting file #{file.path} remotely"
    drive.trash_file file
  end

  def upload_file path, drive
    Log.log_message "Uploading file #{path} ..."
    drive.upload LOCAL_ROOT, path
  end

  def update_remote_file file, drive
    Log.log_message "Updating remote file #{file.path} ..."
    gets
    drive.update LOCAL_ROOT, file
  end

  def resolve_conflict file, drive, latest_local, latest_remote
    Log.log_message "Resolving conflict for #{file.path}"
    case UPDATE_CONFLICT_STRATEGY
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
      Log.log_error "Unrecognized update conflict strategy : #{UPDATE_CONFLICT_STRATEGY}"
    end
  end

  def add_to_manifest path, file
    Log.log_notice "Adding file #{path} to manifest"

    @manifest[path] = {}
    @manifest[path]["remote_modified"] = file.modified_time.nil? ? file.created_time : file.modified_time
    @manifest[path]["local_modified"] = File.mtime(File.join(LOCAL_ROOT, path)).to_datetime
    write_manifest MANIFEST_PATH if IMMEDIATE_REWRITE
  end

  def remove_from_manifest path
    Log.log_notice "Removing file #{path} from manifest"
    @manifest[path] = nil
    write_manifest MANIFEST_PATH if IMMEDIATE_REWRITE
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
      latest_local = File.mtime(File.join(LOCAL_ROOT, file.path)).to_datetime
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
      elsif ALLOW_REMOTE_DELETION
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

    ignore_list = IgnoreList.new IGNORE_LIST_PATH

	  drive = DriveManager.new APPLICATION_NAME, ignore_list
	  local = LocalManager.new LOCAL_ROOT, ignore_list

	  Log.log_notice "Getting local files..."
	  local.get_files
	  Log.log_notice "Getting remote files..."
	  drive.get_files
	  Log.log_notice 'Calculating diff...'
	  diff = get_diff drive, local
	  Log.log_message "Local folder is #{diff.remote_ahead.count} files behind and #{diff.local_ahead.count} files ahead of remote"
	  load_manifest MANIFEST_PATH

	  sync diff, drive, local

    Log.log_notice "Deleting lock file..."
    File.delete LOCK_PATH rescue nil
	end
end
