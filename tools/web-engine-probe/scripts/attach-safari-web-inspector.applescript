on run argv
	if (count of argv) is not 1 then error "usage: attach-safari-web-inspector.applescript prepare|attach"
	set actionName to item 1 of argv as text
	if actionName is "prepare" then return my prepareInspectorWindow()
	if actionName is "attach" then return my attachInspectableTarget()
	error "unknown action: " & actionName
end run

on prepareInspectorWindow()
	tell application "Safari" to activate
	delay 1
	tell application "System Events"
		tell process "Safari"
			set frontmost to true
			if not (exists menu bar item "Develop" of menu bar 1) then
				error "Safari Develop menu is unavailable"
			end if
			click menu bar item "Develop" of menu bar 1
			delay 0.2
			set developMenu to menu 1 of menu bar item "Develop" of menu bar 1
			set inspectItem to missing value
			repeat with candidate in menu items of developMenu
				set candidateName to name of candidate as text
				if candidateName contains "Inspect Apps and Devices" then
					set inspectItem to candidate
				end if
			end repeat
			if inspectItem is missing value then
				error "Safari Inspect Apps and Devices menu item is unavailable"
			end if
			click inspectItem
			delay 1
			return "prepare=ok windows=" & (name of every window as text)
		end tell
	end tell
end prepareInspectorWindow

on attachInspectableTarget()
	tell application "Safari" to activate
	tell application "System Events"
		tell process "Safari"
			set frontmost to true
			set attachResult to ""
			repeat with attemptNumber from 1 to 40
				click menu bar item "Develop" of menu bar 1
				delay 0.15
				set developMenu to menu 1 of menu bar item "Develop" of menu bar 1
				set attachResult to my findInspectableTarget(developMenu)
				if attachResult is not "" then exit repeat
				key code 53
				delay 0.25
			end repeat
			if attachResult is "" then error "Alula Web Probe did not appear in Safari Develop menu"
			delay 1
			return "attach=ok target=" & attachResult & " windows=" & (name of every window as text)
		end tell
	end tell
end attachInspectableTarget

on findInspectableTarget(menuReference)
	tell application "System Events"
		tell process "Safari"
			repeat with menuItemReference in menu items of menuReference
				set itemTitle to ""
				try
					set itemTitle to name of menuItemReference as text
				end try
				log "Safari Develop item: " & itemTitle
				if itemTitle contains "Alula Web Probe" or itemTitle contains "web_engine_probe" then
					click menuItemReference
					return itemTitle
				end if
				try
					if exists menu 1 of menuItemReference then
						set nestedResult to my findInspectableTarget(menu 1 of menuItemReference)
						if nestedResult is not "" then return nestedResult
					end if
				end try
			end repeat
		end tell
	end tell
	return ""
end findInspectableTarget
