Param (
	[string]$InputPath = '',
	[int]$Crf = 16,
	[string]$Preset = 'medium',
	[string]$OutputPath = "$PSScriptRoot\out",
	[string]$TempPath = "$PSScriptRoot",
	[switch]$SetupOnly = $false,
	[switch]$Copy = $false,
	[switch]$Help = $false
)

#Import Functions
. '.\libroc.ps1'

Set-Alias -Name 'roc' -Value '.\roc.ps1' -Scope 1

#save and set the initial window title
$strInitialWinTitle=((Get-Host).UI.RawUI).WindowTitle
Set-WindowTitle 'roc'

Show-Help $Help

if ($SetupOnly) {
	Set-Variable -Name RocSession -Value $true -Scope 1
	Write-Host "(roc) - Remove Ordered Chapters 0.1beta By d3sim8 2018.`nType 'roc -Help' And Press Enter To Begin.`n"
	exit
}
else {
	if (!$RocSession) {
		Write-Host "(roc) - Remove Ordered Chapters 0.1beta By d3sim8 2018.`n"
	}
}

$listFiles = Get-Files $InputPath $true $true
$intCrf = Check-Crf $Crf
$strPreset = Check-Preset $Preset
$strOutputPath = Check-OutputPath $OutputPath
$strTempPath = Check-OutputPath $TempPath

#set the codecs if copying is enabled
$strVideoCodec = 'libx264'
$strAudioCodec = 'flac'
$strSubCodec = 'ass'
if ($Copy) {
	$strVideoCodec = 'copy'
	$strAudioCodec = 'copy'
	$strSubCodec = 'copy'
	Write-Host -ForegroundColor Yellow "Warning: Copy Mode Enabled. This Will Probably Cause Playback Problems."
}

#put everything in a try loop to catch errors and clean up temp files easily
try {
	#init a counter so we know which file we are up to
	$intFileCounter = 1
	#start a loop to iterate though the list of files
	foreach ($objFile in $listFiles) {
		#write a progress message to the screen
		$strMessage = "Processing File $intFileCounter of " + $listFiles.Count
		Write-Host ('-' * $strMessage.Length)
		Write-Host $strMessage
		Write-Host ('-' * $strMessage.Length)
		
		#show the input file path
		Write-Host ("Input File: " + $objFile.FullName)
		
		#define the output file path and show it
		$strMkvMergeOutputFile = $strOutputPath + '\' + $objFile.BaseName + '.mkv'
		Write-Host  ("Output File: " + $strMkvMergeOutputFile)
		
		#Get the chapter info	
		[xml]$xmlChapterInfo = .\bin\mkvextract.exe $objFile.FullName chapters -
		
		#make a list of files with their corresponding SIDs to look up
		$listSIDFiles=Get-Files $objFile.Directory $false $false
		$hashSIDFiles = @{}
		foreach ($objSIDFile in $listSIDFiles) {
			if ($objSIDFile.Extension -eq '.mkv') {
				$jsonFileInfo = .\bin\mkvmerge -J $objSIDFile.FullName | ConvertFrom-Json
				$hashSIDFiles.Set_Item($jsonFileInfo.Container.Properties.Segment_UID, $objSIDFile.FullName)
			}
		}
		
		#algorithm for making encode instructions
		#Initialize an array of encode instructions
		$arrEncInst = @()
		
		#initialize and index counter to zero
		$intCount = 0
		#step through each ChapterAtom
		foreach ($ChapAtom in $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom) {
			#if the current chapter is ordered
			if ($ChapAtom.ChapterSegmentUID) {
				#get it's reference file
				$RefFile = $hashSIDFiles.($ChapAtom.ChapterSegmentUID.'#text')
				
				#if its reference file exists
				if ($RefFile) {
					#get current chapters start time
					$EncStart = ConvertFrom-Sexagesimal $ChapAtom.ChapterTimeStart
					
					#get current chapter's end time
					$EncEnd = ConvertFrom-Sexagesimal $ChapAtom.ChapterTimeEnd
					
					#add start time, end time and file name encode list
					$arrEncInst = $arrEncInst + [ordered]@{
						File = $RefFile
						Start = $EncStart
						End = $EncEnd
					}
					
					#set encode start and end back to null
					$EncStart = $null
					$EncEnd = $null
				}
			}
			#else the chapter is not ordered
			else {
				#if we are not on the first chapter
				if ($intCount -ne 0) {
					#if the previous chapter was ordered				
					if ($xmlChapterInfo.Chapters.EditionEntry.ChapterAtom[$intCount - 1].ChapterSegmentUID) {
						#set encode start time to current chapter's start time
						$EncStart = ConvertFrom-Sexagesimal $ChapAtom.ChapterTimeStart
					}
				}
				#else we are on the first chapter
				else {
					#set the encode start time to the current chapter's start time
					$EncStart = ConvertFrom-Sexagesimal $ChapAtom.ChapterTimeStart
				}
					
				#if we are not on the last chapter
				if  ($intCount -ne ($xmlChapterInfo.Chapters.EditionEntry.ChapterAtom.Count - 1)) {
					#if the next chapter is going to be ordered
					if ($xmlChapterInfo.Chapters.EditionEntry.ChapterAtom[$intCount + 1].ChapterSegmentUID) {
						#set encode end time to current chapter's end time
						$EncEnd = ConvertFrom-Sexagesimal $ChapAtom.ChapterTimeEnd
					}
				}
				#else we are on the last chapter
				else {
					#set the encode end time to the end of the current chapter
					$EncEnd = ConvertFrom-Sexagesimal $ChapAtom.ChapterTimeEnd
				}
				
				#if there is a a valid encode start and a valid encode end time
				if (($EncStart -ne $null) -and ($EncEnd -ne $null)) {
					#add encode start time and encode end time to encode list
					$arrEncInst = $arrEncInst + [ordered]@{
						File = $objFile.FullName
						Start = $EncStart
						End = $EncEnd
					}
					
					#set the encode start and encode end times to null
					$EncStart = $null
					$EncEnd = $null
				}
			}
			
			#increment the index counter
			$intCount++
		}
		
		#algorithm to fix chapters
		#initialize and index counter to zero
		$ExtraTime = 0.0
		$intCount = 0
		#step through each ChapterAtom
		foreach ($ChapAtom in $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom) {
			#if the current chapter is ordered
			if ($ChapAtom.ChapterSegmentUID) {
				#get it's reference file
				$RefFile = $hashSIDFiles.($ChapAtom.ChapterSegmentUID.'#text')
				
				#if its reference file exists
				if ($RefFile) {
					#get the current chapter's duration
					$ChapDur = (ConvertFrom-Sexagesimal $ChapAtom.ChapterTimeEnd) - (ConvertFrom-Sexagesimal $ChapAtom.ChapterTimeStart)
				
					#if were not on the first chapter
					if ($i -ne 0) {
						#get the previous chapter's end time
						$PrevEnd = ConvertFrom-Sexagesimal $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom[$intCount - 1].ChapterTimeEnd
						
						#add the end time of the previous chapter to the current chapter's start time
						$ChapAtom.ChapterTimeStart = ConvertTo-Sexagesimal ((ConvertFrom-Sexagesimal $ChapAtom.ChapterTimeStart) + $PrevEnd)
						
						#add the end time of the previous chapter to the current chapter's end time
						$ChapAtom.ChapterTimeEnd = ConvertTo-Sexagesimal ((ConvertFrom-Sexagesimal $ChapAtom.ChapterTimeEnd) + $PrevEnd)
						
						#add this to the total extra time
						$ExtraTime = $ExtraTime + $ChapDur
					}
					#else, we are on the first chapter
					else {
						#add the current chapter's duration to the total extra time
						$ExtraTime = $ExtraTime + $ChapDur
					}
				}
				#else its reference file does not exist
				else {
					#mark the current chapter as disabled
					$ChapAtom.ChapterFlagEnabled = '0'
					
					#if it is the not the first chapter
					if ($intCount -ne 0) {
						#set current chapter start to the end to the previous chapter's end time
						$ChapAtom.ChapterTimeStart = $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom[$intCount - 1].ChapterTimeEnd
						
						#set current chapter end to the end to the previous chapter's end time
						$ChapAtom.ChapterTimeEnd = $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom[$intCount - 1].ChapterTimeEnd
					}
					#else it is the first chapter
					else {
						#set current chapter's end as equal its start, effectively disabling it, as it is zero length from it's start point
						$ChapAtom.ChapterTimeEnd = $ChapAtom.ChapterTimeStart
					}
				}
			}
			#else the chapter is not ordered
			else {
				#add the total extra time to the current chapter's start time
				$ChapAtom.ChapterTimeStart = ConvertTo-Sexagesimal ((ConvertFrom-Sexagesimal $ChapAtom.ChapterTimeStart) + $ExtraTime)
			
				#add the total extra time to the current chapter's end time
				$ChapAtom.ChapterTimeEnd = ConvertTo-Sexagesimal ((ConvertFrom-Sexagesimal $ChapAtom.ChapterTimeEnd) + $ExtraTime)
			}
			
			#increment the index counter
			$intCount++
		}
		
		#set the chapters to not be ordered chapters
		$xmlChapterInfo.Chapters.EditionEntry.EditionFlagOrdered = '0'
		
		#define the chapter file output path
		$strChapterFile = $strTempPath + '\' + (Generate-RandomString) + '.xml'
		
		#save the chapter file to this output path
		$xmlChapterInfo.Save("$strChapterFile")
		
		#encode the video using the encode instructions
		$floatSeekOffset = 15.0
		$arrOutputFiles = @()
		$floatTotalDuration = 
		$intTotalChunks = $arrEncInst.Count
		
		#get the total output duration for display
		$floatTotalDuration = 0.0
		foreach ($Inst in $arrEncInst) {
			$floatTotalDuration = $floatTotalDuration + ($Inst.end - $Inst.start)
		}
		
		Write-Host ("Total Output Duration: " + (ConvertTo-Sexagesimal $floatTotalDuration))
		
		$intCounter = 1
		$floatProg = 0.0
		foreach ($Inst in $arrEncInst) {
			$floatStartTime = $Inst.Start
			$floatEndTime = $Inst.End
			$floatDuration = $floatEndTime - $floatStartTime
			$strOutputFile = $strTempPath + '\' + (Generate-RandomString) + '.mkv'
			$arrOutputFiles = $arrOutputFiles + $strOutputFile
			
			$strDuration = ConvertTo-Sexagesimal $floatDuration
			$strStartProg = ConvertTo-Sexagesimal $floatProg
			$floatProg = $floatProg + $floatDuration
			$strEndProg = ConvertTo-Sexagesimal $floatProg
			
			
			$floatHybridSeek = $floatStartTime - $floatSeekOffset
			if ($floatHybridSeek -le 0.0) {
				$floatStartTime = 0.0
			}
			
			Write-Host "Processing Chunk $intCounter of $intTotalChunks Duration: $strDuration Output Range: $strStartProg - $strEndProg"
			
			#avoid seeking when possible, as ffmpeg seems to be buggy sometimes
			if ($floatStartTime -eq 0.0) {
				.\bin\ffmpeg.exe -v quiet -stats -y -i $Inst.File -map ? -t $floatDuration -c:v $strVideoCodec -c:a $strAudioCodec -c:s $strSubCodec `
				-preset:v $strPreset -crf $intCrf -map_chapters -1 $strOutputFile
			}
			#otherwise, if we have to use seeking, seek a bit backwards, and decode that bit until we get to the start point
			else {
				.\bin\ffmpeg.exe -v quiet -stats -ss $floatHybridSeek -y -i $Inst.File -ss $floatSeekOffset -map ? -t $floatDuration `
				-c:v $strVideoCodec -c:a $strAudioCodec -c:s $strSubCodec -preset:v $strPreset -crf $intCrf -map_chapters -1 $strOutputFile
			}
			
			$intCounter++
		}
		
		$strMkvMergeOutputFile = $strOutputPath + '\' + $objFile.BaseName + '.mkv'

		#Make an expression string that mkvmerge can run
		Write-Host "Remuxing Segments. Please Wait..."
		$strMkvMerge = ".\bin\mkvmerge --output '$strMkvMergeOutputFile' --chapters '$strChapterFile' " + ($arrOutputFiles -join " + ") + ' | Out-Null'
	
		#Use mkvmerge to join all of the output files
		Invoke-Expression $strMkvMerge

		Cleanup-Files $arrOutputFiles $strChapterFile
		
		#Increment the file counter
		$intFileCounter++
	}
		
	Write-Host "Complete."
}
catch {
	#Show The Error
	$objException = $_.Exception
	$intLineNumber = $_.InvocationInfo.ScriptLineNumber
	$strMessage = $objException.Message
	Write-Host -ForegroundColor Yellow "Error: Caught Exception At Line $intLineNumber`:`n$strMessage"
		if (!$RocSession) {
		Set-WindowTitle $strInitialWinTitle
	}
	Cleanup-Files $arrOutputFiles $strChapterFile
}
finally {
	if (!$RocSession) {
		Set-WindowTitle $strInitialWinTitle
	}
	Cleanup-Files $arrOutputFiles $strChapterFile
}