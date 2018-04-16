# Mi Pay Extractor
Extract Mi Pay from MIUI China Rom

[![Build Status](https://travis-ci.org/linusyang92/mipay-extract.svg)](https://travis-ci.org/linusyang92/mipay-extract)

## Usage
Put MIUI 9 China Rom (OTA zip package) in the directory and double-click `extract.bat` (Windows) or run `./extract.sh` (macOS and Linux) to generate the flashable zip.

Support Windows, Linux and macOS (10.10 or above). Windows version has all dependencies included. For macOS, you need Java 8 runtime. For Linux, you may need both Java 8 and Python 2.7. For example, you can install all dependencies using `apt-get`:

```bash
apt-get install -y openjdk-8-jre python2.7
```

Automatic builds for selected devices are available in [releases](https://github.com/linusyang92/mipay-extract/releases).

## Credits

* sdat2img
* progress (by @verigak)
* smali/baksmali
* SuperR's Kitchen

## Disclaimer
This repository is provided with no warranty. Make sure you have legal access to MIUI Roms if using this repository. If any files of this repository violate your copyright, please contact me to remove them.

## License
[![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
