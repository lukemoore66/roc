function Encode-Segments ($arrEncCmds, $hashCodecs, $arrOutputFiles) {
	#if there is only one encode command
	if (@($arrEncCmds).Count -le 1) {
		#skip the file
		Write-Host "Input File Does Not Appear To Have Any Valid Segments And/Or Chapters.`nThis File Will Be Skipped.`n"
		
		#tidy up temp files
		Cleanup-Files $arrOutputFiles $strChapterFile $strMmgOutputFile $arrSubInfo
		
		#increment the file counter
		$script:intFileCounter++
		
		#continue the file processing loop
		continue
	}
	
	Write-Host "Encoding...`nPress Ctrl + c to exit.`n"
	
	$floatSeekOffset = 15.0
	$intTotalChunks = $arrEncCmds.Count
	
	$intCounter = 1
	$floatProg = 0.0
	foreach ($hashCmd in $arrEncCmds) {
		$floatStartTime = $hashCmd.Start
		$floatEndTime = $hashCmd.End
		$floatDuration = $floatEndTime - $floatStartTime
		$strOutputFile = $arrOutputFiles[$intCounter - 1]

		$strDuration = ConvertTo-Sexagesimal $floatDuration
		$strStartProg = ConvertTo-Sexagesimal $floatProg
		$floatProg = $floatProg + $floatDuration
		$strEndProg = ConvertTo-Sexagesimal $floatProg

		if ($hashCmd.File -eq $objFile.FullName) {
			$strSource = "Main File"
		}
		else {
			$strSource = "External File"
		}

		$floatHybridSeek = $floatStartTime - $floatSeekOffset
		if ($floatHybridSeek -le 0.0) {
			$floatStartTime = 0.0
		}

		Write-Host ("Processing Segment $intCounter of $intTotalChunks Duration: $strDuration Output Range: " + `
		"$strStartProg - $strEndProg Source: $strSource")
		
		#avoid seeking when possible, as ffmpeg seems to be buggy sometimes
		if ($floatStartTime -eq 0.0) {
			.\bin\ffmpeg.exe -v error -stats -y -i $hashCmd.File -t $floatDuration `
			-map 0 -map_chapters -1 -c:v $hashCodecs.Video -c:a $hashCodecs.Audio -c:s $hashCodecs.Sub -preset:v $strPreset -crf $intCrf `
			-x264opts stitchable=1 -max_muxing_queue_size 4000 -b:a $hashCodecs.AudioBitrate $strOutputFile
		}
		#otherwise, we have to use seeking, seek a bit backwards, and decode that bit until we get to the start point
		else {
			.\bin\ffmpeg.exe -v error -stats -y -ss $floatHybridSeek -i $hashCmd.File -ss $floatSeekOffset -t $floatDuration `
			-map 0 -map_chapters -1 -c:v $hashCodecs.Video -c:a $hashCodecs.Audio -c:s $hashCodecs.Sub -preset:v $strPreset -crf $intCrf `
			-x264opts stitchable=1 -max_muxing_queue_size 4000 -b:a $hashCodecs.AudioBitrate $strOutputFile
		}

		$intCounter++
	}
}

function Get-EncCmdsAggressive ($xmlChapterInfo, $hashSegmentFiles, $floatOffsetTime) {
	#aggressive mode encode instructions
	#initialize an array for storing encode instructions
	$arrEncCmds = @()
	
	#for each chapter atom
	foreach ($nodeChapAtom in $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom) {
		#if the chapter has an sid
		if ($nodeChapAtom.ChapterSegmentUID) {
			#get the filename
			$strFilePath = $hashSegmentFiles.($nodeChapAtom.ChapterSegmentUID.'#text')
		}
		#else it does not have an sid
		else {
			#use the main filename
			$strFilePath = $objFile.FullName
		}
		
		#add the file path and chapter start / finish times to the encode instructions array
		$arrEncCmds = $arrEncCmds + @{
			File = $strFilePath
			Start = (ConvertFrom-Sexagesimal $nodeChapAtom.ChapterTimeStart) + $floatOffsetTime
			End = (ConvertFrom-Sexagesimal $nodeChapAtom.ChapterTimeEnd) - $floatOffsetTime
		}
	}
	
	return $arrEncCmds
}

function Fix-ChapAggressive ($xmlChapterInfo, $floatOffsetTime) {
	#aggressive mode fix chapters
	#for each chapter atom
	$intCount = 0
	$floatProgress = 0.0
	foreach ($nodeChapAtom in $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom) {
			#get the chapter's duration
			$floatChapDur = (ConvertFrom-Sexagesimal $nodeChapAtom.ChapterTimeEnd) - (ConvertFrom-Sexagesimal $nodeChapAtom.ChapterTimeStart)
		
			#set the chapter start to the current progress
			$nodeChapAtom.ChapterTimeStart = ConvertTo-Sexagesimal ($floatProgress + $floatOffsetTime)
			
			#add the chapter duration to the current progress
			$floatProgress = $floatProgress + $floatChapDur 
			
			#set the chapter end time to the current progress, minus the correction
			$nodeChapAtom.ChapterTimeEnd = ConvertTo-Sexagesimal ($floatProgress - $floatOffsetTime)
			
		#if the chapter has sid info
		if ($nodeChapAtom.ChapterSegmentUID) {
			#remove the sid info from the chapter
			$nodeChapAtom.RemoveChild($nodeChapAtom.ChapterSegmentUID) | Out-Null
		}
		
		#set a new UID for the current chapter atom
		if (!$nodeChapAtom.ChapterUID) {
			$nodeChapAtom.AppendChild($xmlChapterInfo.CreateElement('ChapterUID')) | Out-Null
		}
		$nodeChapAtom.ChapterUID = Generate-UID
		
		$intCount++
	}
	
	#set a new UID for this chapter edition
	if (!$xmlChapterInfo.Chapters.EditionEntry.EditionUID) {
		$xmlChapterInfo.Chapters.EditionEntry.AppendChild($xmlChapterInfo.CreateElement('EditionUID')) | Out-Null
	}
	$xmlChapterInfo.Chapters.EditionEntry.EditionUID = Generate-UID
	
	#set the chapters to not be ordered chapters
	$xmlChapterInfo.Chapters.EditionEntry.EditionFlagOrdered = '0'
	
	return $xmlChapterInfo
}

function Merge-Segments ($arrOutputFiles, $strMmgOutputFile, $strChapterFile, $strInputFile) {
	#escape backticks if needed
	$strMmgOutputFile = Escape-Backticks $strMmgOutputFile
	$strChapterFile = Escape-Backticks $strChapterFile
	$strInputFile = Escape-Backticks $strInputFile
	$arrEscOutputFiles = @()
	$arrOutputFiles | % {$arrEscOutputFiles += (Escape-Backticks $_)}
	
	#Make an expression string that mkvmerge can run
	Write-Host "Appending Segments..."
	$strMkvMerge = ".\bin\mkvmerge.exe --output ""$strMmgOutputFile"" --chapters ""$strChapterFile"" " + `
	"-A -D -S -B --no-chapters ""$strInputFile"" """ + ($arrEscOutputFiles -join """ + """) + """ | Out-Null"
	
	#Use mkvmerge to join all of the output files
	Invoke-Expression $strMkvMerge
}

function Remux-Subs ($strOutputFile, $arrSubInfo, $strMmgOutputFile) {
	#if there are no subtitles
	if ($arrSubInfo.Count -eq 0) {
		#simply move / rename the the file
		Move-Item -Force -LiteralPath $strMmgOutputFile -Destination $strOutputFile
		
		#return to the main script
		return
	}
	
	#escape backticks if needed
	$strOutputFile = Escape-Backticks $strOutputFile
	$strMmgOutputFile = Escape-Backticks $strMmgOutputFile
	
	$arrSubFiles = @()
	foreach ($hashSubInfo in $arrSubInfo) {
		#escape backticks if needed
		$strSubFile = Escape-Backticks $hashSubInfo.File
		
		$arrSubFiles = $arrSubFiles + $hashSubInfo.File
		$strMkvExt = ".\bin\mkvextract.exe ""$strMmgOutputFile"" tracks " + $hashSubInfo.Index + ":""" + $strSubFile + `
		""" | Out-Null"
		
		Invoke-Expression $strMkvExt
	}
	
	#escape backticks if needed
	$arrEscSubFiles = @()
	$arrSubFiles | % {$arrEscSubFiles += (Escape-Backticks $_)}
	
	$strMkvMerge = ".\bin\mkvmerge.exe --output ""$strOutputFile"" -S ""$strMmgOutputFile"" """ + ($arrEscSubFiles -join """ """) + `
	""" | Out-Null"
	
	Write-Host "Remuxing Subtitles..."
	
	#Use mkvmerge to join all of the output files
	Invoke-Expression $strMkvMerge
}

function Get-SubInfo ($strMmgOutputFile, $strTempPath) {
	#get the needed info from the mkvmerge output file
	$jsonFileInfo = .\bin\mkvmerge -J $strMmgOutputFile | ConvertFrom-Json
	
	#go through each stream and extract subtitles
	$intCount = 0
	$arrSubInfo = @()
	foreach ($jsonProperties in $jsonFileInfo.tracks.properties) {
		if ($jsonProperties.codec_id -eq 'S_TEXT/ASS') {
			$arrSubInfo = $arrSubInfo + @{
				Index = $intCount
				File = $strTempPath + '\' + (Generate-RandomString) + '.ass'
			}
		}
		
		if ($jsonProperties.codec_id -eq 'S_TEXT/UTF8') {
			$arrSubInfo = $arrSubInfo + @{
				Index = $intCount
				File = $strTempPath + '\' + (Generate-RandomString) + '.srt'
			}
		}
		
		$intCount++
	}
	
	return $arrSubInfo
}

function Show-Version ($SetupOnly, $RocSession, $strVersion) {
	if ($SetupOnly) {
	Set-Variable -Name RocSession -Value $true -Scope 2
	
	Write-Host "(roc) - Remove Ordered Chapters $strVersion By d3sim8.`nType 'roc -Help' And Press Enter To Begin.`n"
	
	exit
	}
	else {
		if (!$RocSession) {
			Write-Host "(roc) - Remove Ordered Chapters $strVersion By d3sim8.`n"
		}
	}
}

function Get-EncodeCommands ($xmlChapterInfo, $hashSegmentFiles, $boolAggressive, $floatOffsetTime) {
	#if aggressive mode is enabled
	if ($boolAggressive) {
		#use it to generate encode commands instead
		return Get-EncCmdsAggressive $xmlChapterInfo $hashSegmentFiles $floatOffsetTime
	}
	
	#make an array of encode commands for ffmpeg to process
	#Initialize an array of encode commands
	$arrEncCmds = @()
	
	#Clear the start and end variables
	$floatEncStart = $null
	$floatEncEnd = $null

	#initialize an index counter to zero
	$intCount = 0
	#step through each ChapterAtom
	foreach ($nodeChapAtom in $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom) {
		#if the current chapter references a segment
		if ($nodeChapAtom.ChapterSegmentUID) {
			#get current chapters start time
			$floatEncStart = ConvertFrom-Sexagesimal $nodeChapAtom.ChapterTimeStart

			#get current chapter's end time
			$floatEncEnd = ConvertFrom-Sexagesimal $nodeChapAtom.ChapterTimeEnd

			#add start time, end time and file name encode list
			$arrEncCmds = $arrEncCmds + @{
				File = $hashSegmentFiles.($nodeChapAtom.ChapterSegmentUID.'#text')
				Start = $floatEncStart
				End = $floatEncEnd
			}

			#set encode start and end back to null
			$floatEncStart = $null
			$floatEncEnd = $null
		}
		#else the chapter is not ordered
		else {
			#if we are not on the first chapter
			if ($intCount -ne 0) {
				#if the previous chapter was ordered
				if ($xmlChapterInfo.Chapters.EditionEntry.ChapterAtom[$intCount - 1].ChapterSegmentUID) {
					#set encode start time to current chapter's start time
					$floatEncStart = ConvertFrom-Sexagesimal $nodeChapAtom.ChapterTimeStart
				}
			}
			#else we are on the first chapter
			else {
				#set the encode start time to the current chapter's start time
				$floatEncStart = ConvertFrom-Sexagesimal $nodeChapAtom.ChapterTimeStart
			}

			#if we are not on the last chapter
			if  ($intCount -ne ($xmlChapterInfo.Chapters.EditionEntry.ChapterAtom.Count - 1)) {
				#if the next chapter is going to be ordered
				if ($xmlChapterInfo.Chapters.EditionEntry.ChapterAtom[$intCount + 1].ChapterSegmentUID) {
					#set encode end time to current chapter's end time
					$floatEncEnd = ConvertFrom-Sexagesimal $nodeChapAtom.ChapterTimeEnd
				}
			}
			#else we are on the last chapter
			else {
				#set the encode end time to the end of the current chapter
				$floatEncEnd = ConvertFrom-Sexagesimal $nodeChapAtom.ChapterTimeEnd
			}

			#if there is a a valid encode start and a valid encode end time
			if (($floatEncStart -ne $null) -and ($floatEncEnd -ne $null)) {
				#add encode start time and encode end time to encode list
				$arrEncCmds = $arrEncCmds + @{
					File = $objFile.FullName
					Start = $floatEncStart
					End = $floatEncEnd
				}

				#set the encode start and encode end times to null
				$floatEncStart = $null
				$floatEncEnd = $null
			}
		}

		#increment the index counter
		$intCount++
	}
	
	return $arrEncCmds
}

function Remove-InvalidChapters ($xmlChapterInfo, $hashSegmentFiles) {
	$arrUIDs = @()
	$arrMissAtoms = @()
	$intCount = 0
	foreach ($nodeChapAtom in $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom) {
		#if the current chapter has a UID
		if ($nodeChapterAtom.ChapterUID) {
			#if the UID array contains the current chapter's UID
			if ($arrUIDs -contains $nodeChapAtom) {
				#remove it
				$nodeChapAtom.ParentNode.RemoveChild($nodeChapAtom) | Out-Null
				
				#show a warning
				Write-Host ("Warning: Duplicate UID Found For Chapter: " + ($intCount + 1) + `
				"`nThis Chapter Will Be Skipped.`n")
			}
		}
		
		#if an sid exists
		if ($nodeChapAtom.ChapterSegmentUID) {
			#if the file it references does not exist
			if (!$hashSegmentFiles.($nodeChapAtom.ChapterSegmentUID.'#text')) {
				#remove it
				$nodeChapAtom.ParentNode.RemoveChild($nodeChapAtom) | Out-Null
				
				#add its atom index to the missing atom array
				$arrMissAtoms = $arrMissAtoms + ($intCount + 1)
			}	
		}
		
		$intCount++
	}

	#Show Missing Atoms Warning
	if ($arrMissAtoms.Count -ne 0) {
		if ($arrMissAtoms.Count -gt 1) {
		$strChapterAtoms = ($arrMissAtoms[0..($arrMissAtoms.Count - 2)] -join ', ') + ' and ' +  $arrMissAtoms[-1]
		Write-Host ("Warning: Missing External Segments For Chapters $strChapterAtoms`n" + `
		"These Chapters Will Be Skipped.`n")
		}
		else {
			Write-Host ("Warning: Missing External Segment For Chapter " + $arrMissAtoms[0] + `
			"`nThis Chapter Will Be Skipped.`n")
		}
	}
	
	return $xmlChapterInfo
}

function Get-OutputFiles ($arrEncCmds, $strTempPath) {
	#initialize an array to store random output file names in
	$arrOutputFiles = @()
	
	#for the number of encode commands
	foreach ($hashCmd in $arrEncCmds) {
		#generate a random output file path
		$strOutputPath = "$strTempPath\" + (Generate-RandomString) + '.mkv'
		
		#add this path to the output file array
		$arrOutputFiles = $arrOutputFiles + $strOutputPath
	}
	
	return $arrOutputFiles
}

function Generate-FileSegmentHash ($objFile) {
	#make a hash table of matroska files referenced by their corresponding SIDs
	$listSegmentFiles=Get-Files $objFile.Directory $false $false
	$hashSegmentFiles = @{}
	foreach ($objSegmentFile in $listSegmentFiles) {
		if ($objSegmentFile.Extension -eq '.mkv') {
			$jsonFileInfo = .\bin\mkvmerge -J $objSegmentFile.FullName | ConvertFrom-Json
			$hashSegmentFiles.Set_Item($jsonFileInfo.Container.Properties.Segment_UID, $objSegmentFile.FullName)
		}
	}
	
	return $hashSegmentFiles
}

function Fix-Chapters ($xmlChapterInfo, $boolAggressive, $floatOffsetTime) {
	#if aggressive mode is enabled
	if ($boolAggressive) {
		#use aggressive mode to fix the chapters
		return 	Fix-ChapAggressive $xmlChapterInfo $floatOffsetTime
	}

	#fix the chapters
	#initialize a variable to store the extra time added by external segments
	$floatExtraTime = 0.0
	
	#initialize and index counter to zero
	$intCount = 0
	#step through each ChapterAtom
	foreach ($nodeChapAtom in $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom) {
		#if the current chapter references an external segment
		if ($nodeChapAtom.ChapterSegmentUID) {
			#remove the sid info from the chapter
			$nodeChapAtom.RemoveChild($nodeChapAtom.ChapterSegmentUID) | Out-Null
			
			#get the current chapter's duration
			$floatChapDuration = (ConvertFrom-Sexagesimal $nodeChapAtom.ChapterTimeEnd) - (ConvertFrom-Sexagesimal $nodeChapAtom.ChapterTimeStart)

			#if were not on the first chapter
			if ($i -ne 0) {
				#get the previous chapter's end time
				$floatPrevChapEnd = ConvertFrom-Sexagesimal $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom[$intCount - 1].ChapterTimeEnd

				#add the end time of the previous chapter to the current chapter's start time
				$nodeChapAtom.ChapterTimeStart = ConvertTo-Sexagesimal ((ConvertFrom-Sexagesimal $nodeChapAtom.ChapterTimeStart) + $floatPrevChapEnd)

				#add the end time of the previous chapter to the current chapter's end time
				$nodeChapAtom.ChapterTimeEnd = ConvertTo-Sexagesimal ((ConvertFrom-Sexagesimal $nodeChapAtom.ChapterTimeEnd) + $floatPrevChapEnd)

				#add this to the total extra time
				$floatExtraTime = $floatExtraTime + $floatChapDuration
			}
			#else, we are on the first chapter
			else {
				#add the current chapter's duration to the total extra time
				$floatExtraTime = $floatExtraTime + $floatChapDuration
			}
		}
		#else the chapter is not ordered
		else {
			#add the total extra time to the current chapter's start time
			$nodeChapAtom.ChapterTimeStart = ConvertTo-Sexagesimal ((ConvertFrom-Sexagesimal $nodeChapAtom.ChapterTimeStart) + $floatExtraTime)

			#add the total extra time to the current chapter's end time
			$nodeChapAtom.ChapterTimeEnd = ConvertTo-Sexagesimal ((ConvertFrom-Sexagesimal $nodeChapAtom.ChapterTimeEnd) + $floatExtraTime)
		}
		
		#set a new UID for the current chapter atom
		if (!$nodeChapAtom.ChapterUID) {
			$nodeChapAtom.AppendChild($xmlChapterInfo.CreateElement('ChapterUID')) | Out-Null
		}
		$nodeChapAtom.ChapterUID = Generate-UID

		#increment the index counter
		$intCount++
	}
	
	#set a new UID for this chapter edition
	if (!$xmlChapterInfo.Chapters.EditionEntry.EditionUID) {
		$xmlChapterInfo.Chapters.EditionEntry.AppendChild($xmlChapterInfo.CreateElement('EditionUID')) | Out-Null
	}
	$xmlChapterInfo.Chapters.EditionEntry.EditionUID = Generate-UID
	
	#set the chapters to not be ordered chapters
	$xmlChapterInfo.Chapters.EditionEntry.EditionFlagOrdered = '0'
	
	return $xmlChapterInfo
}

function Check-ChapEdition ($strChapterEdition) {
	if (!$strChapterEdition) {
		return $null
	}
	
	$intMin = 0
	$intMax = 99
	
	try {
		$intChapterEdition = 0 + ([Math]::Round($strChapterEdition))
	}
	catch {
		#Handle The Error
		Write-Host "Chapter Edition Index Is Invalid. Please Use An Integer Ranging From $intMin-$intMax"
		exit
	}
	
	if (($intChapterEdition -ge $intMin) -and ($intChapterEdition -le $intMax)) {
		return $intChapterEdition
	}
	else {
		#Handle The Error
		Write-Host "Chapter Edition Index Is Invalid Please Use An Integer Ranging From $intMin-$intMax"
		exit
	}
}

function Get-ChapEdition ($xmlChapterInfo, $intInputIndex) {
	#initialize a variable to store the chapter edition index
	$intChapEdIndex = $null
	
	
	#if a chapter edition is manually defined
	if ($intInputIndex -ne $null) {
		#if it exists
		if (@($xmlChapterInfo.Chapters.EditionEntry)[$intInputIndex]) {
			#if it has ordered chapters
			if (@($xmlChapterInfo.Chapters.EditionEntry)[$intInputIndex].EditionFlagOrdered -eq '1') {
				#mark this one for use
				$intChapEdIndex = $intInputIndex
			}
			#else it does not have ordered chapters
			else {
				#show a warning
				Write-Host ("Warning: Chapter Edition Index: $intInputIndex Was Not Found.`n" + `
				"Automatically Selecting Chapter Edition.`n")
			}	
		}
	}
	
	#if the chapter edition index is null
	if ($intChapEdIndex -eq $null) {
		#for each chapter edition
		$intCount = 0
		foreach ($nodeChapEd in $xmlChapterInfo.Chapters.EditionEntry) {
			#if a chapter edition is ordered
			if ($nodeChapEd.EditionFlagOrdered -eq '1') {
				#if it is the default
				if ($nodeEditionEntry.EditionFlagDefault -eq '1') {
					#mark this one for use
					$intChapEdIndex = $intCount
					break
				}
			}
			#increment the chapter edition index counter
			$intCount++
		}
	}
	
	#if the chapter edition index is null
	if ($intChapEdIndex -eq $null) {
		#for each chapter edition
		$intCount = 0
		foreach ($nodeChapEd in $xmlChapterInfo.Chapters.EditionEntry) {
			#if a chapter edition is ordered
			if ($nodeChapEd.EditionFlagOrdered -eq '1') {
				#mark the first one for use
				$intChapEdIndex = $intCount
				break
			}
			#increment the chapter edition index counter
			$intCount++
		}
	}
	
	#if the chapter edition is not null, i.e. one was found
	if ($intChapEdIndex -ne $null) {
		#remove all other chapter entries
		$intCount = 0
		foreach ($nodeChapEd in $xmlChapterInfo.Chapters.EditionEntry) {
				if ($intCount -ne $intChapEdIndex) {
					$nodeChapEd.ParentNode.RemoveChild($nodeChapEd) | Out-Null
				}
			#increment the chapter edition index counter
			$intCount++
		}
	}
	#else, a chapter edition index was not found
	else {
		Write-Host "No Ordered Chapter Editions Found. Skipping File."
		
		#tidy up temp files
		Cleanup-Files $arrOutputFiles $strChapterFile $strMmgOutputFile $arrSubInfo
		
		#increment the file counter
		$script:intFileCounter++
		
		#continue the file processing loop
		continue
	}
	
	return $xmlChapterInfo
}

function Show-SkippedFiles ($arrCompletedFiles, $listFiles) {
	#initialize an array to store skipped files
	$arrSkippedFiles = @()
	
	#step through each file in the input file list
	foreach ($objFile in $listFiles) {
		#if the completed list does not contain the input list FullName
		if ($arrCompletedFiles -notcontains $objFile.FullName) {
			#add it to the incomplete array
			$arrSkippedFiles = $arrSkippedFiles + $objFile.Name
		}
	}
	
	if ($arrSkippedFiles.Count -ne 0) {
		Write-Host ("The following File(s) Were Skipped:`n`n" + ($arrSkippedFiles -join "`n") + "`n")
	}
}

function Get-TotalDuration ($arrEncCmds) {
	#get the total output duration for display
	$floatTotalDuration = 0.0
	foreach ($hashCmd in $arrEncCmds) {
		$floatTotalDuration = $floatTotalDuration + ($hashCmd.End - $hashCmd.Start)
	}
	
	return $floatTotalDuration
}

function Show-Help ($boolHelp) {
	if ($boolHelp) {
	Write-Host `
@"
roc - Remove Ordered Chapters

Transcodes / Remuxes Matroska Files That Use Ordered Chapters Into a Single Matroska File.

Example Usage: roc -InputPath 'C:\Path\To\Matroska\Files\'

Options:
	-InputPath	- A Valid File Or Folder Path For Input File(s).
	-Crf		- Video Quality. Integer. 0-51. Default: 16
	-Preset		- x264 Preset. placebo, slowest, slower, slow,medium, fast, faster, ultrafast.
			  Default: medium
	-OutputPath	- A Valid Folder Path For Output File(s). Default: '<ScriptPath>\out'
	-TempPath	- A Valid Folder Path For Temporary File(s). Default '<ScriptPath>\'
	-Copy		- Copies Segments. Very Fast, But May Cause Playback / Decoding Problems.
			  Default: False
	-VideoCodec	- Video Codec. libx264, libx265. Default: libx264
	-AudioCodec	- Audio Codec. flac, aac, ac3, vorbis. Default: flac
	-SubCodec	- Subtitle Codec. ass, srt. Default: ass
	-AudioBitrate	- Audio Bitrate (kbps). Integer. 64-640.
			  Defaults: flac: N/A, aac: 320, ac3: 640, vorbis: 320
	-Aggressive	- Aggressive Segment Detection. Use With Recurring / Non-Standard Chapter Layouts,
			  This Mode Should Only Be Used When Neccessary. Default: False
	-Offset		- Chapter Start / Finish Offset (ms). 0-1000. Creates A Time Gap Between Chapters
			  To Prevent Frame Repeats When Using Aggressive Mode. Default: 40
	-EditionIndex	- Manually Select Chapter Edition Index. 0-99. Default: N/A
	-Help		- Show Script Information And Usage, Then Exit. Default: False

"@
	exit
	}

}

function Set-WindowTitle ($strWinTitle, $boolRocSession) {		
	if (!$boolRocSession) {
		$strWinTitle=((Get-Host).UI.RawUI).WindowTitle=$strWinTitle
	}
}

function Set-Codecs ($boolCopyMode, $strVideoCodec, $strAudioCodec, $strSubCodec, $intAudioBitrate) {
	if ($boolCopyMode) {
		$strVideoCodec = 'copy'
		$strAudioCodec = 'copy'
		$strSubCodec = 'copy'
		$intAudioBitrate = 64
		
		Write-Host "Warning: Codec Copy Mode Enabled. This Can Cause Playback / Decoding Problems.`n"
	}
	
	if ($intAudioBitrate -eq $null) {
		if ($strAudioCodec -eq 'aac') {
			$intAudioBitrate = 320
		}
		
		if ($strAudioCodec -eq 'ac3') {
			$intAudioBitrate = 640
		}
		
		if ($strAudioCodec -eq 'flac') {
			$intAudioBitrate = 64
		}
		
		if ($strAudioCodec -eq 'vorbis') {
			$intAudioBitrate = 320
		}
	}
	else {
		if ($strAudioCodec -eq 'flac') {
			Write-Host ("Warning: Audio Bitrate Does Not Apply When Using The FLAC Codec.`n" + `
			"Please Use AAC or AC3 Instead.`n")
		}
	}
	
	$hashCodecs = @{
		Video = $strVideoCodec
		Audio = $strAudioCodec
		Sub = $strSubCodec
		AudioBitrate = ([string]$intAudioBitrate + 'k')
	}
	
	return $hashCodecs
}

function Get-FullPath ($strInput) {
	try {
		$strOutput=(Resolve-Path -LiteralPath $strInput -ErrorAction Stop).ToString()
	}
	catch {
		return $strInput
	}
	
	return $strOutput
}

function Check-OutputPath ($strOutputFolder) {
	if (!$strOutputFolder) {
	Write-Host "Output Folder Is Undefined. Try Using The -OutputPath Option."
	Write-Host "E.g. roc -OutputPath 'C:\valid\path\to\output'"
	exit
	}
	
	$boolIsValidPath=Test-Path -PathType Container -LiteralPath $strOutputFolder
	if (!$boolIsValidPath) {
		$strOutputFolder = $strOutputFolder.Replace('`', '')
		$boolIsValidPath=Test-Path -PathType Container -LiteralPath $strOutputFolder
	}
	
	if ($boolIsValidPath) {
		#Always Get The Full Path To The Output Folder
		$strOutputFolder=Get-FullPath $strOutputFolder
	
		#Check If The Output Folder Can Be Written To
		try {
			$strRandom=Generate-RandomString
			$strOutputFolderRandom="$strOutputFolder\$strRandom"
			Add-Content -Value $null -NoNewLine -LiteralPath $strOutputFolderRandom -ErrorAction Stop
		}
		catch {	
			#Handle The Error
			Wirte-Host "Could Not Access Output Folder: $strOutputFolder`nPlease Check Permissions."
			exit
		}
		
		#Remove The Random File
		Remove-Item -LiteralPath $strOutputFolderRandom
		
		if ($strOutputFolder[-2] -ne ':') {
			$strOutputFolder = $strOutputFolder.TrimEnd('\')
		}
		
		return $strOutputFolder
	}
	else {
		#Handle The Error
		Write-Host "Output Folder: $strOutputFolder`nIs Invalid Or Does Not Exist."
		exit
	}
}

function Generate-RandomString ($strNumOfChars) {
	$strOutput=$null
	$intCount=1
	
	$arrUpperAZ=[char[]]([int][char]'a'..[int][char]'z')
	$arrLowerAZ=[char[]]([int][char]'A'..[int][char]'Z')
	$arr0To9= [char[]]([int][char]'0'..[int][char]'9')
	
	$arrInput=$arrLowerAZ+$arrUpperAZ+$arr0To9
		
	if (!$strNumOfChars) {
		$strNumOfChars=16
	}
		
	while ($intCount -le $strNumOfChars) {
		$strOutput=$strOutput+(Get-Random -InputObject $arrInput -Count 1)
		$intCount++
	}
	
	return $strOutput
}

function Generate-UID {
	$intNumOfChars=20
	$arrInput=@(0..9)
	
	while ($true) {
		[string]$strOutput=$null
		$intCount=1
		while ($intCount -le $intNumOfChars) {
			#add to the output string
			$strOutput=$strOutput+(Get-Random -InputObject $arrInput -Count 1)
			#increment the string counter
			$intCount++
		}

		#trim off leading zeros
		while ($strOutput[0] -eq '0') {
			$strOutput=$strOutput.TrimStart('0')
		}
		
		$bigintOutput = New-Object -TypeName System.Numerics.BigInteger $strOutput
		
		$bigintMaxValue = New-Object -TypeName System.Numerics.BigInteger 18446744073709551615
		
		$strResult = ($bigintOutput.CompareTo($bigintMaxValue)).ToString()
		
		if ($strResult -eq '-1') {
			return $strOutput
		}
	}	
}

function Get-Files ($InputPath, $boolInit, $boolExclude) {
	if (!$InputPath) {
		Write-Host "Input File/Folder Is Undefined. Try Using The -InputPath Option."
		Write-Host "E.g. roc -InputPath 'C:\path\to\matroskafiles'"
		exit
	}
	
	if (!(Test-Path -LiteralPath $InputPath)) {
		$InputPath = $InputPath.Replace('`', '')
		if (!(Test-Path -LiteralPath $InputPath)) {
			Write-Host "Input File/Folder Is Invalid Or Does Not Exist."
			exit
		}
	}
	
	$listFiles=New-Object System.Collections.Generic.List[System.Object]

	if ((Test-Path -LiteralPath $InputPath -PathType Container)) {
		foreach ($objFile in (Get-ChildItem -LiteralPath $InputPath)) {
			if ($objFile.Extension -eq '.mkv') {
				if ($boolExclude) {
					$strChapterInfo = .\bin\mkvextract.exe $objFile.FullName chapters -
					if ($strChapterInfo) {
						$listFiles.Add($objFile)
					}
				}
				else {
					$listFiles.Add($objFile)
				}
			}
		}
	}
	else {
		$listFiles.Add((Get-Item -LiteralPath $InputPath))
	}
	
	if ($boolInit) {
		if ($listFiles.Count -eq 0) {
			Write-Host "No Matroska Files Found."
		}
	}
	
	return $listFiles
}

function Check-CRF ($strCrf) {
	$intMin = 0
	$intMax = 51
	
	#Show An Error If The Constant Rate Factor Is Undefined
	if ($strCrf -eq $null) {
		Write-Host "Constant Rate Factor Is Not Defined. Please Enter An Integer Ranging From $intMin-$intMax."
		exit
	}
	
	#Make Sure The CRF Is Set To An Integer Between 1 and 51
	try {
		$intCrf=0 + ([Math]::Round($strCrf))
	}
	catch {
		Write-Host "Constant Rate Factor: $strCrf`nIs Invalid. Please Use An Integer Ranging From 0-51"
		exit
	}
	
	if (($intCrf -ge $intMin) -and ($intCrf -le $intMax)) {
		return $intCrf
	}
	else {
		#Handle The Error
		Write-Host "Constant Rate Factor: $strCrf`nIs Invalid. Please Use An Integer Ranging From 0-51"
		exit
	}
}

function Check-Preset ($strPreset) {
	#Define An Array Of Valid Presets If This Is The Case
	$arrValid=@('ultrafast','superfast','veryfast','faster','fast','medium','slow','slower','veryslow','placebo')
	
	#If There Is No Preset Defined, Don't Use One At All
	if (!($strPreset)) {
		return 'medium'
	}
	#Or Else If A Preset Is Defined, Check To Make Sure It Is Valid And Return It Here
	elseif ($arrValid -Contains ($strPreset.ToLower()).Trim()) {
		return ($strPreset)
	}
	#Otherwise The Preset Is Invalid, Exit The Program
	else {
		#Handle The Error
		Write-Host "Invalid Preset. Valid Presets:"
		Write-Host ($arrValid -join ', ')
		exit
	}
}

function Check-AudioBitrate ($strAudioBitrate) {
	if (!$strAudioBitrate) {
		return $null
	}
	
	$intMin = 64
	$intMax = 640
	
	try {
		$intAudioBitrate = 0 + ([Math]::Round($strAudioBitrate))
	}
	catch {
		#Handle The Error
		Write-Host "Audio Bitrate Is Invalid. Please Use An Integer Ranging From $intMin-$intMax"
		exit
	}
	
	if (($intAudioBitrate -ge $intMin) -and ($intAudioBitrate -le $intMax)) {
		return $intAudioBitrate
	}
	else {
		#Handle The Error
		Write-Host "Audio Bitrate Is Invalid Please Use An Integer Ranging From $intMin-$intMax"
		exit
	}
}

function Check-AudioCodec ($strAudioCodec) {
	$arrValid = @('flac', 'aac', 'ac3', 'vorbis')
	
	if (!$strAudioCodec) {
		Write-Host ("Audio Codec Is Not Defined. Valid Codecs:`n" + ($arrValid -join ', '))
		exit
	}
	
	$strAudioCodec = ($strAudioCodec.Trim()).ToLower()
	
	if ($arrValid -contains $strAudioCodec) {
		return $strAudioCodec
	}
	
	Write-Host ("Invalid Audio Codec. Valid Codecs:`n" + ($arrValid -join ', '))
	exit
}

function Check-VideoCodec ($strVideoCodec) {
	$arrValid = @('libx264', 'libx265')
	
	if (!$strVideoCodec) {
		Write-Host ("Video Codec Is Not Defined. Valid Codecs:`n" + ($arrValid -join ', '))
		exit
	}
	
	$strVideoCodec = ($strVideoCodec.Trim()).ToLower()
	
	if ($arrValid -contains $strVideoCodec) {
		return $strVideoCodec
	}
	
	Write-Host ("Invalid Video Codec. Valid Codecs:`n" + ($arrValid -join ', '))
	exit
}

function Check-SubCodec ($strSubCodec) {
	$arrValid = @('ass','srt')
	
	if (!$strSubCodec) {
		Write-Host ("Subtitle Codec Is Not Defined. Valid Codecs:`n" + ($arrValid -join ', '))
		exit
	}
	
	$strSubCodec = ($strSubCodec.Trim()).ToLower()
	
	if ($arrValid -contains $strSubCodec) {
		return $strSubCodec
	}
	
	Write-Host ("Invalid Subtitle Codec. Valid Codecs:`n" + ($arrValid -join ', '))
	exit
}

function ConvertTo-Sexagesimal ([float]$floatDuration) {
	#Split Up The Input String Into Hours, Minutes And Seconds
	$strHours=[math]::truncate($floatDuration/3600)
	$strMins=[math]::truncate($floatDuration/60)-($strHours*60)
	$strSecs=$floatDuration-($strHours*3600)-($strMins*60)
	
	#Convert Them Into The Appropriate String Formats
	$strHours=([int]$strHours).ToString("00")
	$strMins=([int]$strMins).ToString("00")
	$strSecs=([Math]::Round(([float]$strSecs), 3)).ToString("00.000")
	
	#Construct The Output String
	$strDuration="$strHours`:$strMins`:$strSecs"
	
	#Return The Output String
	return $strDuration
}

function ConvertFrom-Sexagesimal ($strSexTime) {
	#Split Up The Sexagesimal Time Into Hours, Minutes And Seconds
	$strHours=[float]($strSexTime.Split(':')[0])*3600
	$strMins=[float]($strSexTime.Split(':')[1])*60
	$strSecs=[float]($strSexTime.Split(':')[2])
	
	#Add Up To Get A Total Time
	$floatTime=$strHours+$strMins+$strSecs
	
	return $floatTime
}

function Cleanup-Files ($arrOutputFiles, $strChapterFile, $strMmgOutputFile, $arrSubInfo) {
	if($arrOutputFiles) {
		foreach ($strOutputFile in $arrOutputFiles) {
			if ($strOutputFile) {
				if (Test-Path -LiteralPath $strOutputFile) {
					Remove-Item -LiteralPath $strOutputFile -ErrorAction SilentlyContinue
				}
			}
		}
	}
	
	if ($arrSubInfo) {
		foreach ($hashSubInfo in $arrSubInfo) {
			if ($hashSubInfo.File) {
				if (Test-Path -LiteralPath $hashSubInfo.File) {
					Remove-Item -LiteralPath $hashSubInfo.File -ErrorAction SilentlyContinue
				}
			}
		}
	}
	
	if ($strChapterFile) {
		if (Test-Path -LiteralPath $strChapterFile) {
			Remove-Item -LiteralPath $strChapterFile -ErrorAction SilentlyContinue
		}
	}
	
	if ($strMmgOutputFile) {
		if (Test-Path -LiteralPath $strMmgOutputFile) {
			Remove-Item -LiteralPath $strMmgOutputFile -ErrorAction SilentlyContinue
		}
	}
}

function Check-OffsetTime ($strOffsetTime) {
	$intMin = 0
	$intMax = 1000
	
	#show an error if the offset time is undefined
	if ($strOffsetTime -eq $null) {
		Write-Host "Offset Time Is Not Defined. Please Enter An Integer Ranging From $intMin-$intMax."
		exit
	}
	
	#make sure the offset is set to an integer between 0 and 1000
	try {
		$strOffsetTime = 0 + ([Math]::Round($strOffsetTime))
	}
	catch {
		Write-Host "Offset Time Is Invalid. Please Enter An Integer Ranging From $intMin-$intMax."
		exit
	}
	
	if (($strOffsetTime -ge $intMin) -and ($strOffsetTime -le $intMax)) {
		return ($strOffsetTime/2)/1000
	}
	else {
		#Handle The Error
		Write-Host "Offset Time Is Invalid. Please Enter An Integer Ranging From $intMin-$intMax."
		exit
	}
}

function Escape-Backticks ($strInput) {
	#Escape Any Backticks In The Input String
	$strOutput=$strInput.Replace('`','``')

	#Return The Result
	return $strOutput
}

function Unescape-Backticks ($strInput) {
	#Unescape Any Backticks In The Input String
	$strOutput=$strInput.Replace('``','`')

	#Return The Result
	return $strOutput
}

function Generate-SID {
	$arrHexValues = @()
	
	(0x00..0xff) | % {$arrHexvalues += $_.ToString("x2")}
	
	$strSID = (Get-Random -InputObject $arrHexValues -Count 16) -join ''
	
	return $strSID
}