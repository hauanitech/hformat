# Method 2

Basically moving your tool in a utility folder (recommended) or not 
then creating an alias pointing towards the script 

example : 

```sh
# must be inside the script folder

mkdir ~/Utils

mkdir ~/Utils/hformat
mv * ~/Utils/hformat

# ----Creating the alias--------

sudo echo \
"alias hformat='bash ~/Utils/hformat/hformat.sh'" >> ~/.bashrc
source ~/.bashrc
```

Simply run these commands and you'll ready to run `hformat` from your terminal

**to remove the alias you'll have to edit the ~/.bashrc file**
**then delete the hformat folder from the Utils folder**