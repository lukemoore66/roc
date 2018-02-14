# roc
roc - Remove Ordered Chapters

Powershell Script

Re-encodes / Remuxes Matroska Files That Use Ordered Chapters Into a Single Matroska File.

Example Usage: roc -InputPath 'C:\Path\To\Matroska\Files\'

Options:
	[-InputPath] <String>]	- A Valid File Or Folder Path For Input File(s).
	[-Crf <Int>]		- An Integer Ranging From 0-51. (AKA: Video Quality 14-25 Are Sane Values)
	[-Preset <String>]	- x264 Preset. placebo, slowest, slower, slow, medium, fast, faster, ultrafast
	[-OutputPath <String>]	- A Valid File Or Folder Path For Output File(s).
	[-TempPath <String>]	- A Valid File Or Folder Path For Temporary File(s).
	[-Copy <Switch>]	- Copies (Remuxes) Segments. Very Fast, But May Cause Playback Problems.
	[-Help <Switch>]	- Shows This Help Menu.
