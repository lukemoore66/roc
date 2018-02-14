# roc - Remove Ordered Chapters From Matroska Files

Powershell Script That Transcodes / Remuxes Matroska Files That Use Ordered Chapters Into a Single Matroska File.

## Getting Started

Download and run roc.exe
At the prompt, type roc -help to begin.

Example Usage: roc -InputPath 'C:\Path\To\Matroska\Files\'

Options
InputPath A Valid File Or Folder Path For Input File(s).
Crf An Integer Ranging From 0-51. (AKA: Video Quality 14-25 Are Sane Values)
Preset x264 Preset. placebo, slowest, slower, slow, medium, fast, faster, ultrafast
OutputPath A Valid File Or Folder Path For Output File(s).
TempPath A Valid File Or Folder Path For Temporary File(s).
Copy Copies (Remuxes) Segments. Very Fast, But May Cause Playback Problems.
Help Shows The Help Menu.

### Prerequisites

.NET 4.5 and Powershell v5. Windows 10 already meets these requirements out of the box. You may have to download these components if you are running an older version.

## Uses
[ffmpeg](https://www.ffmpeg.org/) - Transcoder
[mkvtoolnix](https://mkvtoolnix.download/index.html) - Muxer
[PurpleBooth](https://github.com/PurpleBooth) - Readme Template

## Authors

* **Luke Moore** - *Initial work* - [d3sim8](https://github.com/lukemoore66)

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details

## Acknowledgments

* Hat tip to ffmpeg and mkvtoolnix devs
* Inspiration: CoalGirls

