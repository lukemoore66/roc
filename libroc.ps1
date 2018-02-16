function Encode-Segments ($arrEncCmds, $hashCodecs, $arrOutputFiles) {
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
			.\bin\ffmpeg.exe -v quiet -stats -y -i $hashCmd.File -map ? -t $floatDuration `
			-c:v $hashCodecs.Video -c:a $hashCodecs.Audio -c:s $hashCodecs.Sub `
			-preset:v $strPreset -crf $intCrf -x264opts stitchable=1 -map_chapters -1 $strOutputFile
		}
		#otherwise, if we have to use seeking, seek a bit backwards, and decode that bit until we get to the start point
		else {
			.\bin\ffmpeg.exe -v quiet -stats -ss $floatHybridSeek -y -i $hashCmd.File -ss $floatSeekOffset -map ? -t $floatDuration `
			-c:v $hashCodecs.Video -c:a $hashCodecs.Audio -c:s $hashCodecs.Sub `
			-preset:v $strPreset -crf $intCrf -x264opts stitchable=1 -map_chapters -1 $strOutputFile
		}

		$intCounter++
	}
	
	return $arrOutputFiles
}

function Merge-Segments ($arrOutputFiles, $strMkvMergeOutputFile, $strChapterFile) {
	#Make an expression string that mkvmerge can run
	Write-Host "Appending Segments. Please Wait..."
	$strMkvMerge = ".\bin\mkvmerge --output '$strMkvMergeOutputFile' --chapters '$strChapterFile' " + `
	($arrOutputFiles -join " + ") + ' | Out-Null'

	#Use mkvmerge to join all of the output files
	Invoke-Expression $strMkvMerge

	Write-Host "Processing Complete.`n"
}

function Show-Version ($SetupOnly, $RocSession, $strVersion) {
	if ($SetupOnly) {
	Set-Variable -Name RocSession -Value $true -Scope 2
	
	Write-Host "(roc) - Remove Ordered Chapters $strVersion By d3sim8.`nType 'roc -Help' And Press Enter To Begin.`n"
	
	exit
	}
	else {
		if (!$RocSession) {
			Write-Host "(roc) - Remove Ordered Chapters $strVersion 2018 By d3sim8.`n"
		}
	}
}

function Get-EncodeCommands ($xmlChapterInfo, $hashSegmentFiles) {
	#make an array of encode commands for ffmpeg to process
	#Initialize an array of encode commands
	$arrEncCmds = @()

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
			$arrEncCmds = $arrEncCmds + [ordered]@{
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
				$arrEncCmds = $arrEncCmds + [ordered]@{
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
	$arrMissAtoms = @()
	$intCount = 0
	foreach ($nodeChapAtom in $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom) {
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
	$hashSegmentFiles = [ordered]@{}
	foreach ($objSegmentFile in $listSegmentFiles) {
		if ($objSegmentFile.Extension -eq '.mkv') {
			$jsonFileInfo = .\bin\mkvmerge -J $objSegmentFile.FullName | ConvertFrom-Json
			$hashSegmentFiles.Set_Item($jsonFileInfo.Container.Properties.Segment_UID, $objSegmentFile.FullName)
		}
	}
	
	return $hashSegmentFiles
}

function Fix-Chapters ($xmlChapterInfo) {
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
		$nodeChapAtom.ChapterUID = Generate-UID

		#increment the index counter
		$intCount++
	}

	#set the chapters to not be ordered chapters
	$xmlChapterInfo.Chapters.EditionEntry.EditionFlagOrdered = '0'
	
	return $xmlChapterInfo
}

function Get-DefaultEdition ($xmlChapterInfo) {
	#reduce the chapter edition count to a single ordered default edition
	#initialize a variable to store the default first ordered chapter edition index
	$intDefaultEdIndex = $null
	$intCount = 0
	foreach ($nodeEditionEntry in $xmlChapterInfo.Chapters.EditionEntry) {
		#if the chapter edition is ordered
		if ($nodeEditionEntry.EditionFlagOrdered -eq '1') {
			#if the edition is marked as default, 
			if ($nodeEditionEntry.EditionFlagDefault -eq '1') {
				#use this
				$intDefaultEdIndex = $intCount
				
				#break the loop here
				break
			}
		}
		
		#increment the entry counter
		$intCount++
	}
	
	#if a default was found, remove all other chapter editions
	$intCount = 0
	if ($intDefaultEdIndex -ne $null) {
		$intCount = 0
		foreach ($nodeEditionEntry in $xmlChapterInfo.Chapters.EditionEntry) {
			#if the index does not equal the default one
			if ($intCount -ne $intDefaultEdIndex) {
				#remove the edition
				$nodeEditionEntry.ParentNode.RemoveChild($nodeEditionEntry) | Out-Null
			}
			#increment the entry counter
			$intCount++
		}
	}
	else {
	#else, no default was found, there is at least one edition ordered chapters, remove all but the first
		$intCount = 0
		foreach ($nodeEditionEntry in $xmlChapterInfo.Chapters.EditionEntry) {
			#if we are not one the first entry
			if ($intCount -ne 0) {
				$nodeEditionEntry.ParentNode.RemoveChild($nodeEditionEntry) | Out-Null
			}
			
			#increment the entry counter
			$intCount++
		}
	}
	
	#set a new UID for this chapter edition
	$xmlChapterInfo.Chapters.EditionEntry.EditionUID = Generate-UID
	
	return $xmlChapterInfo
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
	[-InputPath] <String>]	- A Valid File Or Folder Path For Input File(s).
	[-Crf <Int>]		- An Integer Ranging From 0-51. (AKA: Video Quality 14-25 Are Sane Values)
	[-Preset <String>]	- x264 Preset. placebo, slowest, slower, slow, medium, fast, faster, ultrafast
	[-OutputPath <String>]	- A Valid Folder Path For Output File(s).
	[-TempPath <String>]	- A Valid Folder Path For Temporary File(s).
	[-Copy <Switch>]	- Copies (Remuxes) Segments. Very Fast, But May Cause Playback Problems.
	[-Help <Switch>]	- Shows This Help Menu.
	
"@
	exit
	}

}

function Set-WindowTitle ($strWinTitle, $boolRocSession) {		
	if (!$boolRocSession) {
		$strWinTitle=((Get-Host).UI.RawUI).WindowTitle=$strWinTitle
	}
}

function Set-Codecs {
	Param(
		[string]$Video = 'libx264',
		[string]$Audio = 'flac',
		[string]$Sub = 'ass',
		[bool]$CopyMode = $false
	)
	
	if ($CopyMode) {
		$Video = 'copy'
		$Audio = 'copy'
		$Sub = 'copy'
		
		Write-Host -ForegroundColor Yellow "Warning: Copy Mode Enabled. This Will Probably Cause Playback Problems."
	}
	
	$hashCodecs = [ordered]@{
		Video = $Video
		Audio = $Audio
		Sub = $Sub
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
	
	$intWhileCount = 0
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
		
		$intWhileCount++
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
	#Set Some Sensible Defaults If The Constant Rate Factor Is Undefined
	if (!$strCrf) {
		return 14
	}
	
	#Make Sure The CRF Is Set To An Integer Between 1 and 51
	try {
		$intCrf=0+([Math]::Round($strCrf))
	}
	catch {
		Write-Host "Constant Rate Factor: $strCrf`nIs Invalid. Please Use An Integer Ranging From 0-51"
	}
	
	if (($intCrf -ge 0) -and ($intCrf -le 51)) {
		return $intCrf
	}
	else {
		#Handle The Error
		Write-Host "Constant Rate Factor: $strCrf`nIs Invalid. Please Use An Integer Ranging From 0-51"
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

function Cleanup-Files ($arrOutputFiles, $strChapterFile) {
	foreach ($strOutputFile in $arrOutputFiles) {
		if (Test-Path -LiteralPath $strOutputFile) {
			Remove-Item -LiteralPath $strOutputFile -ErrorAction SilentlyContinue
		}
	}
	
	if ($strChapterFile) {
		Remove-Item -LiteralPath $strChapterFile -ErrorAction SilentlyContinue
	}
}