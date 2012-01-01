(* Description: Dumping the audio stream of DVD chapters into MP3 files.
Author: Markus Kwaśnicki
Date: 2012-01-01 *)

property outputFolder : missing value
property propertyListFile : missing value
property dataStructure : missing value
property titleStructureSummary : missing value
property titleSummaryToChooseFrom : missing value

on run
	display dialog "Use as droplet only!" with title "Usage fail" buttons {"OK"} default button "OK" with icon 1
end run

on open droppedItems
	try
		(* Repeat with each dropped mounted DVD volume *)
		repeat with droppedItem in droppedItems
			(* Create output folder on the desktop for extracting the audio stream *)
			tell application "Finder"
				set newFolderName to missing value
				try
					set newFolderName to (droppedItem as text) -- Contains trailing colon
					set newFolderName to characters 1 through ((length of newFolderName) - 1) of newFolderName as text -- Cut of the trailing colon
					set outputFolder to (make new folder at (path to desktop folder from user domain) with properties {name:newFolderName}) as alias
				on error m number n
					if n = -48 then
						(* The new folder already exists *)
						set outputFolder to (path to desktop folder from user domain as text) & newFolderName & ":" as alias
					else
						error m number n
					end if
				end try
			end tell
			
			(* List information into a XML file *)
			set propertyListFile to (outputFolder as text) & "lsdvd.xml"
			set shellCommand to "/opt/local/bin/lsdvd -x -Ox '" & (POSIX path of droppedItem as text) & "' > " & (POSIX path of propertyListFile)
			do shell script shellCommand
			set propertyListFile to propertyListFile as alias
			
			(* Do something with the XML file output representing the data structure of the DVD *)
			parseDataStructure()
			summarizeTitles()
			makeItSo()
		end repeat
	on error m number n
		if n is -128 then
			-- User canceled
		else
			display dialog m with title n buttons {"OK"} default button "OK" with icon 0
		end if
	end try
end open

(* Subroutines *)
on parseDataStructure()
	set xmlData to missing value
	
	set fileHandle to open for access propertyListFile
	set xmlData to read fileHandle to eof
	close access fileHandle
	
	set dataStructure to parse XML xmlData
end parseDataStructure

on summarizeTitles()
	set titleStructureSummary to {}
	set titleSummaryToChooseFrom to {}
	
	repeat with element in (XML contents of dataStructure)
		set loopData to {numberOfTitle:missing value, lengthoftitle:missing value, chapterCount:missing value}
		
		if XML tag of element is equal to "track" then
			set track to XML contents of element
			set chapters to 0
			
			repeat with tag in track
				if XML tag of tag is equal to "ix" then
					set numberOfTitle of loopData to XML contents of tag as integer
				else if XML tag of tag is equal to "length" then
					set lengthoftitle of loopData to XML contents of tag as text
				else if XML tag of tag is equal to "chapter" then
					set chapters to chapters + 1
				end if
			end repeat
			
			set chapterCount of loopData to chapters
			copy loopData to end of titleStructureSummary
			set titleSummary to "Track " & numberOfTitle of loopData & " with length of " & lengthoftitle of loopData & " seconds in " & chapterCount of loopData & " chapters"
			copy titleSummary to end of titleSummaryToChooseFrom
		end if
	end repeat
end summarizeTitles

on makeItSo()
	choose from list titleSummaryToChooseFrom with title "Which DVD track to dump?"
	set chosenResult to result
	if chosenResult is not false then
		display dialog "About to dump audio stream! This will take a while." with title "Point of No Return" with icon 1
		
		set listPosition to word 2 of first item of chosenResult
		item listPosition of titleStructureSummary
		
		set chosenTitle to item listPosition of titleStructureSummary
		repeat with chapter from 1 to (chapterCount of chosenTitle)
			set currentTrackAviFile to POSIX path of outputFolder & "Track " & chapter & ".avi" -- POSIX path needed here
			set currentTrackMp3File to POSIX path of outputFolder & "Track " & chapter & ".mp3" -- POSIX path needed here
			
			set mencoderShellCommand to "/opt/local/bin/mencoder -oac mp3lame -lameopts preset=standard -chapter " & chapter & "-" & chapter & " -ovc frameno -o '" & currentTrackAviFile & "' dvd://" & (numberOfTitle of chosenTitle)
			set mplayerShellCommand to "/opt/local/bin/mplayer '" & currentTrackAviFile & "' -dumpaudio -dumpfile '" & currentTrackMp3File & "'"
			
			do shell script mencoderShellCommand
			do shell script mplayerShellCommand
			tell application "Finder" to delete POSIX file currentTrackAviFile as alias -- Move the temporary needed AVI file to the trash
		end repeat
		
		tell application "Finder" to delete propertyListFile -- Move the temporary property list file to the trash after all work is done
		display dialog "Audio stream was dumped successfully to your desktop!" with title "Well done" buttons {"OK"} default button "OK" with icon 1
	end if
end makeItSo

