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
		Write-Host "(roc) - Remove Ordered Chapters 0.1beta By d3sim8 2018.`nType 'roc -Help' And Press Enter To Begin.`n"
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

		#build a list of encode info
		$arrEncodeInfo = @()
		$intCounter = 0
		foreach ($nodeChapterAtom in $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom) {
			#first, we need to check if an SID exists for this chapter
			if ($nodeChapterAtom.ChapterSegmentUID) {
				#add the needed info to the array of encode info
				$arrEncodeInfo = $arrEncodeInfo + [ordered]@{
					InputFile = $hashSIDFiles.($nodeChapterAtom.ChapterSegmentUID.'#text');
					StartTime = $nodeChapterAtom.ChapterTimeStart;
					EndTime = $nodeChapterAtom.ChapterTimeEnd;
					Inserted = $true;
					Index = $intCounter
					SID = $nodeChapterAtom.ChapterSegmentUID.'#text'
				}
			}
			#we are dealing with a regular chapter
			else {
				#add this info to the array
				$arrEncodeInfo = $arrEncodeInfo + [ordered]@{
					InputFile = $objFile.FullName;
					StartTime = $nodeChapterAtom.ChapterTimeStart;
					EndTime = $nodeChapterAtom.ChapterTimeEnd;
					Inserted = $false;
					Index = $intCounter
					SID = $nodeChapterAtom.ChapterSegmentUID.'#text'
				}
			}
			$intCounter++
		}
		
		#make a list of valid inserted chapters
		#mark all invalid chapters as disabled
		$arrInsertedChapters = @()
		$arrInvalidChapterAtoms = @()
		$arrInvalidSIDs = @()
		$intCounter = 0
		foreach ($hash in $arrEncodeInfo) {
			if ($hash.Inserted -eq $true) {
				if ($hash.InputFile) {
					$arrInsertedChapters = $arrInsertedChapters + $hash.Index
				}
				else {
					$arrInvalidChapterAtoms = $arrInvalidChapterAtoms + $intCounter
					$arrInvalidSIDs = $arrInvalidSIDs + $hash.SID
				}
			}
			$intCounter++
		}
		
		if ($arrInvalidChapterAtoms.Count -gt 0) {
			Write-Host "`nInvalid File References Found For:"
			$intCounter = 0
			foreach ($intSegment in $arrInvalidChapterAtoms) {
				Write-Host ("Chapter Atom Index: " + $intSegment + " SID: " + $arrInvalidSIDs[$intCounter])
				$intCounter++
			}
			Write-Host "These Chapter Atoms Will Be Skipped."
			if ($arrInsertedChapters.Count -eq 0) {
				Write-Host "No Valid Chapter Atoms Found. Skipping File."
				continue
			}
		}
		
		#fix the chapters
		#we need to add timestamps to all of the chapters after the inserted chapters to fix them
		$intCounter = 0
		$floatExtraDuration = 0
		foreach ($nodeChapterAtom in $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom) {
			if ($nodeChapterAtom.ChapterSegmentUID) {
				#make sure it is a valid chapter, mark it as disabled if it is not, and set it's start and end time
				#to be the same as the end time of the chapter before it, if it is the first chapter, set it all to zero
				if ($arrInvalidChapterAtoms -contains $intCounter) {
					if ($intCounter -eq 0) {
						$nodeChapterAtom.ChapterTimeStart = ConvertTo-Sexagesimal 0.0
						$nodeChapterAtom.ChapterTimeEnd = ConvertTo-Sexagesimal 0.0
					}
					else {
						$floatPrevChapterEnd = ConvertFrom-Sexagesimal $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom[$intCounter - 1].ChapterTimeEnd
						$nodeChapterAtom.ChapterTimeStart = ConvertTo-Sexagesimal $floatPrevChapterEnd
						$nodeChapterAtom.ChapterTimeEnd = ConvertTo-Sexagesimal $floatPrevChapterEnd
						$nodeChapterAtom.ChapterFlagEnabled = '0'
					}
				}
				
				#add the end time of the previous chapter to this chapter's start and finish
				if ($intCounter -gt 0) {
					$floatCurrentChapterStart = ConvertFrom-Sexagesimal $nodeChapterAtom.ChapterTimeStart
					$floatCurrentChapterEnd = ConvertFrom-Sexagesimal $nodeChapterAtom.ChapterTimeEnd
					$floatCurrentChapterDuration = $floatCurrentChapterEnd - $floatCurrentChapterStart
					$floatPrevChapterEnd = ConvertFrom-Sexagesimal $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom[$intCounter - 1].ChapterTimeEnd
					
					$nodeChapterAtom.ChapterTimeStart = ConvertTo-Sexagesimal ($floatCurrentChapterStart + $floatPrevChapterEnd)
					$nodeChapterAtom.ChapterTimeEnd = ConvertTo-Sexagesimal ($floatCurrentChapterEnd + $floatPrevChapterEnd)
				}
				
				$floatExtraDuration = $floatExtraDuration + $floatCurrentChapterDuration
			}
			else {
				$floatCurrentChapterStart = ConvertFrom-Sexagesimal $nodeChapterAtom.ChapterTimeStart
				$floatCurrentChapterEnd = ConvertFrom-Sexagesimal $nodeChapterAtom.ChapterTimeEnd
					
				if ($intCounter -gt 0) {
					#get the previous chapters end time now it has been updated properly
					$floatCurrentChapterStart = ConvertFrom-Sexagesimal $nodeChapterAtom.ChapterTimeStart
					$floatPrevChapterEnd = ConvertFrom-Sexagesimal $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom[$intCounter - 1].ChapterTimeEnd

					$nodeChapterAtom.ChapterTimeStart = ConvertTo-Sexagesimal ($floatCurrentChapterStart + $floatExtraDuration)
					$nodeChapterAtom.ChapterTimeEnd = ConvertTo-Sexagesimal ($floatCurrentChapterEnd + $floatExtraDuration)
				}
			}
			
			$intCounter++
		}
		
		#Finally, set the chapters to not be ordered chapters
		$xmlChapterInfo.Chapters.EditionEntry.EditionFlagOrdered = '0'
		
		$strChapterFile = $strTempPath + '\' + (Generate-RandomString) + '.xml'
		$xmlChapterInfo.Save("$strChapterFile")
		
		#make an array of encode instructions from the array of inserted chapters
		$arrEncodeInstructions = @()
		$intCounter = 0
		foreach ($intChapter in $arrInsertedChapters) {
			#start cases
			if ($intCounter -eq 0) {
				#Special Case: handle the first chapter being an inserted file
				if ($intChapter -eq 0) {
					#add encode instructions for the inserted file only
					$arrEncodeInstructions = $arrEncodeInstructions + [ordered]@{
						InputFile = $arrEncodeInfo[$intChapter].InputFile;
						StartTime = $arrEncodeInfo[$intChapter].StartTime;
						EndTime = $arrEncodeInfo[$intChapter].EndTime
					}
				}
				else {
					#add the encode instructions for the original file
					$arrEncodeInstructions = $arrEncodeInstructions + [ordered]@{
						InputFile = $objFile.FullName;
						StartTime = $arrEncodeInfo[$intCounter].StartTime;
						EndTime = $arrEncodeInfo[$intChapter - 1].EndTime
					}
					
					#add the encode instructions for the inserted file
					$arrEncodeInstructions = $arrEncodeInstructions + [ordered]@{
						InputFile = $arrEncodeInfo[$intChapter].InputFile;
						StartTime = $arrEncodeInfo[$intChapter].StartTime;
						EndTime = $arrEncodeInfo[$intChapter].EndTime
					}
				}
			}
			
			#middle case
			if (($intCounter -lt ($arrInsertedChapters.Count - 1)) -and ($intCounter -gt 0)) {
				#add the encode instructions for the original file
				$arrEncodeInstructions = $arrEncodeInstructions + [ordered]@{
					InputFile = $objFile.FullName;
					StartTime = $arrEncodeInfo[($arrInsertedChapters[$intCounter - 1] + 1)].StartTime;
					EndTime = $arrEncodeInfo[$intChapter - 1].EndTime
				}
				
				#add the encode instructions for the inserted file
				$arrEncodeInstructions = $arrEncodeInstructions + [ordered]@{
					InputFile = $arrEncodeInfo[$intChapter].InputFile;
					StartTime = $arrEncodeInfo[$intChapter].StartTime;
					EndTime = $arrEncodeInfo[$intChapter].EndTime
				}
			}
			
			#end cases
			if ($intCounter -eq ($arrInsertedChapters.Count - 1)) {
				#only use the start of the last inserted chapter if it is actually there
				if ($arrInsertedChapters.Count -ne 1) {
					#add the encode instructions for the original file
					$arrEncodeInstructions = $arrEncodeInstructions + [ordered]@{
						InputFile = $objFile.FullName;
						StartTime = $arrEncodeInfo[($arrInsertedChapters[$intCounter - 1] + 1)].StartTime;
						EndTime = $arrEncodeInfo[$intChapter - 1].EndTime
					}
					
					#add the encode instructions for the inserted file
					$arrEncodeInstructions = $arrEncodeInstructions + [ordered]@{
						InputFile = $arrEncodeInfo[$intChapter].InputFile;
						StartTime = $arrEncodeInfo[$intChapter].StartTime;
						EndTime = $arrEncodeInfo[$intChapter].EndTime
					}
				}
				
				#handle any extra video at the end
				if ($intChapter -lt ($arrEncodeInfo.Count - 1)) {
					#add the encode instructions for the original file only
					$arrEncodeInstructions = $arrEncodeInstructions + [ordered]@{
						InputFile = $objFile.FullName;
						StartTime = $arrEncodeInfo[($intChapter + 1)].StartTime;
						EndTime = $arrEncodeInfo[-1].EndTime
					}
				}
			}
			
			$intCounter++
		}
		
		#encode the video using the encode instructions
		$floatSeekOffset = 15.0
		$arrOutputFiles = @()
		$floatTotalDuration = ConvertFrom-Sexagesimal $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom[-1].ChapterTimeEnd
		$intTotalChunks = $arrEncodeInstructions.Count
		
		Write-Host ("Total Duration: " + (ConvertTo-Sexagesimal $floatTotalDuration))
		
		$intCounter = 1
		foreach ($hash in $arrEncodeInstructions) {
			$floatStartTime = ConvertFrom-Sexagesimal $hash.StartTime
			$floatEndTime = ConvertFrom-Sexagesimal $hash.EndTime
			$floatDuration = $floatEndTime - $floatStartTime
			$strOutputFile = $strTempPath + '\' + (Generate-RandomString) + '.mkv'
			$arrOutputFiles = $arrOutputFiles + $strOutputFile
			
			$strDuration = ConvertTo-Sexagesimal $floatDuration
			$strStartTime = ConvertTo-Sexagesimal $floatStartTime
			$strEndTime = ConvertTo-Sexagesimal $floatEndTIme
			
			Write-Host "Processing Chunk $intCounter of $intTotalChunks Duration: $strDuration ($strStartTime - $strEndTime)"
			
			if ($floatStartTime -eq 1.000) {
				.\bin\ffmpeg.exe -v quiet -stats -y -i $hash.InputFile -map ? -t $floatDuration -c:v $strVideoCodec -c:a $strAudioCodec -c:s $strSubCodec `
				-preset:v $strPreset -crf $intCrf -map_chapters -1 $strOutputFile
			}
			else {
				.\bin\ffmpeg.exe -v quiet -stats -ss ($floatStartTime - $floatSeekOffset) -y -i $hash.InputFile -ss $floatSeekOffset -map ? -t $floatDuration `
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