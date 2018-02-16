Param (
	[string]$InputPath = '',
	[int]$Crf = 16,
	[string]$Preset = 'medium',
	[string]$OutputPath = "$PSScriptRoot\out",
	[string]$TempPath = "$PSScriptRoot",
	[switch]$SetupOnly = $false,
	[switch]$Copy = $false,
	[switch]$Help = $false,
	[string]$VideoCodec = 'libx264',
	[string]$AudioCodec = 'flac',
	[string]$SubCodec = 'ass'
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
$listFiles = Get-Files $InputPath $true $true
$intCrf = Check-Crf $Crf
$strPreset = Check-Preset $Preset
$strOutputPath = Check-OutputPath $OutputPath
$strTempPath = Check-OutputPath $TempPath

#set up the codecs
$hashCodecs = Set-Codecs -CopyMode $Copy -Video $VideoCodec -Audio $AudioCodec -Sub $SubCodec

#put everything in a try loop to catch errors and clean up temp files easily
try {
	#init a counter so we know which file we are up to
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
		$xmlChapterInfo = Get-DefaultEdition $xmlChapterInfo

		#make a hash table referencing external segment files by their segment id
		$hashSegmentFiles = Generate-FileSegmentHash $objFile

		#remove any invalid chapters
		$xmlChapterInfo = Remove-InvalidChapters $xmlChapterInfo $hashSegmentFiles

		#make an array of hashes containing encode commands for ffmpeg
		$arrEncCmds = Get-EncodeCommands $xmlChapterInfo $hashSegmentFiles

		#fix the chapter entries now the encode commands have been generated
		$xmlChapterInfo = Fix-Chapters $xmlChapterInfo

		#define the chapter file output path
		$strChapterFile = $strTempPath + '\' + (Generate-RandomString) + '.xml'

		#save the chapter file to this output path
		$xmlChapterInfo.Save("$strChapterFile")

		#show the total output duration
		$floatTotalDuration = Get-TotalDuration $arrEncCmds
		Write-Host ("Total Output Duration: " + (ConvertTo-Sexagesimal $floatTotalDuration) + "`n")

		#generate a list of random file names for output files
		(1..($arrEncCmds.Count)) | % {[array]$arrOutputFiles += "$strTempPath\" + `
		(Generate-RandomString) + '.mkv'}

		#run the encode instructions, return an array of file for mkvmerge to process
		Encode-Segments $arrEncCmds $hashCodecs $arrOutputFiles

		#set the output file name for mkv merge
		$strMkvMergeOutputFile = $strOutputPath + '\' + $objFile.BaseName + '.mkv'

		#merge the segments with mkvmerge
		Merge-Segments $arrOutputFiles $strMkvMergeOutputFile $strChapterFile

		#tidy up temp files
		Cleanup-Files $arrOutputFiles $strChapterFile

		#Increment the file counter
		$intFileCounter++
	}

	Write-Host "Complete."
}
catch {
	#show error messages
	Write-Host -ForegroundColor Yellow ("Error: Caught Exception At Line " + `
	$_.InvocationInfo.ScriptLineNumber + ":`n" + $_.Exception.Message)

	#tidy up temp files
	Cleanup-Files $arrOutputFiles $strChapterFile

	#set the window title back to normal if needed
	Set-WindowTitle $strInitialWinTitle $RocSession

	Write-Host ''
}
finally {
	#tidy up temp files
	Cleanup-Files $arrOutputFiles $strChapterFile

	#set the window title back to normal if needed
	Set-WindowTitle $strInitialWinTitle $RocSession

	Write-Host ''
}