# roc - Remove Ordered Chapters From Matroska Files

A PowerShell script that transcodes / remuxes Matroska files that use ordered chapters (e.g. external OP and ED files) into single Matroska files.

## Getting Started

Download the entire git folder i.e. use the 'Clone or Download' button above, then unzip everything to a folder of your choice and run roc.exe. At the prompt, type 'roc -help' to begin.

Example Usage:
```
roc -InputPath 'C:\Path\To\Matroska\Files\'
```

### Prerequisites

.NET 4.5 and Powershell v5. Windows 10 already meets these requirements out of the box. You may have to download these components if you are running an older version of Windows.

This script uses large temporary files when running, therefore, it is not recommended to run it off an SSD. You can manually specify the temp folder it uses with the -TempPath option if needed.

## Uses
[ffmpeg](https://www.ffmpeg.org/) - Transcoder

[mkvtoolnix](https://mkvtoolnix.download/index.html) - Muxer

[PurpleBooth](https://github.com/PurpleBooth) - Readme Template

[GraphicLoads](http://graphicloads.com/) - Program Icon

## Authors

* **Luke Moore** - *Initial work* - [d3sim8](https://github.com/lukemoore66)

## License

This project is licensed under the MIT License - see the [LICENSE.md](/res/LICENSE.md) file for details

## Acknowledgments

* Hat tip to ffmpeg and mkvtoolnix devs
* Inspiration: CoalGirls

