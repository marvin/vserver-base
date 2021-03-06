#!/bin/bash
#install vserver stuff
#all files in vserver.d are enumerated. 
#each file may contain a package name, url, shell-command or package file name.
#
#Comments: each line starting with "#" is ignored
#
#url: 	each line that starts with http,https,ftp and ends with .dep is interpreted as
#	url. If the file is not already downloaded to the PKG_DIR, it is requested and
#	stored in PKG_DIR before installing it.
#e.g.:http://website.de/path/packet.dep
#
#package name:	a debian package name that should be installed
#e.g:bind9
#
#pre-command: a shell command that is executed AFTER installing packages
#pre-cmd: rm /etc/apache2/site-enabled/*
#
#post-command:	a shell command is exectuted AFTER installing packages and files. a temporary file is created with all the commands
#post-cmd:a2enmod ssl


PKG_DIR=dl
LIST_DIR=vserver.d
FILES=files
PREINSTALL=/tmp/vserver-preinstall.sh
POSTINSTALL=/tmp/vserver-postinstall.sh

rm -rf $PREINSTALL $POSTINSTALL
> $PREINSTALL
chmod 755 $PREINSTALL
> $POSTINSTALL
chmod 755 $POSTINSTALL

apt-get update
apt-get dist-upgrade

for i in ./$LIST_DIR/[0-9][0-9][0-9]-*
do
 	echo "----- $i ----"
	IFS='
'
	for p in $(cat $i | sed 's/^#.*$//' | sed 's#\t\+.*$##')
	do
#	echo "[$p]"
		#check for url
	 	url="$(echo $p | sed -n '/^\(http\|https\|ftp\):\/\/.*.deb$/p')"	
		if [ ! "$url" = "" ]; then
			#echo "==URL:$url=="
			file="$(echo $url | sed -n '/^\(http\|https\|ftp\):\/\/.*.deb$/{s#.*/\(.*\.deb$\)#\1#;p}')"
			#echo "--FILE:$PKG_DIR/$file"
			test ! -f $PKG_DIR/$file && wget -O $PKG_DIR/$file $url
			dpkg -i $PKG_DIR/$file
		else
#echo "######1 $p-${p%%:*}"
			#check if a program should be called
			if [ "${p%%:*}" = "pre-cmd" ]; then
				cmd="${p#pre-cmd:}"
				echo "$cmd" >> $PREINSTALL
				continue
			fi
#echo "######2 $p-${p%%:*}"
			if [ "${p%%:*}" = "post-cmd" ]; then
				cmd="${p#post-cmd:}"
				echo "$cmd" >> $POSTINSTALL
				continue
			fi
#echo "######3 $p"


			#check if we should use apt-get or dpkg
			if [ "${p##*.}" = "deb" ]; then
				dpkg -i $PKG_DIR/$p
			else 
				apt-get --yes install $p
			fi
		fi
	done
done

echo "========================================================="
echo "running pre-commands"
$PREINSTALL $FILES

echo "========================================================="
echo "copy files"
cp -r -d --preserve $FILES/* /

echo "========================================================="
echo "running post-commands"
$POSTINSTALL $FILES

echo "========================================================="
echo "finished."

