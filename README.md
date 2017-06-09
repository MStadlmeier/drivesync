# DriveSync
A command line utility that synchronizes your Google Drive files with a local folder on your machine. Downloads new remote files, uploads new local files to your Drive and deletes or updates files both locally and on Drive if they have changed in one place.

Works as a replacement for the Google Drive client for Windows and Mac


## Setup
Make sure you have both ruby and the Google API gem installed.

    sudo apt-get install ruby
    gem install google-api-client

Configure the program in config.yml as you like. `drive_path`will be the path for your local copy of your Drive.


## Usage
Manually sync with

    ruby drivesync.rb

This will sync your drive, downloading, uploading, updating or deleting files as needed.


**DriveSync is meant to run automatically**, ideally as a cronjob. To schedule DriveSync to run automatically edit your crontab (`crontab -e`) and add the following line to it

    */1 * * * * ruby /path/to/drivesync.rb

This will sync every minute. Don't worry about syncing too often, there is a lock mechanism so there can never be more than one sync running at a time. You can also pipe the output of the program into a file if you want to see what it actually does.

Note : If you use rvm, you may need to run `rvm cron setup` before ruby can be used in a cronjob. It may also be necessary to cd into the drivesync folder before running the script

**DISCLAIMER**

Neither I nor this software are in any way affiliated with Google.