local GUI = require("GUI")
local system = require("System")
local fs = require("Filesystem")
local paths = require("Paths")

local versionCode = {
	part1 = 1,
	part2 = 4
}

-- Upgrading to verion 1.4

if (fs.exists(paths.user.applicationData .. "Lock/")) then
	-- Previous installed version was 1.0 - 1.3
	
	fs.rename(paths.user.applicationData .. "Lock/", paths.user.applicationData .. "DoorLock/")
	local settingsOld = fs.readTable(paths.user.applicationData .. "DoorLock/Config.cfg")
	local settingsNew = {
		autoLockTime = settingsOld[1],
		authFailSide = settingsOld[2],
		authSuccSide = settingsOld[3],
		isInAutostart = settingsOld[4],
		password = settingsOld[5],
		trustedUser = settingsOld[6],
		versionCode = versionCode
	}
	fs.writeTable(paths.user.applicationData .. "DoorLock/Config.cfg", settingsNew)
end