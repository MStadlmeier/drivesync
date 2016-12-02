require 'google/apis/drive_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'json'

require 'fileutils'
require './drive_manager'
require './file'
require './local_manager'

include Log

APPLICATION_NAME = 'DriveSync'
LOCAL_ROOT = "/home/max/Documents/drive"
MANIFEST_PATH = "/home/max/.drivesync_manifest"
#If set to true, DriveSync will delete files from your drive if they have been deleted locally
ALLOW_REMOTE_DELETION = false
#If set to true, changes to manifest will always be saved immediately. Slower, but safer
IMMEDIATE_REWRITE = true

class Synchronizer

	def get_diff drive, local
	  diff = FileDiff.new
	  drive.files.each do |file|
	    diff.remote_ahead << file unless local.find_by_path file.path
	  end

	  local.files.each do |file|
	    diff.local_ahead << file unless drive.find_by_path file
	  end

	  diff
	end

  def download_file file, drive
    Log.log_message "Downloading file #{file.path} ..."
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

  def add_to_manifest path, file
    Log.log_notice "Adding file #{path} to manifest"

    @manifest[path] = {}
    @manifest[path]["remote_modified"] = file.modified_time
    @manifest[path]["local_modified"] = File.mtime(File.join(LOCAL_ROOT, path))
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

	def run
	  drive = DriveManager.new APPLICATION_NAME
	  local = LocalManager.new LOCAL_ROOT

	  Log.log_notice "Getting local files..."
	  local.get_files
	  Log.log_notice "Getting remote files..."
	  drive.get_files
	  Log.log_notice 'Calculating diff...'
	  diff = get_diff drive, local
	  Log.log_message "Local folder is #{diff.remote_ahead.count} files behind and #{diff.local_ahead.count} files ahead of remote"
	  load_manifest MANIFEST_PATH

	  sync diff, drive, local
	end
end