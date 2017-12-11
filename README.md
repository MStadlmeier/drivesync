# DriveSync
**v 1.3**

A command line utility that synchronizes your Google Drive files with a local folder on your machine. Downloads new remote files, uploads new local files to your Drive and deletes or updates files both locally and on Drive if they have changed in one place. Allows blacklisting or whitelisting of files and folders that should not / should be synced.

Works as a replacement for the Google Drive client for Windows and Mac


## Installation
There are two ways to install this software. Downloading the source and using your own Ruby installation or downloading the pre-packaged version including Ruby

### If you have Ruby installed
You need Ruby version 2.x . I tested and developed this software with 2.3.0 and 2.1.2
````
git clone git@github.com:MStadlmeier/drivesync.git
cd drivesync
bundle install
````
You can then run DriveSync with `ruby drivesync.rb`

### If you do not have a Ruby installation
[Download the bundled package here](https://github.com/MStadlmeier/drivesync/releases/tag/1.2.0) (Linux x86_64 package)
Extract it with `tar -xzf drivesync-linux-x86_64-v_1.2.tar.gz`
CD into the newly created folder
You can then run DriveSync with `./drivesync`

### Updates
The easiest way to get the latest version is by going in the directory that contains drivesync.rb and running `git pull` . You can also simply download the latest version from this site. DriveSync checks for updates whenever it starts and notifies you if there is a new version. However, users that automate DriveSync may not see this notice, so I suggest checking this site occasionally or running `ruby drivesync.rb -v` to check for updates.

## Configuration
There is a *config.yml* file containing all the software's settings. Depending on how you installed DriveSync you will find it either in **path/to/drivesync/config.yml** or **path/to/drivesync/lib/app/config.yml**
The settings are explained in the config file. For now, the most important option is the location for the drive folder on your local system. Set it to where you would like your local drive to be.

## Automating DriveSync
**Make sure to run DriveSync manually at least once after you install it, as it will ask you to authenticate.**

Ideally, you shouldn't have to sync your Drive manually, so let's run DriveSync periodically as a Cronjob. To do this, edit your crontab with `crontab -e` and add a Cronjob.

If you are using your own Ruby installation:

    */1 * * * * ruby /path/to/drivesync/drivesync.rb
**If you use rvm to manage your Ruby installations, you may need to run *rvm cron setup* before you can use ruby in Cronjobs**

If you used the bundled package:

    */1 * * * * /path/to/drivesync/drivesync

This will attempt to run DriveSync every minute. If DriveSync is started, but a sync is already in progress then the program will terminate and let the sync finish. You can also redirect the software's output into a log file so you can keep track of what is being synced or any errors that might occur: `path/to/drivesync/drivesync.rb > /tmp/drivesync.log`

## Large files
Personally, I wouldn't advise automatically syncing "large" (anything in the several hundred MB range) files between platforms with this or any other software. By default, DriveSync will ignore any file above 512 MB but this can be changed in the config file. If you do this, you may have to increase the timeout threshold which can also be done in the config file.

## Troubleshooting
If you encounter any difficulties, feel free to open an issue here and I'll get to you as soon as possible. Alternatively, running `ruby drivesync.rb reset` will reset your installation and clear your local drive folder, which might also help.

## Known Issues
* The Google Drive filesystem allows folders or files with identical paths, while common Linux filesystems do not. I strongly advice against having multiple files with identical paths on Drive (for example a folder with two files called foo.txt).

* Currently, DriveSync ignores Google Docs files (documents, presentations, spreadsheets, etc). In the future, these files might be "downloaded" as links to the corresponding files on Drive.


## Disclaimer
Neither I nor this software are in any way affiliated with Google. Although I tested this software very thoroughly and have been using it myself for over a year without any loss of data, you agree to use DriveSync at your own risk and I am not responsible for any damages that may occur.
