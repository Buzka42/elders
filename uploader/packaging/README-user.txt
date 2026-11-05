World of Meta Uploader
======================

Sends your Elders and Bloodsports data from World of Warcraft to World of Meta,
and brings the site's data back into the game.

Getting started
---------------
1. Start menu > World of Meta Uploader > Link account, and enter the code
   shown on the World of Meta site.
2. Type /reload in game. The first sync follows.

Background mode (tray icon)
---------------------------
The uploader keeps syncing while it runs. Quit it from the tray icon's menu.
To start it again, open "World of Meta Uploader" from the Start menu.

Script mode
-----------
Nothing runs in the background. Use Start menu > World of Meta Uploader >
Sync now whenever you want to sync.

Useful shortcuts
----------------
Sync now   one sync, then the window stays open so you can read the result
Status     shows the mode, autostart, WoW folder and the files it found

Your settings
-------------
Settings and your link token are kept in %APPDATA%\meta-uploader\
(config.json). The log is uploader.log in the same folder.
Uninstalling does not delete this folder, so a reinstall stays linked.
Delete the folder yourself if you want to remove the link as well.
