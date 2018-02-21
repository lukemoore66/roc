Param (
	[string]$InputPath = '',
	[string]$Crf = '16',
	[string]$Preset = 'medium',
	[string]$OutputPath = "$PSScriptRoot\out",
	[string]$TempPath = "$PSScriptRoot",
	[switch]$SetupOnly = $false,
	[switch]$Copy = $false,
	[switch]$Help = $false,
	[string]$AudioBitrate = '',
	[string]$VideoCodec = 'libx264',
	[string]$AudioCodec = 'flac',
	[string]$SubCodec = 'ass',
	[switch]$Aggressive = $false,
	[string]$Offset = '40',
	[string]$EditionIndex = ''
)

#set version
$strVersion = "v0.9-beta 2018"

#Import Functions
. '.\libroc.ps1'

#set up an alias to make things easier for the user
Set-Alias -Name 'roc' -Value '.\roc.ps1' -Scope 1

#save and set the initial window title
$strInitialWinTitle=((Get-Host).UI.RawUI).WindowTitle
Set-WindowTitle 'roc' $RocSession

#show help if needed
Show-Help $Help

#show the version as needed
Show-Version $SetupOnly $RocSession $strVersion

#check the input parameters
#TODO: codecs
$intCrf = Check-Crf $Crf
$strPreset = Check-Preset $Preset
$strOutputPath = Check-OutputPath $OutputPath
$strTempPath = Check-OutputPath $TempPath
$strVideoCodec = Check-VideoCodec $VideoCodec
$strAudioCodec = Check-AudioCodec $AudioCodec
$strSubCodec = Check-SubCodec $SubCodec
$intAudioBitrate = Check-AudioBitrate $AudioBitrate
$floatOffsetTime = Check-OffsetTime $Offset
$boolAggressive = $Aggressive
$intChapEdition = Check-ChapEdition $EditionIndex

#get a list of input files
$listFiles = Get-Files $InputPath $true $true

#show the input file list and total count
Write-Host "`nInput File(s):`n"; Write-Host (($listFiles | % {Write-Host $_.Name}) + "`n" + `
@($listFiles).Count + " File(s) Found.`n")

#set up the codecs
$hashCodecs = Set-Codecs $Copy $strVideoCodec $strAudioCodec $strSubCodec $intAudioBitrate

#put everything in a try block to catch errors and clean up temp files easily
try {
	#initialize an array to store completed files
	$arrCompletedFiles = @()
	
	#initialize a counter so we know which file we are up to
	$intFileCounter = 1
	
	#start a loop to iterate though the list of files
	foreach ($objFile in $listFiles) {
		#write a progress message to the screen
		$strMessage = "Processing File $intFileCounter of " + $listFiles.Count
		Write-Host (('-' * $strMessage.Length) + "`n$strMessage`n" + ('-' * $strMessage.Length))

		#show the input file path
		Write-Host ("Input File: " + $objFile.FullName + "`n")

		#define the output file path and show it
		$strMkvMergeOutputFile = $strOutputPath + '\' + $objFile.BaseName + '.mkv'
		Write-Host  ("Output File: " + $strMkvMergeOutputFile + "`n")

		#Get the chapter info
		[xml]$xmlChapterInfo = .\bin\mkvextract.exe $objFile.FullName chapters -

		#get the default chapter edition entry
		$xmlChapterInfo = Get-ChapEdition $xmlChapterInfo $intChapEdition

		#make a hash table referencing external segment files by their segment id
		$hashSegmentFiles = Generate-FileSegmentHash $objFile

		#remove any invalid chapters
		$xmlChapterInfo = Remove-InvalidChapters $xmlChapterInfo $hashSegmentFiles
		
		#make an array of hashes containing encode commands for ffmpeg
		$arrEncCmds = Get-EncodeCommands $xmlChapterInfo $hashSegmentFiles `
		$boolAggressive $floatOffsetTime

		#fix the chapter entries now the encode commands have been generated
		$xmlChapterInfo = Fix-Chapters $xmlChapterInfo $boolAggressive $floatOffsetTime
			
		#define the chapter file output path
		$strChapterFile = $strTempPath + '\' + (Generate-RandomString) + '.xml'

		#save the chapter file to this output path
		$xmlChapterInfo.Save("$strChapterFile")

		#show the total output duration
		$floatTotalDuration = Get-TotalDuration $arrEncCmds
		Write-Host ("Total Output Duration: " + (ConvertTo-Sexagesimal $floatTotalDuration) + "`n")

		#generate a list of random file names for output files
		$arrOutputFiles = Get-OutputFiles $arrEncCmds $strTempPath

		#use ffmpeg to run the encode instructions
		Encode-Segments $arrEncCmds $hashCodecs $arrOutputFiles

		#set the mkvmerge output file name
		$strMmgOutputFile = $strTempPath + '\' + (Generate-RandomString) + '.mkv'

		#merge the segments with mkvmerge
		Merge-Segments $arrOutputFiles $strMmgOutputFile $strChapterFile $objFile.FullName
		
		#tidy up temp files
		Cleanup-Files $arrOutputFiles $strChapterFile $null $null
		
		#make a list of subtitle info
		$arrSubInfo = Get-SubInfo $strMmgOutputFile $strTempPath
		
		#define the output file name
		$strOutputFile = $strOutputPath + '\' + $objFile.BaseName + '.mkv'
		
		#remux the file
		Remux-Subs $strOutputFile $arrSubInfo $strMmgOutputFile
		
		#tidy up temp files
		Cleanup-Files $arrOutputFiles $strChapterFile $strMmgOutputFile $arrSubInfo

		#add the file to the completed file list
		$arrCompletedFiles = $objFile.FullName
		
		#Increment the file counter
		$intFileCounter++
		
		#show a file complete message
		Write-Host "Processing Complete."
	}
	
	#show any files that were skipped
	Show-SkippedFiles $arrCompletedFiles $listFiles
	
	#show completed message
	Write-Host "Script Complete."
}
catch {
	#show error messages
	Write-Host ("Error: Caught Exception At Line " + `
	$_.InvocationInfo.ScriptLineNumber + ":`n" + $_.Exception.Message)

	#tidy up temp files
	Cleanup-Files $arrOutputFiles $strChapterFile $strMmgOutputFile $arrSubInfo

	#set the window title back to normal if needed
	Set-WindowTitle $strInitialWinTitle $RocSession

	Write-Host ''
}
finally {
	#tidy up temp files
	Cleanup-Files $arrOutputFiles $strChapterFile $strMmgOutputFile $arrSubInfo

	#set the window title back to normal if needed
	Set-WindowTitle $strInitialWinTitle $RocSession

	Write-Host ''
}