# hformat - Bash Formatting Utility

<p align="center">A simple formatting utility script written in bash to help 
formatting in a simple way any external disks.
</p>

## Quickstart 

```sh
git clone https://github.com/hauanitech/hformat.git

chmod +x hformat
./hformat.sh
```

In order to have the tool installed on your machine as terminal command pick one of the
following methods :

[[method 1]](/docs/install_m1.md) (recommended)</br>
[[method 2]](/docs/install_m2.md)

## Usage

The easiest way to use this formatting utility is to use it this way

```sh
./hformat.sh --all -y
# basically formats every external disks (FAT32 + no label)
```

You may want to edit the default settings by opening up the configuration tab

```sh
./hformat.sh config

# Open an Interactive panel in the terminal
```

## Contribute

if you find this project useful drop a star or
open any pull requests if you find fixes / performance improvements
