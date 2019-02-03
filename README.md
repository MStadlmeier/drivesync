# DriveSync
**v 1.4.0**

A command line utility that synchronizes your Google Drive files with a local folder on your machine. Downloads new remote files, uploads new local files to your Drive and deletes or updates files both locally and on Drive if they have changed in one place. Allows blacklisting or whitelisting of files and folders that should not / should be synced.

Works as a replacement for the Google Drive client for Windows and Mac


## Installation
Please note that the pre-packaged version has been removed because Travelling Ruby stopped being maintained, causing some SSL issues.

**Requires Ruby >= 2.0**. If Ruby isn't installed on your system, [get it through rvm](https://rvm.io/rvm/install) or install it yourself with your distro's package manager.

When Ruby is installed, get drivesync:

````
git clone https://github.com/MStadlmeier/drivesync.git
cd drivesync
bundle install
````

You can then run DriveSync with `ruby drivesync.rb`

### Updates
The easiest way to get the latest version is by going in the directory that contains drivesync.rb and running `git pull` . DriveSync checks for updates whenever it starts and notifies you if there is a new version. However, users that automate DriveSync may not see this notice, so I suggest checking this site occasionally or running `ruby drivesync.rb -v` to check for updates.

## Configuration
There is a config file located in `~/.drivesync/config.yml` containig all of DriveSync's settings.
This file can also be edited directly with `ruby drivesync.rb config` .
The settings are explained in the config file. For now, the most important option is the location for the drive folder on your local system. Set it to where you would like your local drive to be.

## Automating DriveSync
**Make sure to run DriveSync manually at least once after you install it, as it will ask you to authenticate.**

Ideally, you shouldn't have to sync your Drive manually, so let's run DriveSync periodically as a Cronjob. To do this, edit your crontab with `crontab -e` and add a Cronjob.

    */1 * * * * ruby /path/to/drivesync/drivesync.rb
**If you use rvm to manage your Ruby installations, you may need to run *rvm cron setup* before you can use ruby in Cronjobs**


This will attempt to run DriveSync every minute. If DriveSync is started, but a sync is already in progress then the program will terminate and let the sync finish. You can also redirect the software's output into a log file so you can keep track of what is being synced or any errors that might occur: `ruby path/to/drivesync/drivesync.rb > /tmp/drivesync.log`

## Large files
Personally, I wouldn't advise automatically syncing "large" (anything in the several hundred MB range) files between platforms with this or any other software. By default, DriveSync will ignore any file above 512 MB but this can be changed in the config file. If you do this, you may have to increase the timeout threshold which can also be done in the config file.

## Troubleshooting
If you encounter any difficulties, feel free to open an issue here and I'll get to you as soon as possible. Alternatively, running `ruby drivesync.rb reset` will reset your installation and clear your local drive folder, which might also help.

## Known Issues
* The Google Drive filesystem allows folders or files with identical paths, while common Linux filesystems do not. I strongly advice against having multiple files with identical paths on Drive (for example a folder with two files called foo.txt).

* Currently, DriveSync ignores Google Docs files (documents, presentations, spreadsheets, etc). In the future, these files might be "downloaded" as links to the corresponding files on Drive.

* Folders are not deleted remotely if they are deleted locally. The contents will be deleted, however.


## Disclaimer
Neither I nor this software are in any way affiliated with Google. Although I tested this software very thoroughly and have been using it myself for over a year without any loss of data, you agree to use DriveSync at your own risk and I am not responsible for any damages that may occur.
