function Get-TotalDuration ($arrEncList) {
	#get the total output duration for display
	$floatTotalDuration = 0.0
	foreach ($Inst in $arrEncInst) {
		$floatTotalDuration = $floatTotalDuration + ($Inst.end - $Inst.start)
	}
	
	return $floatTotalDuration
}

function ShowMissingAtoms ($xmlChapterInfo) {
	#get missing chapter atoms for display
	$arrMissAtoms = @()
	$intCount = 0
	foreach ($ChapAtom in $xmlChapterInfo.Chapters.EditionEntry.ChapterAtom) {
		if ($chapAtom.ChapterSegmentUID) {
			if ($chapAtom.ChapterFlagEnabled -eq '0') {
				$arrMissAtoms = $arrMissAtoms + $intCount
			}
		}
		$intCount++
	}
	
	#Show Missing Atoms Warning
	if ($arrMissAtoms.Count -ne 0) {
		if ($arrMissAtoms.Count -gt 1) {
		$strChapterAtoms = ($arrMissAtoms[0..($arrMissAtoms.Count - 2)] -join ', ') + ' and ' +  $arrMissAtoms[-1]
		Write-Host "Warning: Missing Chapter Atoms $strChapterAtoms`nThese Will Automatically Be Skipped.`n"
		}
		else {
			Write-Host ("Warning: Missing Chapter Atom " + $arrMissAtoms[0] + "`nIt Will Automatically Be Skipped.`n")
		}
	}
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

function Set-WindowTitle ($strWinTitle) {
	if ($strWinTitle) {
		$strWinTitle=((Get-Host).UI.RawUI).WindowTitle=$strWinTitle
	}
	else {		
		#Handle The Error
		$strErrorMessage="Could Not Set Window Title"
		Handle-Error $MyInvocation.MyCommand $strErrorMessage $false $strErrorLog $null $null
	}
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
	$intCount=0
	
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
		Remove-Item -LiteralPath $strOutputFile -ErrorAction SilentlyContinue
	}
	
	if ($strChapterFile) {
		Remove-Item -LiteralPath $strChapterFile -ErrorAction SilentlyContinue
	}
}