-- Answers the native Open and Save panels that
-- integration_test/macos_file_picker_sandbox_test.dart opens, in that order.
-- The test runs inside the sandboxed app and can't click a panel it opened
-- itself, so CI's test-macos job starts this in the background first:
--
--   osascript scripts/ci/drive_macos_file_panel.applescript <probe dir> <screenshot dir>
--
-- Each panel is a sheet on the app's window (file_picker uses
-- beginSheetModal). For each one: wait for the sheet, open "Go to Folder"
-- (Cmd+Shift+G), type the path, press Return to go there, then Return again
-- to confirm Open/Save. Needs Accessibility permission for osascript.
--
-- Screenshots of each step go to <screenshot dir>, which CI uploads as an
-- artifact, so a failed run shows what was actually on screen.

property shotDir : ""

on run argv
	set probeDir to item 1 of argv
	set shotDir to item 2 of argv
	tell application "System Events" to set uiEnabled to UI elements enabled
	log "UI scripting enabled: " & uiEnabled
	my answerSheet(probeDir & "/probe.pem", "Open")
	-- The Save panel already has the file name filled in (saved.txt), so
	-- only the folder needs to be typed.
	my answerSheet(probeDir, "Save")
	log "Both panels answered"
end run

on shoot(shotName)
	try
		do shell script "screencapture -x " & quoted form of (shotDir & "/" & shotName & ".png")
	on error errMsg
		log "screencapture failed: " & errMsg
	end try
end shoot

on answerSheet(targetPath, label)
	set appProc to my waitForSheet(label)
	log label & " sheet appeared"
	my shoot(label & "-1-appeared")
	tell application "System Events"
		set frontmost of appProc to true
		delay 1
		keystroke "g" using {command down, shift down}
		delay 1.5
		keystroke targetPath
		delay 1
		my shoot(label & "-2-path-typed")
		key code 36 -- Return: go to the typed path
		delay 1.5
		my shoot(label & "-3-navigated")
		key code 36 -- Return: confirm Open / Save
	end tell
	log label & " sheet answered with " & targetPath
	-- Wait for this sheet to close, so the next waitForSheet can't mistake
	-- it for the following panel.
	repeat 60 times
		tell application "System Events"
			if not (exists sheet 1 of window 1 of appProc) then return
		end tell
		delay 0.5
	end repeat
	my shoot(label & "-4-still-open")
	error label & " sheet did not close"
end answerSheet

on waitForSheet(label)
	-- Up to 10 minutes: the first macOS build in a CI job is slow. Logs
	-- what it can see every 30s, so a sheet it fails to recognize shows up
	-- in the log rather than as silence.
	repeat with i from 1 to 1200
		tell application "System Events"
			set procs to (every process whose name starts with "NATS Client")
			if procs is not {} then
				set appProc to item 1 of procs
				try
					if exists sheet 1 of window 1 of appProc then return appProc
				end try
			end if
		end tell
		if i mod 60 = 0 then my describe(label)
		delay 0.5
	end repeat
	my shoot(label & "-timeout")
	error "Timed out waiting for the " & label & " sheet"
end waitForSheet

on describe(label)
	try
		tell application "System Events"
			set procs to (every process whose name starts with "NATS Client")
			if procs is {} then
				log "Waiting for " & label & ": no NATS Client process yet"
				return
			end if
			set appProc to item 1 of procs
			set winCount to count of windows of appProc
			set summary to "Waiting for " & label & ": " & winCount & " window(s)"
			repeat with w in windows of appProc
				set summary to summary & " [" & (name of w as text) & ", role " & (role of w) & ", " & (count of sheets of w) & " sheet(s)]"
			end repeat
			log summary
		end tell
	on error errMsg
		log "Waiting for " & label & ": could not inspect UI: " & errMsg
	end try
	my shoot(label & "-waiting")
end describe
