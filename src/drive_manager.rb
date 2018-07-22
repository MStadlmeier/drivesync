require 'google/apis/drive_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'

require_relative './file'
require_relative './logger'
require_relative './helper'

include Log

class DriveManager
  OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'
  SCOPE = Google::Apis::DriveV3::AUTH_DRIVE
  CREDENTIALS_PATH = File.join(Dir.home, '.credentials',
                               "drivesync.yaml")
  DRIVE_FILES_TYPE = "application/vnd.google-apps"
  DRIVE_FOLDER_TYPE = "application/vnd.google-apps.folder"
  ROOT_FOLDER = "My Drive"

  attr_accessor :files
  attr_reader :credentials_path

  def authorize
    FileUtils.mkdir_p(File.dirname(CREDENTIALS_PATH))

    @credentials_path = CREDENTIALS_PATH
    client_id = Google::Auth::ClientId.from_file(@config['client_secret_path'])
    token_store = Google::Auth::Stores::FileTokenStore.new(file: credentials_path)
    authorizer = Google::Auth::UserAuthorizer.new(
      client_id, SCOPE, token_store)
    user_id = 'default'
    credentials = authorizer.get_credentials(user_id)
    if credentials.nil?
      url = authorizer.get_authorization_url(
        base_url: OOB_URI)
      puts "Open the following URL in the browser and enter the " +
           "resulting code after authorization"
      puts url
      code = STDIN.gets
      credentials = authorizer.get_and_store_credentials_from_code(
        user_id: user_id, code: code, base_url: OOB_URI)
    end
    credentials
  end

  def initialize app_name, config
    @config = config
    @service = Google::Apis::DriveV3::DriveService.new
    @service.client_options.application_name = app_name
    @service.authorization = authorize
    begin
      @service.client_options.open_timeout_sec = @config['timeout']
      @service.client_options.read_timeout_sec = @config['timeout']
      @service.client_options.send_timeout_sec = @config['timeout']
      @service.request_options.retries = @config['retries']
    rescue NoMethodError => e
      puts e.message
      Log.log_error "Error configuring drive service. Make sure your dependencies are up-to-date by running 'bundle install' in the drivesync directory"
      exit 1
    end
    @folder_cache = {}
  end

  #Loads file metadata from drive and stores them in remote_files with full paths
  def get_files
    fields = "next_page_token, files(id, name, owners, parents, mime_type, sharedWithMeTime, modifiedTime, createdTime)"

    folders = []
    @files = []

    #Go through pages of files and save files and folders
    next_token = nil
    first_page = true
    while first_page || (!next_token.nil? && !next_token.empty?)
      results = @service.list_files(q: "not trashed", fields: fields, page_token: next_token)
      folders += results.files.select{|file| file.mime_type == DRIVE_FOLDER_TYPE and belongs_to_me?(file)}
      @files += results.files.select{|file| !file.mime_type.include?(DRIVE_FILES_TYPE) and belongs_to_me?(file)}
      next_token = results.next_page_token
      first_page = false
    end

    #Cache folders
    folders.each {|folder| @folder_cache[folder.id] = folder}

    #Resolve file paths and apply ignore list
    @files.each {|file| file.path = resolve_path file}
    @files.reject!{|file| Helper.file_ignored? file.path, @config}

    Log.log_notice "Counted #{@files.count} remote files in #{folders.count} folders"
  end

  def find_by_path path
    return nil if @files.nil?
    @files.select{|file| file.path == path}.first
  end

  def download file, dest
    @service.get_file file.id, download_dest: dest
  end

  def upload local_root, local_path
    folder = nil
    #File is in sub-folder
    if local_path.include? '/'
      #Path without filename
      location = local_path.split('/')[0..-2].join('/')
      folder = traverse_and_create location
    end

    remote_file = Google::Apis::DriveV3::File.new
    remote_file.name = local_path.split('/').last
    remote_file.parents = [folder.id] unless folder.nil?

    fields = "id, name, mime_type, createdTime, modifiedTime"
    @service.create_file(remote_file, fields: fields, upload_source: File.join(local_root, local_path))
  end

  def trash_file file
    return if file.nil?
    id = file.id
    #Get version of the file with only the 'trashed' attribute
    file = @service.get_file id, fields: "trashed"
    file.trashed = true
    @service.update_file(id, file)
  end

  def update local_root, file
    return if file.nil?
    #Hack : This call returns a server error for mime type plain/text. Very likely a server bug
    content_type = file.mime_type == "text/plain" ? "application/json" : file.mime_type
    @service.update_file(file.id, content_type: content_type, upload_source: File.join(local_root, file.path))
  end

  private

  def resolve_path file
    return file.name if file.parents == nil || file.parents.count == 0
    path = [file.name]
    parent_id = file.parents.first
    while (parent_id != nil) do
      parent = get_folder parent_id
      #Prepend folder name, unless it's the root folder
      path.unshift parent.name if parent.parents != nil and parent.parents.count > 0
      parent_id = parent.parents == nil ? nil : parent.parents.first
    end
    path.join('/')
  end

  def get_folder id
    return @folder_cache[id] unless @folder_cache[id].nil?
    folder = @service.get_file(id, fields: "name, parents, id")
    Log.log_error("Cannot find parent folder : #{id}") if folder.nil?
    @folder_cache[id] = folder
  end

  def folder_with_name name, parent = nil
    @folder_cache.values.select{|file| file.name == name and (parent.nil? or file.parents.first == parent.id)}.first
  end

  def create_folder name, parent = nil
    folder = Google::Apis::DriveV3::File.new
    folder.mime_type = DRIVE_FOLDER_TYPE
    folder.parents = [parent.id] unless parent.nil?
    folder.name = name
    Log.log_notice "Creating folder #{folder.name} ..."
    result = @service.create_file folder, fields: "id, name, owners, parents, mime_type, sharedWithMeTime, modifiedTime, createdTime"
    @folder_cache[result.id] = result
  end

  #Traverses the given path on drive, creates any missing folders and returns the last folder in the path
  def traverse_and_create path
    root = @folder_cache.values.find{|file| file.name == ROOT_FOLDER and file.parents.nil?}

    #DriveV3::File (actually folders)
    files = [root]
    places = path.split '/'
    places.each do |place|
      next if place == ''
      folder = folder_with_name place, files.last
      folder = create_folder(place, files.last) if folder.nil?
      files << folder
    end
    files.last
  end

  #Returns true if this file actually belongs to the user and is not just shared with them
  #sharedWithMeTime is not enough to test this because files that were shared long ago don't seem to have this property
  #so the owners have to be checked as well
  def belongs_to_me? file
    #The only difference between shared files that have been added to your Drive
    #and those that haven't is that those that have have a file path (parents)
    return true if @config['sync_shared_in_drive'] and file.parents != nil and file.parents != []
    file.shared_with_me_time.nil? and file.owners != nil and file.owners.select{|owner| owner.me}.count > 0
  end
end
