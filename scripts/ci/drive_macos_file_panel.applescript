-- Answers the native Open and Save panels that
-- integration_test/macos_file_picker_sandbox_test.dart opens, in that order.
-- The test runs inside the sandboxed app and can't click a panel it opened
-- itself, so CI's test-macos job starts this in the background first:
--
--   osascript scripts/ci/drive_macos_file_panel.applescript <probe dir>
--
-- Each panel is a sheet on the app's window (file_picker uses
-- beginSheetModal). For each one: wait for the sheet, open "Go to Folder"
-- (Cmd+Shift+G), type the path, press Return to go there, then Return again
-- to confirm Open/Save. Needs Accessibility permission for osascript, which
-- GitHub's macOS runner images grant for UI testing.

on run argv
	set probeDir to item 1 of argv
	my answerSheet(probeDir & "/probe.pem", "Open")
	-- The Save panel already has the file name filled in (saved.txt), so
	-- only the folder needs to be typed.
	my answerSheet(probeDir, "Save")
	log "Both panels answered"
end run

on answerSheet(targetPath, label)
	set appProc to my waitForSheet(label)
	log label & " sheet appeared"
	tell application "System Events"
		set frontmost of appProc to true
		delay 1
		keystroke "g" using {command down, shift down}
		delay 1.5
		keystroke targetPath
		delay 1
		key code 36 -- Return: go to the typed path
		delay 1.5
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
	error label & " sheet did not close"
end answerSheet

on waitForSheet(label)
	-- Up to 10 minutes: the first macOS build in a CI job is slow.
	repeat 1200 times
		tell application "System Events"
			set procs to (every process whose name starts with "NATS Client")
			if procs is not {} then
				set appProc to item 1 of procs
				try
					if exists sheet 1 of window 1 of appProc then return appProc
				end try
			end if
		end tell
		delay 0.5
	end repeat
	error "Timed out waiting for the " & label & " sheet"
end waitForSheet
