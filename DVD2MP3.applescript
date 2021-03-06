(* Description: Dumping the audio stream of DVD chapters into MP3 files.
Author: Markus Kwaśnicki
Version: 201304141116 *)

property outputFolder : missing value
property propertyListFile : missing value
property dataStructure : missing value
property titleStructureSummary : missing value
property titleSummaryToChooseFrom : missing value
property titleWithLongestTrack : missing value

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

on humanReadableLengthOfTitle(lengthInSeconds)
	(* Input must be given of type text, 
	because english decimal separators are used by the XML output of lsdvd, 
	which need to be handled.
	Anyway output will be considered as format: hh:mm:ss *)
	
	set decimalSeparatorOffset to (offset of "." in lengthInSeconds)
	(* A clever test for the decimal separator issue *)
	if decimalSeparatorOffset > 0 and 0.0 as text is equal to "0,0" then
		set newLengthInSeconds to text 1 thru (decimalSeparatorOffset - 1) of lengthInSeconds & "," & text (decimalSeparatorOffset + 1) thru -1 of lengthInSeconds
	else
		set newLengthInSeconds to lengthInSeconds
	end if
	-- //
	
	set newLengthInSeconds to (round (newLengthInSeconds as real) rounding as taught in school)
	set secondsPart to newLengthInSeconds mod 60
	set minutesPart to (round newLengthInSeconds / 60 rounding down) as integer
	set hoursPart to (round minutesPart / 60 rounding down) as integer
	set minutesPart to minutesPart - hoursPart * 60
	
	set humanReadableLength to (text -2 thru -1 of ("00" & hoursPart)) & ":" & (text -2 thru -1 of ("00" & minutesPart)) & ":" & (text -2 thru -1 of ("00" & secondsPart)) -- Clever solution for leading zeros
	return humanReadableLength
end humanReadableLengthOfTitle

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
	
	set currentNativeLength to 0
	set previousNativeLength to 0
	
	repeat with element in (XML contents of dataStructure)
		set loopData to {numberOfTitle:missing value, lengthoftitle:missing value, chapterCount:missing value}
		
		if XML tag of element is equal to "track" then
			set track to XML contents of element
			set chapters to 0
			
			repeat with tag in track
				if XML tag of tag is equal to "ix" then
					set numberOfTitle of loopData to XML contents of tag as integer
				else if XML tag of tag is equal to "length" then
					set currentNativeLength to XML contents of tag as integer
					set lengthoftitle of loopData to humanReadableLengthOfTitle(XML contents of tag as text)
				else if XML tag of tag is equal to "chapter" then
					set chapters to chapters + 1
				end if
			end repeat
			
			set chapterCount of loopData to chapters
			copy loopData to end of titleStructureSummary
			set titleSummary to "Track " & numberOfTitle of loopData & " with length of " & lengthoftitle of loopData & " time in " & chapterCount of loopData & " chapters"
			copy titleSummary to end of titleSummaryToChooseFrom
			
			(* Which is the longest track? *)
			ignoring punctuation
				if currentNativeLength > previousNativeLength then
					set titleWithLongestTrack to titleSummary
					set previousNativeLength to currentNativeLength
				end if
			end ignoring
		end if
	end repeat
end summarizeTitles

on makeItSo()
	choose from list titleSummaryToChooseFrom with title "DVD track listing" with prompt "Which DVD track to dump?" default items {titleWithLongestTrack}
	set chosenResult to result
	if chosenResult is not false then
		
		(* Choosing encoding preset *)
		set presets to {"medium (good quality; VBR, 150-180 kbps)", ¬
			"standard (high quality; VBR, 170-210 kbps)", ¬
			"extreme (very high quality; VBR, 200-240 kbps)", ¬
			"insane (highest quality; CBR encoding, 320 kbps)"} -- Taken from mencoder's man page
		choose from list presets with title "Encoding quality" with prompt "Choose your desired encoding preset:" default items {item 2 of presets}
		set chosenPreset to result
		if chosenPreset is not false then
			set preset to first word of first item of chosenPreset
		else
			return -- End program due to lack of encoding preset
		end if
		(* End of choosing encoding preset *)
		
		display dialog "About to dump audio stream! This will take a while." with title "Point of No Return" with icon 1
		
		set listPosition to word 2 of first item of chosenResult
		item listPosition of titleStructureSummary
		
		set chosenTitle to item listPosition of titleStructureSummary
		repeat with chapter from 1 to (chapterCount of chosenTitle)
			set currentTrackAviFile to POSIX path of outputFolder & "Track " & listPosition & " - Chapter " & chapter & ".avi" -- POSIX path needed here
			set currentTrackMp3File to POSIX path of outputFolder & "Track " & listPosition & " - Chapter " & chapter & ".mp3" -- POSIX path needed here
			
			set mencoderShellCommand to "/opt/local/bin/mencoder -oac mp3lame -lameopts preset=" & preset & " -chapter " & chapter & "-" & chapter & " -ovc frameno -o '" & currentTrackAviFile & "' dvd://" & (numberOfTitle of chosenTitle)
			set mplayerShellCommand to "/opt/local/bin/mplayer '" & currentTrackAviFile & "' -dumpaudio -dumpfile '" & currentTrackMp3File & "'"
			
			do shell script mencoderShellCommand
			do shell script mplayerShellCommand
			
			tell application "Finder" to delete POSIX file currentTrackAviFile as alias -- Move the temporary needed AVI file to the trash
		end repeat
		
		tell application "Finder" to delete propertyListFile -- Move the temporary property list file to the trash after all work is done
		beep -- Notify by a sound
		display dialog "Audio stream was dumped successfully to your desktop!" with title "Well done" buttons {"OK"} default button "OK" with icon 1
	end if
end makeItSo

(* End of AppleScript *)

