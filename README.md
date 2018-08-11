# Mi Pay Extractor
Extract Mi Pay from MIUI China Rom

[![Build Status](https://travis-ci.org/linusyang92/mipay-extract.svg)](https://travis-ci.org/linusyang92/mipay-extract)

**Use at your own risk!**

## Usage
Put MIUI 9 China Rom (OTA zip package) in the directory and double-click `extract.bat` (Windows) or run `./extract.sh` (macOS and Linux) to generate the flashable zip.

Additionally, if you want to recover Chinese functions, e.g. bus card shortcut or quick payments for WeChat/Alipay in "App Vault" (i.e. the leftmost shortcut page on home screen), you can add an option `--appvault`: `extract.bat --appvault` (Windows) or `./extract.sh --appvault` (macOS and Linux). An extra flashable zip file with prefix `eufix-appvault` will be generated.

Support Windows, Linux and macOS (10.10 or above). Windows version has all dependencies included. For macOS, you need Java 8 runtime. For Linux, you may need both Java 8 and Python 2.7. For example, you can install all dependencies using `apt-get`:

```bash
apt-get install -y openjdk-8-jre python2.7
```

Automatic builds for selected devices are available in [releases](https://github.com/linusyang92/mipay-extract/releases).

## Recover Chinese Functions

For users in China, you can also download the **xiaomi.eu rom** and run `cleaner-fix.sh` for creating a flashable zip with prefix `eufix`. It contains patches to

* Show Lunar dates in Calendar app.
* Fix FC of cleaner app.
* Show payment monitor options in setting page of Security app.
* Use Chinese weather sources in Weather app.

## (Optional) Encryption for xiaomi.eu ROMs

It is recommended to enable encryption if you plan to use Mi Pay. Official MIUI roms (China or International) has encryption enabled by default. But xiaomi.eu roms **remove encryption** by default (check in "Settings-Privacy-Encryption"). Some early versions of EU roms have bootloop bugs when enabling encryption in Settings (**Backup before trying!**).

If your device cannot be encrypted normally in Settings, you can completely **format `/data/` partition** and flash the additional zip file `eufix-force-fbe-oreo.zip` after flashing xiaomi.eu ROM.

**Warning**: Formatting `/data` will destroy **EVERYTHING**, including all your personal data and external storage (`/sdcard`). Remember to backup before formatting. Once your `/data` partition is encrypted, it will be kept encrypted through system updates.

## Credits

* sdat2img
* progress (by @verigak)
* smali/baksmali
* SuperR's Kitchen
* vdexExtractor
* Google Android SDK
* p7zip

## Disclaimer
This repository is provided with no warranty. Make sure you have legal access to MIUI Roms if using this repository. If any files of this repository violate your copyright, please contact me to remove them.

## License
[![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
