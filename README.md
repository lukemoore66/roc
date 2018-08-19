# roc - Remux Ordered Chapters - From Segemnted Matroska Files

A PowerShell script that transcodes / remuxes Matroska files that use ordered chapters (e.g. external OP and ED segments) into single Matroska files.

## Getting Started

Download the entire git folder i.e. use the 'Clone or Download' button above, then unzip everything to a folder of your choice and run roc.exe. You will then be presented with a prompt.

To begin, type:

```
roc -Help
```
and press Enter.


Typical usage looks like this:
```
roc -InputPath 'C:\Path\To\Matroska\Files\'
```

Don't forget the quotation marks around file and folder paths, they are needed for PowerShell to take things literally. Files and folders can also be dragged and dropped into the PowerShell window.

### Prerequisites

PowerShell 3.0 or higher is required. Windows 8 and 10 have it installed by default. You may have to download the latest [Windows Management Framework](https://www.microsoft.com/en-us/download/details.aspx?id=54616) (which includes PowerShell) manually if you are running an older version of Windows. This script will only run on Windows.

This script uses large temporary files when running, therefore, it is not recommended to run it off an SSD. You can manually specify the temp folder it uses with the -TempPath option if needed.

## Uses
[ffmpeg](https://www.ffmpeg.org/) - Transcoder

[mkvtoolnix](https://mkvtoolnix.download/index.html) - Muxer

[PurpleBooth](https://github.com/PurpleBooth) - Readme Template

[GraphicLoads](http://graphicloads.com/) - Program Icon

## Authors

* **Luke Moore** - [lukemoore66](https://github.com/lukemoore66)

## License

This project is licensed under the MIT License - see the [LICENSE.md](/res/LICENSE.md) file for details

## Acknowledgments

* Hat tip to ffmpeg and mkvtoolnix devs
* Inspiration: CoalGirls

