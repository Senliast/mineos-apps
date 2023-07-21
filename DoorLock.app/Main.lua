-- DoorLock v.1.4 by Senliast
-- GitHub: https://github.com/Senliast/MineOSApps
-- 
-- A lock that supports code or fingerprint. You can configure output of a
-- redstone signal on different sites depending on if the authentication
-- failed or succeeded and an auto-lock timer.
-- 
-- This app is reborn of the CodeDoor app on older MineOS versions with some more
-- functions additionally. CodeDoor uses old libraries that doesnt work on new
-- MineOS versions (at least, officially) and is therefore not available anymore.
-- This app changes it.



-- Initializing hardware and loading libraries
local fs = require("Filesystem")
local GUI = require("GUI")
local unicode = require("Unicode")
local system = require("System")
local number = require("Number")
local event = require("Event")
local screen = require("Screen")
local component = require("Component")
local image = require("Image")
local paths = require("Paths")
local kb = require("Keyboard")
local txt = require("Text")
local online = false
local versionCode = {
	part1 = 1,
	part2 = 4
}
local rs

-- Perform update from earlier versions
system.execute("/Applications/DoorLock.app/updater.lua")

-- Get localization table dependent of current system language
local localization = system.getCurrentScriptLocalization()

local errorTable = { }
local currentErrorTablePos = 1
local shouldNotStart = false

if system.getCurrentScript() ~= "/Applications/DoorLock.app/Main.lua" then
	shouldNotStart = true
	errorTable[currentErrorTablePos] = localization.errorMassiv.canWorkPropOnlyIfInApp
	currentErrorTablePos = currentErrorTablePos + 1
end

-- Check whatever the redstone card are present
if component.isAvailable("redstone") == false then
	errorTable[currentErrorTablePos] = localization.errorMassiv.redstoneCardNeeded
	currentErrorTablePos = currentErrorTablePos + 1
	shouldNotStart = true
	GUI.alert(localization.errorMassiv.startInterrupted,
		errorTable
	)
else
	rs = component.redstone
end

-- Check whatever the required libraries are present
if shouldNotStart == false then
	if not fs.exists("/Libraries/sides.lua") or not fs.exists("/Libraries/colors.lua") then
	-- Ask the user to install required libraries

		shouldNotStart = true
		local workspaceInstallLibs, windowInstallLibs, menu = system.addWindow(GUI.filledWindow(1, 1, 60, 14, 0xE1E1E1))
		
		local installLibsText1 = windowInstallLibs:addChild(GUI.text(1, 3, 0x000000, localization.installLibsText1))
		local installLibsText2 = windowInstallLibs:addChild(GUI.text(1, 3, 0x000000, localization.installLibsText2))
		local acceptButton = windowInstallLibs:addChild(GUI.button(2, 2, 24, 3, 0xFFFFFF, 0x555555, 0x880000, 0xFFFFFF, localization.OK))
		local cancelButton = windowInstallLibs:addChild(GUI.button(2, 2, 24, 3, 0xFFFFFF, 0x555555, 0x880000, 0xFFFFFF, localization.cancel))
		
		local mostLongStrLength = 0
		
		if unicode.len(installLibsText1.text) > mostLongStrLength then mostLongStrLength = unicode.len(installLibsText1.text) end
		if unicode.len(installLibsText2.text) > mostLongStrLength then mostLongStrLength = unicode.len(installLibsText2.text) end
		
		installLibsText1.localX = number.round(windowInstallLibs.width / 2 - mostLongStrLength / 2)
		installLibsText1.localY = 4
		installLibsText2.localX = installLibsText1.localX
		installLibsText2.localY = installLibsText1.localY + 1
		acceptButton.localX = windowInstallLibs.width / 2 - (acceptButton.width + cancelButton.width + 4) / 2
		acceptButton.localY = windowInstallLibs.height - acceptButton.height - 2
		cancelButton.localX = acceptButton.localX +  acceptButton.width + 4
		cancelButton.localY = acceptButton.localY
		workspaceInstallLibs:draw()
		
		windowInstallLibs.actionButtons.maximize.onTouch = function()
		end
		
		acceptButton.onTouch = function()
			fs.copy("/Applications/DoorLock.app/Resources/sides.lua", "/Libraries/sides.lua")
			fs.copy("/Applications/DoorLock.app/Resources/colors.lua", "/Libraries/colors.lua")
			system.execute("/Applications/DoorLock.app/RestartApp.lua")
			windowInstallLibs:remove()
		end
		
		cancelButton.onTouch = function()
			windowInstallLibs:remove()
		end
	end
end

if shouldNotStart == false then
	local sides = require("sides")
	local colors = require("sides")


	----------------------------------------------------------------------
	-- User-settable variables

	-- If redstone singal is detected on this line - the lock will stop and reset
	-- the auto-lock timer if there is any and the door is ALREADY unlocked.
	-- Set to 6 to ignore.
	local blockAutoLockTimerSide = 6

	-- If redstone signal is detected on this line - the lock will disable
	-- even if locked and remain disabled until the signal is gone.
	-- Set to 6 to ignore.
	local forceUnlockSide = 6

	-- Max count of digits in the password
	local maxPasswordInputFieldNumbers = 10

	-- If no signal is detected on this line - the lock will enable and
	-- will not let any disable it even with corrent login data.
	-- Set to 6 to ignore.
	local onlineSide = 6

	-- Disable the "fingerprint scanning" animation during the biometric authenticaion.
	-- The program checks the user immediatelly.
	local disableBioAuthAnimation = false

	-- Disable the fail / success authentication animation.
	local disableAuthAnimation = false

	-- Title, that will be displayed on the top. If you want to leave the
	-- default title, set to "".
	local title = ""
	----------------------------------------------------------------------



	----------------------------------------------------------------------
	-- Logic variables

	-- Passwords, that will be accepted by the system.
	local password = { }

	-- User that will be accepted during biometric authentication.
	local trustedUser = "0"

	local currentEnteredPassword = ""

	-- After this amount of second the door will automatically lock if it is not opened.
	-- Set to 0 to disable auto-lock.
	local autoLockTime = 0

	local isInAutostart = false
	local locked = true
	local UIActive = true
	local offlineMessageAlreadyShown = false
	local sendingForceUnlockSignal = false
	local lockOnce = false
	local unlockOnce = false
	local settingsFolder = paths.user.applicationData .. "DoorLock/"
	local settingsFile = settingsFolder .. "Config.cfg"
	local settings = { }
	local settingsInvalid = false
	local setupShouldLoad = false
	local firstSetup = false
	local origWidth, origHeight = screen.getWidth(), screen.getHeight()
	local width, height = 59, 30
	----------------------------------------------------------------------



	----------------------------------------------------------------------
	-- Redstone variables

	-- Redstone signal will be put on this line, while the lock is disabled.
	local authSuccSide, authSuccColor = sides.right, colors.green

	-- Redstone signal will be put on this line for a small amout of time
	-- if the authentication has failed.
	local authFailSide, authFailColor = sides.right, colors.yellow
	----------------------------------------------------------------------
	
	

	-- Because of a magic, for me not understandable reason, in rare cases
	-- if the app is running for a long time, like a few days,
	-- the call to the redstone API randomly fails, causing the app to crash.
	-- May be it has something to do with chunk loading idk. Anyway,
	-- therefore i made it through a safe call, that will just ignore the
	-- error and the app will continue run. Also used to ignore the error
	-- if additional redstone functions are disabled.
	function safersGetInput(side)
		local ret = {pcall(rs.getInput, side)}
		if not tonumber(ret[2]) then
			return {0, 0}
		else
			return ret
		end
	end

	-- Write settings to the disk.
	function saveSettings()
		settings = { }
		errorTable = { }
		currentErrorTablePos = 1
		settingsInvalid = false
		
		if not tonumber(autoLockTime) then
			settingsInvalid = true
			errorTable[currentErrorTablePos] = localization.errorMassiv.autolockTInvalid
			currentErrorTablePos = currentErrorTablePos + 1
		end
		
		if authFailSide == authSuccSide then
			settingsInvalid = true
			errorTable[currentErrorTablePos] = localization.errorMassiv.sidesCantBeSame
			currentErrorTablePos = currentErrorTablePos + 1
		end
		
		local userSettings = system.getUserSettings()
		local alreadyInAutostart = false
		if isInAutostart == true then
			if not fs.exists("/Applications/DoorLock.app/Main.lua") then
				settingsInvalid = true
				errorTable[currentErrorTablePos] = localization.errorMassiv.autostartOnlyIfInApp
				currentErrorTablePos = currentErrorTablePos + 1
			else
				local userSettings = system.getUserSettings()
				local alreadyInAutostart = false
				
				-- Iterate through the autostart table and insert the app if not yet
				for key, value in pairs(userSettings.tasks) do
					if value.path == "/Applications/DoorLock.app/Main.lua" then alreadyInAutostart = true end
				end

				if alreadyInAutostart == false then
				table.insert(userSettings.tasks, {
					path = "/Applications/DoorLock.app/Main.lua",
					enabled = true,
					mode = 1,
				})
				end
				-- Save user settings
				system.saveUserSettings()
			end
		else
		  -- Iterate through the autostart table and remove the app
			for key, value in pairs(userSettings.tasks) do
				if value.path == "/Applications/DoorLock.app/Main.lua" then table.remove(userSettings.tasks, key) end
			end
			
			-- Save user settings.
			system.saveUserSettings()
		end
		
		
		for key, value in pairs(password) do
			if not tonumber(value) then
				settingsInvalid = true
				errorTable[currentErrorTablePos] = localization.errorMassiv.pwdCanContOnlyNum
				currentErrorTablePos = currentErrorTablePos + 1
			end
		end
	  
	    if settingsInvalid == false then
			settings.autoLockTime = autoLockTime
			settings.authFailSide = authFailSide
			settings.authSuccSide = authSuccSide
			settings.password = password
			settings.isInAutostart = isInAutostart
			settings.trustedUser = trustedUser
			settings.versionCode = versionCode
			fs.writeTable(settingsFile, settings)
		end
	end

	-- Read config file from the disk.
	function loadSettings()
		settings = { }
		errorTable = { }
		currentErrorTablePos = 1
		settingsInvalid = false
		settings = fs.readTable(settingsFile)	  

		autoLockTime = settings.autoLockTime
		authFailSide = settings.authFailSide
		authSuccSide = settings.authSuccSide
		isInAutostart = settings.isInAutostart
		password = settings.password
		trustedUser = settings.trustedUser
		
		if not tonumber(settings.autoLockTime) then
			settingsInvalid = true
			errorTable[currentErrorTablePos] = localization.errorMassiv.autolockTInvalid
			currentErrorTablePos = currentErrorTablePos + 1
		end
		
		if settings.authFailSide == settings.authSuccSide then
			settingsInvalid = true
			errorTable[currentErrorTablePos] = localization.errorMassiv.sidesCantBeSame
			currentErrorTablePos = currentErrorTablePos + 1
		end
		
		local userSettings = system.getUserSettings()
		local alreadyInAutostart = false
		if isInAutostart == true then
			if not fs.exists("/Applications/DoorLock.app/Main.lua") then
				settingsInvalid = true
				errorTable[currentErrorTablePos] = localization.errorMassiv.autostartOnlyIfInApp
				currentErrorTablePos = currentErrorTablePos + 1
			else
			
			-- Iterate through the autostart table and insert the app if not yet
			for key, value in pairs(userSettings.tasks) do
				if value.path == "/Applications/DoorLock.app/Main.lua" then alreadyInAutostart = true end
			end

			if alreadyInAutostart == false then
				table.insert(userSettings.tasks, {
					path = "/Applications/DoorLock.app/Main.lua",
					enabled = true,
					mode = 1,
				})
			end
			
			-- Save user settings
			system.saveUserSettings()
			end
		else
			-- Iterate through the autostart table and remove the app
			for key, value in pairs(userSettings.tasks) do
				if value.path == "/Applications/DoorLock.app/Main.lua" then table.remove(userSettings.tasks, key) end
			end
			
			-- Save user settings.
			system.saveUserSettings()
		end
				
		for key, value in pairs(settings.password) do
			if not tonumber(value) then
				settingsInvalid = true
				errorTable[currentErrorTablePos] = localization.errorMassiv.pwdCanContOnlyNum
				currentErrorTablePos = currentErrorTablePos + 1
			end
		end
	end

	-- Check if ALT is pressed.
	if kb.isKeyDown(56) or kb.isKeyDown(184) then setupShouldLoad = true end



	-- Build GUI

	-- Add a new window to MineOS workspace
	local workspaceSetup, windowSetup, menu = system.addWindow(GUI.filledWindow(1, 1, 120, 40, 0xE1E1E1))

	windowSetup.localX = number.round(screen.getWidth() / 2 - windowSetup.width / 2)
	windowSetup.localY = number.round(screen.getHeight() / 2 - windowSetup.height / 2)

	-- Create callback function with resizing rules when window changes its' size

	windowSetup.actionButtons.maximize.onTouch = function()
	end

	if title == "" then title = localization.title end
	screen.setResolution(width, height)

	-- Create objects

	local workspace = GUI.workspace()
	local background = workspace:addChild(GUI.panel(1, 1, width, height, 0x005b96))
	local backgroundD = workspace:addChild(GUI.panel(1, 1, workspace.width, workspace.height, 0xc85f00))

	local text1 = workspace:addChild(GUI.text(1, 3, 0xffffff, title))
	local keyPadButton1 = workspace:addChild(GUI.button(7, 6, 5, 3, 0x62c2ff, 0xffffff, 0x0099ff, 0xffffff, "1"))
	local keyPadButton2 = workspace:addChild(GUI.button(keyPadButton1.x + 7, keyPadButton1.y, 5, 3, 0x62c2ff, 0xffffff, 0x0099ff, 0xffffff, "2"))
	local keyPadButton3 = workspace:addChild(GUI.button(keyPadButton2.x + 7, keyPadButton1.y, 5, 3, 0x62c2ff, 0xffffff, 0x0099ff, 0xffffff, "3"))
	local keyPadButton4 = workspace:addChild(GUI.button(keyPadButton1.x, keyPadButton1.y + 5, 5, 3, 0x62c2ff, 0xffffff, 0x0099ff, 0xffffff, "4"))
	local keyPadButton5 = workspace:addChild(GUI.button(keyPadButton4.x + 7, keyPadButton4.y, 5, 3, 0x62c2ff, 0xffffff, 0x0099ff, 0xffffff, "5"))
	local keyPadButton6 = workspace:addChild(GUI.button(keyPadButton5.x + 7, keyPadButton4.y, 5, 3, 0x62c2ff, 0xffffff, 0x0099ff, 0xffffff, "6"))
	local keyPadButton7 = workspace:addChild(GUI.button(keyPadButton4.x, keyPadButton4.y + 5, 5, 3, 0x62c2ff, 0xffffff, 0x0099ff, 0xffffff, "7"))
	local keyPadButton8 = workspace:addChild(GUI.button(keyPadButton7.x + 7, keyPadButton7.y, 5, 3, 0x62c2ff, 0xffffff, 0x0099ff, 0xffffff, "8"))
	local keyPadButton9 = workspace:addChild(GUI.button(keyPadButton8.x + 7, keyPadButton7.y, 5, 3, 0x62c2ff, 0xffffff, 0x0099ff, 0xffffff, "9"))
	local keyPadButtonC = workspace:addChild(GUI.button(keyPadButton7.x, keyPadButton7.y + 5, 5, 3, 0x62c2ff, 0xffffff, 0x0099ff, 0xffffff, "C"))
	local keyPadButton0 = workspace:addChild(GUI.button(keyPadButtonC.x + 7, keyPadButtonC.y, 5, 3, 0x62c2ff, 0xffffff, 0x0099ff, 0xffffff, "0"))
	local keyPadButtonL = workspace:addChild(GUI.button(keyPadButton0.x + 7, keyPadButtonC.y, 5, 3, 0x62c2ff, 0xffffff, 0x0099ff, 0xffffff, "►"))
	local text2 = workspace:addChild(GUI.text(7, 26, 0xffffff, localization.text2))
	local text3 = workspace:addChild(GUI.text(7, 27, 0xffffff, localization.text3))
	local text4 = workspace:addChild(GUI.text(7, 28, 0xffffff, localization.text4))
	local authFieldPart1 = workspace:addChild(GUI.text(35, 10, 0xffffff, "┌─────────────────┐"))
	local authFieldPart2 = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart1.y + 1, 0xffffff, "│                 │"))
	local authFieldPart3 = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart2.y + 1, 0xffffff, "│                 │"))
	local authFieldPart4 = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart3.y + 1, 0xffffff, "│                 │"))
	local authFieldPart5 = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart4.y + 1, 0xffffff, "│                 │"))
	local authFieldPart6 = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart5.y + 1, 0xffffff, "│                 │"))
	local authFieldPart7 = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart6.y + 1, 0xffffff, "│                 │"))
	local authFieldPart8 = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart7.y + 1, 0xffffff, "│                 │"))
	local authFieldPart9 = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart8.y + 1, 0xffffff, "│                 │"))
	local authFieldPart10 = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart9.y + 1, 0xffffff, "│                 │"))
	local authFieldPart11 = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart10.y + 1, 0xffffff, "└─────────────────┘"))
	local passwordFieldPart1 = workspace:addChild(GUI.text(35, 6, 0xffffff, "┌─────────────────┐"))
	local passwordFieldPart2 = workspace:addChild(GUI.text(passwordFieldPart1.x, passwordFieldPart1.y + 1, 0xffffff, "│                 │"))
	local passwordFieldPart3 = workspace:addChild(GUI.text(passwordFieldPart2.x, passwordFieldPart2.y + 1, 0xffffff, "└─────────────────┘"))
	local passwordFieldPart4 = workspace:addChild(GUI.text(passwordFieldPart2.x, passwordFieldPart2.y, 0xffffff, ""))

	local text1D = workspace:addChild(GUI.text(1, 3, 0xffffff, title))
	local keyPadButton1D = workspace:addChild(GUI.button(7, 6, 5, 3, 0xff7900, 0xffffff, 0xff7900, 0xffffff, "1"))
	local keyPadButton2D = workspace:addChild(GUI.button(keyPadButton1.x + 7, keyPadButton1.y, 5, 3, 0xff7900, 0xffffff, 0xff7900, 0xffffff, "2"))
	local keyPadButton3D = workspace:addChild(GUI.button(keyPadButton2.x + 7, keyPadButton1.y, 5, 3, 0xff7900, 0xffffff, 0xff7900, 0xffffff, "3"))
	local keyPadButton4D = workspace:addChild(GUI.button(keyPadButton1.x, keyPadButton1.y + 5, 5, 3, 0xff7900, 0xffffff, 0xff7900, 0xffffff, "4"))
	local keyPadButton5D = workspace:addChild(GUI.button(keyPadButton4.x + 7, keyPadButton4.y, 5, 3, 0xff7900, 0xffffff, 0xff7900, 0xffffff, "5"))
	local keyPadButton6D = workspace:addChild(GUI.button(keyPadButton5.x + 7, keyPadButton4.y, 5, 3, 0xff7900, 0xffffff, 0xff7900, 0xffffff, "6"))
	local keyPadButton7D = workspace:addChild(GUI.button(keyPadButton4.x, keyPadButton4.y + 5, 5, 3, 0xff7900, 0xffffff, 0xff7900, 0xffffff, "7"))
	local keyPadButton8D = workspace:addChild(GUI.button(keyPadButton7.x + 7, keyPadButton7.y, 5, 3, 0xff7900, 0xffffff, 0xff7900, 0xffffff, "8"))
	local keyPadButton9D = workspace:addChild(GUI.button(keyPadButton8.x + 7, keyPadButton7.y, 5, 3, 0xff7900, 0xffffff, 0xff7900, 0xffffff, "9"))
	local keyPadButtonCD = workspace:addChild(GUI.button(keyPadButton7.x, keyPadButton7.y + 5, 5, 3, 0xff7900, 0xffffff, 0xff7900, 0xffffff, "C"))
	local keyPadButton0D = workspace:addChild(GUI.button(keyPadButtonC.x + 7, keyPadButtonC.y, 5, 3, 0xff7900, 0xffffff, 0xff7900, 0xffffff, "0"))
	local keyPadButtonLD = workspace:addChild(GUI.button(keyPadButton0.x + 7, keyPadButtonC.y, 5, 3, 0xff7900, 0xffffff, 0xff7900, 0xffffff, "►"))
	local text2D = workspace:addChild(GUI.text(7, 26, 0xffffff, localization.text2D))
	local text3D = workspace:addChild(GUI.text(7, 27, 0xffffff, localization.text3D))
	local text4D = workspace:addChild(GUI.text(7, 28, 0xffffff, localization.text4D))
	local authFieldPart1D = workspace:addChild(GUI.text(35, 10, 0xffffff, "┌─────────────────┐"))
	local authFieldPart2D = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart1.y + 1, 0xffffff, "│                 │"))
	local authFieldPart3D = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart2.y + 1, 0xffffff, "│                 │"))
	local authFieldPart4D = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart3.y + 1, 0xffffff, "│                 │"))
	local authFieldPart5D = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart4.y + 1, 0xffffff, "│                 │"))
	local authFieldPart6D = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart5.y + 1, 0xffffff, "│                 │"))
	local authFieldPart7D = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart6.y + 1, 0xffffff, "│                 │"))
	local authFieldPart8D = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart7.y + 1, 0xffffff, "│                 │"))
	local authFieldPart9D = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart8.y + 1, 0xffffff, "│                 │"))
	local authFieldPart10D = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart9.y + 1, 0xffffff, "│                 │"))
	local authFieldPart11D = workspace:addChild(GUI.text(authFieldPart1.x, authFieldPart10.y + 1, 0xffffff, "└─────────────────┘"))
	local passwordFieldPart1D = workspace:addChild(GUI.text(35, 6, 0xffffff, "┌─────────────────┐"))
	local passwordFieldPart2D = workspace:addChild(GUI.text(passwordFieldPart1.x, passwordFieldPart1.y + 1, 0xffffff, "│                 │"))
	local passwordFieldPart3D = workspace:addChild(GUI.text(passwordFieldPart2.x, passwordFieldPart2.y + 1, 0xffffff, "└─────────────────┘"))
	local passwordFieldPart4D = workspace:addChild(GUI.text(passwordFieldPart2.x, passwordFieldPart2.y, 0xffffff, ""))

	local warningMessageBackgroundOM = workspace:addChild(GUI.panel(1, 14, workspace.width, 5,  0xff0000))
	local warningMessageOM = workspace:addChild(GUI.text(1, 1, 0xffffff, localization.offline))
	warningMessageOM.localX = number.round(warningMessageBackgroundOM.width / 2 - warningMessageOM.width / 2)
	warningMessageOM.localY = number.round(warningMessageBackgroundOM.localY + 2)

	local textStatus = workspace:addChild(GUI.text(1, 27, 0xffffff, "0"))

	function Split(s, delimiter)
		result = {};
		for match in (s..delimiter):gmatch("(.-)"..delimiter) do
			table.insert(result, match);
		end
		return result;
	end

	function drawSetupUI()
		screen.setResolution(origWidth, origHeight)

		-- Build GUI of the setup window

		local autoLockTimerText1 = windowSetup:addChild(GUI.text(3, 2, 0x000000, localization.autoLockTimerText1))
		local autoLockTimerText2 = windowSetup:addChild(GUI.text(3, 2, 0x000000, localization.autoLockTimerText2))
		local autoLockTimerInput = windowSetup:addChild(GUI.input(2, 2, 30, 3, 0xEEEEEE, 0x555555, 0x999999, 0xFFFFFF, 0x2D2D2D, "0", " "))
		local outputOnWrongAuthText1 = windowSetup:addChild(GUI.text(3, 2, 0x000000, localization.outputOnWrongAuthText1))
		local outputOnWrongAuthText2 = windowSetup:addChild(GUI.text(3, 2, 0x000000, localization.outputOnWrongAuthText2))
		local outputOnWrongAuthComboBox = windowSetup:addChild(GUI.comboBox(3, 2, 30, 3, 0xEEEEEE, 0x2D2D2D, 0xCCCCCC, 0x888888))
		outputOnWrongAuthComboBox:addItem(localization.right)
		outputOnWrongAuthComboBox:addItem(localization.left)
		outputOnWrongAuthComboBox:addItem(localization.back)
		outputOnWrongAuthComboBox:addItem(localization.front)
		local outputOnSuccAuthText1 = windowSetup:addChild(GUI.text(3, 2, 0x000000, localization.outputOnSuccAuthText1))
		local outputOnSuccAuthText2 = windowSetup:addChild(GUI.text(3, 2, 0x000000, localization.outputOnSuccAuthText2))
		local outputOnSuccAuthComboBox = windowSetup:addChild(GUI.comboBox(3, 2, 30, 3, 0xEEEEEE, 0x2D2D2D, 0xCCCCCC, 0x888888))
		outputOnSuccAuthComboBox:addItem(localization.right)
		outputOnSuccAuthComboBox:addItem(localization.left)
		outputOnSuccAuthComboBox:addItem(localization.back)
		outputOnSuccAuthComboBox:addItem(localization.front)
		local putToAutoStartText = windowSetup:addChild(GUI.text(3, 2, 0x000000, localization.putToAutoStartText))
		local putToAutoStartSwitch = windowSetup:addChild(GUI.switch(3, 2, 8, 0x66DB80, 0x1D1D1D, 0xEEEEEE, false))

		local passwordsText1 = windowSetup:addChild(GUI.text(3, 2, 0x000000, localization.passwordsText1))
		local passwordsText2 = windowSetup:addChild(GUI.text(3, 2, 0x000000, localization.passwordsText2))
		local passwordsText3 = windowSetup:addChild(GUI.text(3, 2, 0x000000, localization.passwordsText3))
		local passwordsInput = windowSetup:addChild(GUI.input(2, 2, 30, 3, 0xEEEEEE, 0x555555, 0x999999, 0xFFFFFF, 0x2D2D2D, "0", " "))

		local bioUsersText1 = windowSetup:addChild(GUI.text(3, 2, 0x000000, localization.bioUsersText1))
		local bioUsersText2 = windowSetup:addChild(GUI.text(3, 2, 0x000000, localization.bioUsersText2))
		local bioUsersText3 = windowSetup:addChild(GUI.text(3, 2, 0x000000, localization.bioUsersText3))
		local bioUsersInput = windowSetup:addChild(GUI.input(2, 2, 30, 3, 0xEEEEEE, 0x555555, 0x999999, 0xFFFFFF, 0x2D2D2D, "0", " "))

		local uninstallButton = windowSetup:addChild(GUI.button(2, 2, 24, 3, 0xFFFFFF, 0x555555, 0x880000, 0xFFFFFF, localization.uninstall))
		uninstallButton.onTouch = function()
			local workspaceUninstall, windowUninstall, menu = system.addWindow(GUI.filledWindow(1, 1, 60, 14, 0xE1E1E1))

			local uninstallText1 = windowUninstall:addChild(GUI.text(3, 2, 0x000000, localization.uninstallText1))
			local uninstallText2 = windowUninstall:addChild(GUI.text(3, 2, 0x000000, localization.uninstallText2))
			local acceptButton = windowUninstall:addChild(GUI.button(2, 2, 24, 3, 0xFFFFFF, 0x555555, 0x880000, 0xFFFFFF, localization.OK))
			local cancelButton = windowUninstall:addChild(GUI.button(2, 2, 24, 3, 0xFFFFFF, 0x555555, 0x880000, 0xFFFFFF, localization.cancel))

			-- Calculate position and centrize objects

			local mostLongStrLength = 0

			if unicode.len(uninstallText1.text) > mostLongStrLength then mostLongStrLength = unicode.len(uninstallText1.text) end
			if unicode.len(uninstallText2.text) > mostLongStrLength then mostLongStrLength = unicode.len(uninstallText2.text) end

			uninstallText1.localX = number.round(windowUninstall.width / 2 - mostLongStrLength / 2)
			uninstallText1.localY = 4
			uninstallText2.localX = uninstallText1.localX
			uninstallText2.localY = uninstallText1.localY + 1
			acceptButton.localX = windowUninstall.width / 2 - (acceptButton.width + cancelButton.width + 4) / 2
			acceptButton.localY = windowUninstall.height - 4
			cancelButton.localX = acceptButton.localX +  acceptButton.width + 4
			cancelButton.localY = acceptButton.localY
			workspaceUninstall:draw()

			windowUninstall.actionButtons.maximize.onTouch = function()
			end
			
			acceptButton.onTouch = function()
			-- Remove program from autostart if set.
				local userSettings = system.getUserSettings()
				
				for key, value in pairs(userSettings.tasks) do
					if value.path == "/Applications/DoorLock.app/Main.lua" then table.remove(userSettings.tasks, key) end
				end
				
				system.saveUserSettings()
				
				fs.remove("/Libraries/sides.lua")
				fs.remove("/Libraries/colors.lua")
				fs.remove(settingsFolder)
				fs.remove("/Applications/DoorLock.app")
				shouldNotStart = true
				windowUninstall:remove()
				windowSetup:remove()
			end
			
			cancelButton.onTouch = function()
				windowUninstall:remove()
			end
		end
		  
		-- Check current settings, save them and start the app
		local saveAndStartButton = windowSetup:addChild(GUI.button(2, 2, 24, 3, 0xFFFFFF, 0x555555, 0x880000, 0xFFFFFF, localization.saveAndStart))
		saveAndStartButton.onTouch = function()		
			autoLockTime = autoLockTimerInput.text
			if outputOnWrongAuthComboBox.selectedItem == 1 then authFailSide = sides.right end
			if outputOnWrongAuthComboBox.selectedItem == 2 then authFailSide = sides.left end
			if outputOnWrongAuthComboBox.selectedItem == 3 then authFailSide = sides.back end
			if outputOnWrongAuthComboBox.selectedItem == 4 then authFailSide = sides.front end
			if outputOnSuccAuthComboBox.selectedItem == 1 then authSuccSide = sides.right end
			if outputOnSuccAuthComboBox.selectedItem == 2 then authSuccSide = sides.left end
			if outputOnSuccAuthComboBox.selectedItem == 3 then authSuccSide = sides.back end
			if outputOnSuccAuthComboBox.selectedItem == 4 then authSuccSide = sides.front end
			isInAutostart = putToAutoStartSwitch.state
			password = Split(passwordsInput.text, ",")
			trustedUser = Split(bioUsersInput.text, ",")
			
			saveSettings()
			
			if settingsInvalid == true then 
				GUI.alert(localization.errorMassiv.startInterrupted,
					errorTable
			)
			else
				firstSetup = false
				screen.setResolution(origWidth, origHeight)
				system.execute("/Applications/DoorLock.app/RestartApp.lua")
				windowSetup:remove()
			end
		end
	
		local cancelButton = windowSetup:addChild(GUI.button(2, 2, 24, 3, 0xFFFFFF, 0x555555, 0x880000, 0xFFFFFF, localization.cancel))
		cancelButton.onTouch = function()
			windowSetup:remove()
		end
		  
		  
		
		-- Calculate and centrize objects

		autoLockTimerText1.localX = 4
		autoLockTimerText1.localY = 4
		autoLockTimerText2.localX = autoLockTimerText1.localX
		autoLockTimerText2.localY = autoLockTimerText1.localY + 1
		autoLockTimerInput.localX = autoLockTimerText2.localX
		autoLockTimerInput.localY = autoLockTimerText2.localY + 2
		outputOnWrongAuthText1.localX = autoLockTimerInput.localX
		outputOnWrongAuthText1.localY = autoLockTimerInput.localY + 4
		outputOnWrongAuthText2.localX = outputOnWrongAuthText1.localX
		outputOnWrongAuthText2.localY = outputOnWrongAuthText1.localY + 1
		outputOnWrongAuthComboBox.localX = outputOnWrongAuthText2.localX
		outputOnWrongAuthComboBox.localY = outputOnWrongAuthText2.localY + 2
		outputOnSuccAuthText1.localX = outputOnWrongAuthComboBox.localX
		outputOnSuccAuthText1.localY = outputOnWrongAuthComboBox.localY + 4
		outputOnSuccAuthText2.localX = outputOnSuccAuthText1.localX
		outputOnSuccAuthText2.localY = outputOnSuccAuthText1.localY + 1
		outputOnSuccAuthComboBox.localX = outputOnSuccAuthText2.localX
		outputOnSuccAuthComboBox.localY = outputOnSuccAuthText2.localY + 2
		putToAutoStartText.localX = outputOnSuccAuthComboBox.localX
		putToAutoStartText.localY = outputOnSuccAuthComboBox.localY + 4
		putToAutoStartSwitch.localX = putToAutoStartText.localX
		putToAutoStartSwitch.localY = putToAutoStartText.localY + 2

		passwordsText1.localX = 70
		passwordsText1.localY = 4
		passwordsText2.localX = passwordsText1.localX
		passwordsText2.localY = passwordsText1.localY + 1
		passwordsText3.localX = passwordsText2.localX
		passwordsText3.localY = passwordsText2.localY + 1
		passwordsInput.localX = passwordsText3.localX
		passwordsInput.localY = passwordsText3.localY + 2
		bioUsersText1.localX = passwordsInput.localX
		bioUsersText1.localY = passwordsInput.localY + 4
		bioUsersText2.localX = bioUsersText1.localX
		bioUsersText2.localY = bioUsersText1.localY + 1
		bioUsersText3.localX = bioUsersText2.localX
		bioUsersText3.localY = bioUsersText2.localY + 1
		bioUsersInput.localX = bioUsersText3.localX
		bioUsersInput.localY = bioUsersText3.localY + 2

		uninstallButton.localX = windowSetup.width / 2 - (uninstallButton.width  + saveAndStartButton.width + cancelButton.width + 6) / 2
		uninstallButton.localY = windowSetup.height - 4
		saveAndStartButton.localX = uninstallButton.localX + uninstallButton.width + 2
		saveAndStartButton.localY = uninstallButton.localY
		cancelButton.localX = saveAndStartButton.localX + saveAndStartButton.width  + 2
		cancelButton.localY = saveAndStartButton.localY

		if greetingsButtonNext then greetingsButtonNext.hidden = true end
		if greetingText1 then greetingText1.hidden = true end
		if greetingText2 then greetingText2.hidden = true end
		if greetingText3 then greetingText3.hidden = true end
		if greetingText4 then greetingText4.hidden = true end
		if greetingText5 then greetingText5.hidden = true end
		if greetingText6 then greetingText6.hidden = true end
			
		-- If the app is started the first time
		if firstSetup == false then
			loadSettings()
			
			if settingsInvalid == false then
				autoLockTimerInput.text = autoLockTime 
				if authFailSide == sides.right then outputOnWrongAuthComboBox.selectedItem = 1 end
				if authFailSide == sides.left then outputOnWrongAuthComboBox.selectedItem = 2 end
				if authFailSide == sides.back then outputOnWrongAuthComboBox.selectedItem = 3 end
				if authFailSide == sides.front then outputOnWrongAuthComboBox.selectedItem = 4 end
				if authSuccSide == sides.right then outputOnSuccAuthComboBox.selectedItem = 1 end
				if authSuccSide == sides.left then outputOnSuccAuthComboBox.selectedItem = 2 end
				if authSuccSide == sides.back then outputOnSuccAuthComboBox.selectedItem = 3 end
				if authSuccSide == sides.front then outputOnSuccAuthComboBox.selectedItem = 4 end
				putToAutoStartSwitch:setState(isInAutostart)

				-- Retrieve passwords, convert into string and show them in the settings window
				passwordsInput.text = ""
				
				for key, value in pairs(password) do
					if passwordsInput.text == "" then
						passwordsInput.text = value
					else
						passwordsInput.text = passwordsInput.text .. "," .. value
					end
				end

				-- Retrieve bio users and show them in the settings window
				bioUsersInput.text = ""
				for key, value in pairs(trustedUser) do
					if bioUsersInput.text == "" then
						bioUsersInput.text = value
					else
						bioUsersInput.text = bioUsersInput.text .. "," .. value
					end
				end
			end
		end
	
		workspaceSetup:draw()
		windowSetup:draw()
	end

	-- Draws the "fingerprint scanning" animation during the bio auth.
	function visualizeBioAuth()
		if disableBioAuthAnimation then return end

		text2.hidden = true
		text3.hidden = true
		text4.hidden = true
		
		textStatus.hidden = false
		textStatus.text = localization.checkingUser
		textStatus.localX = number.round(workspace.width / 2 - unicode.len(textStatus.text) / 2)
		workspace:draw()

		-- Pattern for the animation.
		local origCurrentStr = "0"
		visualizingStr = "╠═════════════════╣"
		
		origCurrentStr = authFieldPart1.text
		authFieldPart1.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart1.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart2.text
		authFieldPart2.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart2.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart3.text
		authFieldPart3.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart3.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart4.text
		authFieldPart4.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart4.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart5.text
		authFieldPart5.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart5.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart6.text
		authFieldPart6.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart6.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart7.text
		authFieldPart7.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart7.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart8.text
		authFieldPart8.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart8.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart9.text
		authFieldPart9.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart9.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart10.text
		authFieldPart10.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart10.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart11.text
		authFieldPart11.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart11.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart11.text
		authFieldPart11.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart11.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart10.text
		authFieldPart10.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart10.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart9.text
		authFieldPart9.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart9.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart8.text
		authFieldPart8.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart8.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart7.text
		authFieldPart7.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart7.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart6.text
		authFieldPart6.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart6.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart5.text
		authFieldPart5.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart5.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart4.text
		authFieldPart4.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart4.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart3.text
		authFieldPart3.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart3.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart2.text
		authFieldPart2.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart2.text = origCurrentStr
		event.sleep(0.05)
		
		origCurrentStr = authFieldPart1.text
		authFieldPart1.text = visualizingStr
		workspace:draw()
		event.sleep(0.05)
		authFieldPart1.text = origCurrentStr
		event.sleep(0.05)
		workspace:draw()
	end

	function tooManyNumbers()
		local c = 0
		local warningMessageBackground = workspace:addChild(GUI.panel(1 , 14, workspace.width, 4,	0xff7900))
		local warningMessage = workspace:addChild(GUI.text(1, 1, 0xffffff, localization.tooManyNumbers))
		warningMessage.localX = number.round(warningMessageBackground.width / 2 - warningMessage.width / 2)
		warningMessage.localY = number.round(warningMessageBackground.localY + 1)
		workspace:draw()
		
		while c < 5 do
			c = c + 1
			event.sleep(1)
		end
		
		c = 0
		
		warningMessageBackground:remove()
		warningMessage:remove()
	end

	keyPadButton1.onTouch = function()
		if string.len(currentEnteredPassword) < maxPasswordInputFieldNumbers then
			currentEnteredPassword = currentEnteredPassword .. "1"
			passwordFieldPart4.text = passwordFieldPart4.text .. "*"
			passwordFieldPart4.localX = number.round(passwordFieldPart2.x + passwordFieldPart2.width / 2 - passwordFieldPart4.width / 2)
			workspace:draw()
		else
			tooManyNumbers()
		end
	end

	keyPadButton2.onTouch = function()
		if string.len(currentEnteredPassword) < maxPasswordInputFieldNumbers then
			currentEnteredPassword = currentEnteredPassword .. "2"
			passwordFieldPart4.text = passwordFieldPart4.text .. "*"
			passwordFieldPart4.localX = number.round(passwordFieldPart2.x + passwordFieldPart2.width / 2 - passwordFieldPart4.width / 2)
			workspace:draw()
		else
			tooManyNumbers()
		end
	end

	keyPadButton3.onTouch = function()
		if string.len(currentEnteredPassword) < maxPasswordInputFieldNumbers then
			currentEnteredPassword = currentEnteredPassword .. "3"
			passwordFieldPart4.text = passwordFieldPart4.text .. "*"
			passwordFieldPart4.localX = number.round(passwordFieldPart2.x + passwordFieldPart2.width / 2 - passwordFieldPart4.width / 2)
			workspace:draw()
		else
			tooManyNumbers()
		end
	end

	keyPadButton4.onTouch = function()
		if string.len(currentEnteredPassword) < maxPasswordInputFieldNumbers then
			currentEnteredPassword = currentEnteredPassword .. "4"
			passwordFieldPart4.text = passwordFieldPart4.text .. "*"
			passwordFieldPart4.localX = number.round(passwordFieldPart2.x + passwordFieldPart2.width / 2 - passwordFieldPart4.width / 2)
			workspace:draw()
		else
			tooManyNumbers()
		end
	end

	keyPadButton5.onTouch = function()
		if string.len(currentEnteredPassword) < maxPasswordInputFieldNumbers then
			currentEnteredPassword = currentEnteredPassword .. "5"
			passwordFieldPart4.text = passwordFieldPart4.text .. "*"
			passwordFieldPart4.localX = number.round(passwordFieldPart2.x + passwordFieldPart2.width / 2 - passwordFieldPart4.width / 2)
			workspace:draw()
		else
			tooManyNumbers()
		end
	end

	keyPadButton6.onTouch = function()
		if string.len(currentEnteredPassword) < maxPasswordInputFieldNumbers then
			currentEnteredPassword = currentEnteredPassword .. "6"
			passwordFieldPart4.text = passwordFieldPart4.text .. "*"
			passwordFieldPart4.localX = number.round(passwordFieldPart2.x + passwordFieldPart2.width / 2 - passwordFieldPart4.width / 2)
			workspace:draw()
		else
			tooManyNumbers()
		end
	end

	keyPadButton7.onTouch = function()
		if string.len(currentEnteredPassword) < maxPasswordInputFieldNumbers then
			currentEnteredPassword = currentEnteredPassword .. "7"
			passwordFieldPart4.text = passwordFieldPart4.text .. "*"
			passwordFieldPart4.localX = number.round(passwordFieldPart2.x + passwordFieldPart2.width / 2 - passwordFieldPart4.width / 2)
			workspace:draw()
		else
			tooManyNumbers()
		end
	end

	keyPadButton8.onTouch = function()
		if string.len(currentEnteredPassword) < maxPasswordInputFieldNumbers then
			currentEnteredPassword = currentEnteredPassword .. "8"
			passwordFieldPart4.text = passwordFieldPart4.text .. "*"
			passwordFieldPart4.localX = number.round(passwordFieldPart2.x + passwordFieldPart2.width / 2 - passwordFieldPart4.width / 2)
			workspace:draw()
		else
			tooManyNumbers()
		end
	end

	keyPadButton9.onTouch = function()
		if string.len(currentEnteredPassword) < maxPasswordInputFieldNumbers then
			currentEnteredPassword = currentEnteredPassword .. "9"
			passwordFieldPart4.text = passwordFieldPart4.text .. "*"
			passwordFieldPart4.localX = number.round(passwordFieldPart2.x + passwordFieldPart2.width / 2 - passwordFieldPart4.width / 2)
			workspace:draw()
		else
			tooManyNumbers()
		end
	end

	keyPadButton0.onTouch = function()
		if string.len(currentEnteredPassword) < maxPasswordInputFieldNumbers then
			currentEnteredPassword = currentEnteredPassword .. "0"
			passwordFieldPart4.text = passwordFieldPart4.text .. "*"
			passwordFieldPart4.localX = number.round(passwordFieldPart2.x + passwordFieldPart2.width / 2 - passwordFieldPart4.width / 2)
			workspace:draw()
		else
			tooManyNumbers()
		end
	end

	keyPadButtonC.onTouch = function()
		-- Clear password.
		currentEnteredPassword = ""
		passwordFieldPart4.text = ""
		workspace:draw()
	end

	keyPadButtonL.onTouch = function()
		if locked == true then
			-- Check if the entered password is correct.
			local a1 = false
			for key, value in pairs(password) do
				if a1 == false then
					if currentEnteredPassword == value then
						sendingForceUnlockSignal = true
						authSucc()
						a1 = true
						workspace:draw()
					end
				end
			end
			if a1 == false then authFail() end
		else
			lock()
			sendingForceUnlockSignal = false
			workspace:draw()
		end
	end

	-- Draw the the active UI. This is used when the program is in the normal mode
	-- and waiting for PIN / fingerprint.
	function drawActiveUI()
		UIActive = true
		text1D.hidden = true
		backgroundD.hidden = true
		keyPadButton1D.hidden = true
		keyPadButton2D.hidden = true
		keyPadButton3D.hidden = true
		keyPadButton4D.hidden = true
		keyPadButton5D.hidden = true
		keyPadButton6D.hidden = true
		keyPadButton7D.hidden = true
		keyPadButton8D.hidden = true
		keyPadButton9D.hidden = true
		keyPadButton0D.hidden = true
		keyPadButtonLD.hidden = true
		keyPadButtonCD.hidden = true
		text2D.hidden = true
		text3D.hidden = true
		text4D.hidden = true
		authFieldPart1D.hidden = true
		authFieldPart2D.hidden = true
		authFieldPart3D.hidden = true
		authFieldPart4D.hidden = true
		authFieldPart5D.hidden = true
		authFieldPart6D.hidden = true
		authFieldPart7D.hidden = true
		authFieldPart8D.hidden = true
		authFieldPart9D.hidden = true
		authFieldPart10D.hidden = true
		authFieldPart11D.hidden = true
		passwordFieldPart1D.hidden = true
		passwordFieldPart2D.hidden = true
		passwordFieldPart3D.hidden = true
		passwordFieldPart4D.hidden = true
		
		text2.hidden = false
		text3.hidden = false
		text4.hidden = false
		workspace:draw()
	end

	-- Draw inactive UI. This happens when the authenticaion was successfull
	-- and the program is waiting for lock command or timer. Only the lock
	-- button is active.
	function drawInactiveUI(l)
		UIActive = false
		text1D.hidden = false
		backgroundD.hidden = false
		keyPadButton1D.hidden = false
		keyPadButton2D.hidden = false
		keyPadButton3D.hidden = false
		keyPadButton4D.hidden = false
		keyPadButton5D.hidden = false
		keyPadButton6D.hidden = false
		keyPadButton7D.hidden = false
		keyPadButton8D.hidden = false
		keyPadButton9D.hidden = false
		keyPadButton0D.hidden = false
		keyPadButtonCD.hidden = false
		text2D.hidden = false
		text3D.hidden = false
		text4D.hidden = false
		authFieldPart1D.hidden = false
		authFieldPart2D.hidden = false
		authFieldPart3D.hidden = false
		authFieldPart4D.hidden = false
		authFieldPart5D.hidden = false
		authFieldPart6D.hidden = false
		authFieldPart7D.hidden = false
		authFieldPart8D.hidden = false
		authFieldPart9D.hidden = false
		authFieldPart10D.hidden = false
		authFieldPart11D.hidden = false
		passwordFieldPart1D.hidden = false
		passwordFieldPart2D.hidden = false
		passwordFieldPart3D.hidden = false
		passwordFieldPart4D.hidden = false
		
		if l == true then
			keyPadButtonLD.hidden = false
		end
		
		text2.hidden = true
		text3.hidden = true
		text4.hidden = true
		workspace:draw()
	end

	function offlineMessage(b)
		if offlineMessageAlreadyShown ~= b then
		if offlineMessageAlreadyShown == false then
			offlineMessageAlreadyShown = true
			drawInactiveUI(true)
			warningMessageBackgroundOM.hidden = false
			warningMessageOM.hidden = false
			text2D.hidden = true
			text3D.hidden = true
			text4D.hidden = true
			workspace:draw()
		else
			offlineMessageAlreadyShown = false
			-- background:remove()
			text2D.hidden = false
			text3D.hidden = false
			text4D.hidden = false
			drawActiveUI()
			warningMessageBackgroundOM.hidden = true
			warningMessageOM.hidden = true
			workspace:draw()
		end
		end
	end

	function authSucc()
		-- GUI.alert("here")
		locked = false
		pcall(rs.setOutput, authSuccSide, 255)
		if sendingForceUnlockSignal == true then
			if forceUnlockSide ~= 6 then pcall(rs.setOutput, forceUnlockSide, 255) end
		end
		computer.beep(2000)
		drawInactiveUI()
		text2D.hidden = true
		text3D.hidden = true
		text4D.hidden = true
		
		textStatus.hidden = false
		textStatus.text = localization.accessAllowed
		textStatus.localX = number.round(workspace.width / 2 - unicode.len(textStatus.text) / 2)
		workspace:draw()
		event.sleep(0.5)
		
		-- Skip the animation if the corresponding variable is set.
		if disableAuthAnimation == false then
			textStatus.hidden = true
			workspace:draw()
			event.sleep(0.5)
			
			textStatus.hidden = false
			workspace:draw()
			event.sleep(0.5)
			
			textStatus.hidden = true
			workspace:draw()
			event.sleep(0.5)
			
			textStatus.hidden = false
			workspace:draw()
			event.sleep(0.5)
			
			textStatus.hidden = true
			workspace:draw()
			event.sleep(0.5)
			
			textStatus.hidden = false
			workspace:draw()
			event.sleep(5)
		else
			event.sleep(0.5)
		end
		
		textStatus.hidden = true
		text2D.hidden = false
		text3D.hidden = false
		text4D.hidden = false
		
		currentEnteredPassword = ""
		passwordFieldPart4.text = ""
		keyPadButtonL.text = "L"
		workspace:draw()
	end

	function authFail()
		text2.hidden = true
		text3.hidden = true
		text4.hidden = true
		
		textStatus.hidden = false
		textStatus.text = localization.noMatchesFound
		textStatus.localX = number.round(workspace.width / 2 - unicode.len(textStatus.text) / 2)
		workspace:draw()

		pcall(rs.setOutput, authFailSide, 255)
		local background = workspace:addChild(GUI.panel(1, 1, workspace.width, workspace.height, 0xff7900))
		local warningMessageBackground = workspace:addChild(GUI.panel(1 , 14, workspace.width, 5,	0xff0000))
		local warningMessage = workspace:addChild(GUI.text(1, 1, 0xffffff, localization.accessDenied))
		warningMessage.localX = number.round(warningMessageBackground.width / 2 - warningMessage.width / 2)
		warningMessage.localY = number.round(warningMessageBackground.localY + 2)
		workspace:draw()
		computer.beep(1000)
		event.sleep(0.05)
		background:remove()
		warningMessageBackground:remove()
		warningMessage:remove()
		local warningMessageBackground = workspace:addChild(GUI.panel(1 , 14, workspace.width, 5,	0xff7900))
		local warningMessage = workspace:addChild(GUI.text(1, 1, 0xffffff, localization.accessDenied))
		warningMessage.localX = number.round(warningMessageBackground.width / 2 - warningMessage.width / 2)
		warningMessage.localY = number.round(warningMessageBackground.localY + 2)
		workspace:draw()
		event.sleep(0.05)
		warningMessageBackground:remove()
		warningMessage:remove()
		
		local background = workspace:addChild(GUI.panel(1, 1, workspace.width, workspace.height, 0xff7900))
		local warningMessageBackground = workspace:addChild(GUI.panel(1 , 14, workspace.width, 5,	0xff0000))
		local warningMessage = workspace:addChild(GUI.text(1, 1, 0xffffff, localization.accessDenied))
		warningMessage.localX = number.round(warningMessageBackground.width / 2 - warningMessage.width / 2)
		warningMessage.localY = number.round(warningMessageBackground.localY + 2)
		workspace:draw()
		computer.beep(1000)
		event.sleep(0.05)
		background:remove()
		warningMessageBackground:remove()
		warningMessage:remove()
		local warningMessageBackground = workspace:addChild(GUI.panel(1 , 14, workspace.width, 5,	0xff7900))
		local warningMessage = workspace:addChild(GUI.text(1, 1, 0xffffff, localization.accessDenied))
		warningMessage.localX = number.round(warningMessageBackground.width / 2 - warningMessage.width / 2)
		warningMessage.localY = number.round(warningMessageBackground.localY + 2)
		workspace:draw()
		event.sleep(0.05)
		warningMessageBackground:remove()
		warningMessage:remove()
		
		local background = workspace:addChild(GUI.panel(1, 1, workspace.width, workspace.height, 0xff7900))
		local warningMessageBackground = workspace:addChild(GUI.panel(1 , 14, workspace.width, 5,	0xff0000))
		local warningMessage = workspace:addChild(GUI.text(1, 1, 0xffffff, localization.accessDenied))
		warningMessage.localX = number.round(warningMessageBackground.width / 2 - warningMessage.width / 2)
		warningMessage.localY = number.round(warningMessageBackground.localY + 2)
		workspace:draw()
		computer.beep(1000)
		event.sleep(0.05)
		background:remove()
		warningMessageBackground:remove()
		warningMessage:remove()
		local warningMessageBackground = workspace:addChild(GUI.panel(1 , 14, workspace.width, 5,	0xff7900))
		local warningMessage = workspace:addChild(GUI.text(1, 1, 0xffffff, localization.accessDenied))
		warningMessage.localX = number.round(warningMessageBackground.width / 2 - warningMessage.width / 2)
		warningMessage.localY = number.round(warningMessageBackground.localY + 2)
		workspace:draw()
		event.sleep(0.05)
		
		-- Skip the animation if the corresponding variable is set.
		if disableAuthAnimation == false then
			local c = 0
			
			while c < 5 do
				c = c + 1
				event.sleep(1)
			end
			
			c = 0
		else
			event.sleep(1)
		end
		
		text2.hidden = false
		text3.hidden = false
		text4.hidden = false
		textStatus.hidden = true
		currentEnteredPassword = ""
		passwordFieldPart4.text = ""
		pcall(rs.setOutput, authFailSide, 0)
		warningMessageBackground:remove()
		warningMessage:remove()
		workspace:draw()
	end

	function lock()
		-- Enable the lock. Removes the redstone signal and draws active GUI.
		locked = true
		pcall(rs.setOutput, authSuccSide, 0)
		if sendingForceUnlockSignal == true then
			if forceUnlockSide ~= 6 then pcall(rs.setOutput, forceUnlockSide, 0) end
		end
		textStatus.hidden = false
		textStatus.text = localization.locking
		textStatus.localX = number.round(workspace.width / 2 - unicode.len(textStatus.text) / 2)
		workspace:draw()
		drawActiveUI()
		keyPadButtonL.text = "►"
		textStatus.hidden = true
		workspace:draw()
	end

	-- Centrize some more objects.
	text1.localX = number.round(workspace.width / 2 - text1.width / 2)
	text1D.localX = number.round(workspace.width / 2 - text1.width / 2)
	textStatus.hidden = true
	warningMessageBackgroundOM.hidden = true
	warningMessageOM.hidden = true
	drawActiveUI()

	local time1 = computer.uptime()

	-- Check whatever its the first start of the app, is settings present, apply them and start the program.
	if not fs.exists(settingsFile) then
		setupShouldLoad = true
		firstSetup = true
	else
		loadSettings()
		if settingsInvalid == true then 
			GUI.alert(localization.errorMassiv.startInterrupted,
				errorTable
			)
			setupShouldLoad = true
		else
			firstSetup = false
			screen.setResolution(width, height)
			saveSettings()
		end
	end

	-- GUI.alert(setupShouldLoad)
	
	if setupShouldLoad == true then
		-- Load the greetings and setup windows. This happens if either the user holds ALT on the start
		-- or the program detected an invalid configuration.
		-- if firstSetup == true then
		local greetingTextLines = localization.greetingTextLines
	
		-- Build GUI of the greetings page.
		local greetingText1 = windowSetup:addChild(GUI.text(3, 2, 0x000000, greetingTextLines[1]))
		local greetingText2 = windowSetup:addChild(GUI.text(3, 2, 0x000000, greetingTextLines[2]))
		local greetingText3 = windowSetup:addChild(GUI.text(3, 2, 0x000000, greetingTextLines[3]))
		local greetingText4 = windowSetup:addChild(GUI.text(3, 2, 0x000000, greetingTextLines[4]))
		local greetingText5 = windowSetup:addChild(GUI.text(3, 2, 0xff0000, greetingTextLines[5]))
		local greetingText6 = windowSetup:addChild(GUI.text(3, 2, 0xff0000, greetingTextLines[6]))
		local greetingsButtonNext = windowSetup:addChild(GUI.button(2, 2, 24, 3, 0xFFFFFF, 0x555555, 0x880000, 0xFFFFFF, localization.next))
		greetingsButtonNext.onTouch = function()
			if greetingsButtonNext then greetingsButtonNext.hidden = true end
			if greetingText1 then greetingText1.hidden = true end
			if greetingText2 then greetingText2.hidden = true end
			if greetingText3 then greetingText3.hidden = true end
			if greetingText4 then greetingText4.hidden = true end
			if greetingText5 then greetingText5.hidden = true end
			if greetingText6 then greetingText6.hidden = true end
			drawSetupUI()
		end
		
		-- Calculate objects position and centrize them...
		local mostLongStrLength = 0

		if unicode.len(greetingText1.text) > mostLongStrLength then mostLongStrLength = unicode.len(greetingText1.text) end
		if unicode.len(greetingText2.text) > mostLongStrLength then mostLongStrLength = unicode.len(greetingText2.text) end
		if unicode.len(greetingText3.text) > mostLongStrLength then mostLongStrLength = unicode.len(greetingText3.text) end
		if unicode.len(greetingText4.text) > mostLongStrLength then mostLongStrLength = unicode.len(greetingText4.text) end
		if unicode.len(greetingText5.text) > mostLongStrLength then mostLongStrLength = unicode.len(greetingText5.text) end
		if unicode.len(greetingText6.text) > mostLongStrLength then mostLongStrLength = unicode.len(greetingText6.text) end

		greetingText1.localX = number.round(windowSetup.width / 2 - mostLongStrLength / 2)
		greetingText1.localY = number.round(windowSetup.height / 2 - (greetingText1.height + greetingText2.height + greetingText3.height + greetingText4.height + greetingText5.height + greetingText6.height + 1) / 2)
		greetingText2.localX = greetingText1.localX
		greetingText2.localY = greetingText1.localY + 1
		greetingText3.localX = greetingText1.localX
		greetingText3.localY = greetingText2.localY + 1
		greetingText4.localX = greetingText1.localX
		greetingText4.localY = greetingText3.localY + 1
		greetingText5.localX = greetingText1.localX
		greetingText5.localY = greetingText4.localY + 2
		greetingText6.localX = greetingText1.localX
		greetingText6.localY = greetingText5.localY + 1
		greetingsButtonNext.localX = number.round(windowSetup.width / 2 - greetingsButtonNext.width / 2)
		greetingsButtonNext.localY = windowSetup.height - greetingsButtonNext.height - 2
		  
		-- Update screen.
		workspaceSetup:draw()
	else
		-- Normal start of the app. Change screen resolution, reset redstone outputs, in the case if they
		-- were not correctly reset before, draw the code lock GUI and start listening to events.
		screen.setResolution(width, height)
		if windowSetup then windowSetup:remove() end
		pcall(rs.setOutput, authSuccSide, 0)
		pcall(rs.setOutput, authFailSide, 0)
		if forceUnlockSide ~= 6 then pcall(rs.setOutput, forceUnlockSide, 0) end
		
		
		
		-- Prepare workspace and create event handlers. The main logic of the app is stored here.
		local mainLoop = event.addHandler(function()
			-- GUI.alert(safersGetInput(onlineSide)[2] )
			-- Check whatever the code lock should be online
			if safersGetInput(onlineSide)[2] > 0 or onlineSide == 6 then
				offlineMessage(false)
				lockOnce = false
				-- GUI.alert(safersGetInput(forceUnlockSide)[2])
				if safersGetInput(forceUnlockSide)[2] > 6 and sendingForceUnlockSignal == false then
					if unlockOnce == false then
						unlockOnce = true
						authSucc()
						text3D.text = " "
						text4D.text = " "
						keyPadButtonLD.hidden = false
						workspace:draw()
					end
				else
					if unlockOnce == true then
						lock()
						unlockOnce = false
					end
					
					
					
					-- Check whatever this computer itself sending the force unlock signal.
					if locked == false and UIActive == false and autoLockTime ~= "0" and (safersGetInput(blockAutoLockTimerSide)[2] == 0 or blockAutoLockTimerSide == 6) then
						-- Timer of the autolock feature. Most probably it could be done more easy but well...
						if computer.uptime() - time1 < 1 then
						
						else
							time1 = time1 + 1
							autoLockTimer = autoLockTimer - 1
						end
						text3D.text = localization.autolockIn .. number.round(tonumber(autoLockTimer)) .. "."
						text4D.text = localization.lToLock
						workspace:draw()
						
						-- Lock once the timer is expired.
						if autoLockTimer == 0 then
							lock()
							sendingForceUnlockSignal = false
						end
					else
						-- if autoLockTime == "0" then GUI.alert(autoLockTime) end
						if locked == false and autoLockTime == "0" then
							text3D.text = localization.lToLock
							text4D.text = " "
						end
						
						-- Stop and reset the autolock timer if a corresponding signal has been put.
						-- GUI.alert(safersGetInput(blockAutoLockTimerSide)[2])
						if safersGetInput(blockAutoLockTimerSide)[2] > 0 then
							text3D.text = localization.autoLockTimerStopped
							
						end
						
						-- Update display.
						workspace:draw()
						autoLockTimer = autoLockTime
						time1 = computer.uptime()
					end		
				
				end
			else
				if lockOnce == false then
					lockOnce = true
					lock()
				end
				offlineMessage(true)
			end
		end, 0.1)
		
		-- Check if the user, that touched the screen, is an allowed user for bio auth.
		local touchListener = event.addHandler(function(e1, e2, e3, e4, e5, e6)
			if e1 == "touch" and e3 > authFieldPart1.x and e3 < authFieldPart1.x + authFieldPart1.width and e4 > authFieldPart1.y and e4 < authFieldPart11.y and UIActive == true then
				visualizeBioAuth()
				local a1 = false
				for key, value in pairs(trustedUser) do
					if a1 == false then
					if e6 == value then
						sendingForceUnlockSignal = true
						authSucc()
						a1 = true
						workspace:draw()
					end
				end
			end
			if a1 == false then authFail() end
			end
		end)
		
		-- Exit the app if space is pressed.
		event.addHandler(function(e1, e2, e3, e4)
			if e1 == "key_down" and e4 == 57 then
				event.removeHandler(mainLoop)
				event.removeHandler(touchListener)
				screen.setResolution(origWidth, origHeight)
				workspace:stop()
			end
		end)		
		
		workspace:draw()
		workspace:start()
	end

	if shouldNotStart == true then if windowSetup then windowSetup:remove() end end
end