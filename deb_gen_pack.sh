#!/bin/bash

function program_is_installed {
  # set to 1 initially
  local return_=1
  # set to 0 if not found
  type $1 >/dev/null 2>&1 || { local return_=0; }
  # return value
  echo "$return_"
}

# check if jq is intalled for json read
if [ $(program_is_installed jq ) == 0 ]
then
  sudo apt-get install jq
fi


NAME=`cat gen_deb.json | jq -r '."name"'`
VERSION=`cat gen_deb.json | jq -r '."version"'`
DESCRIPTION=`cat gen_deb.json | jq -r '."description"'`
NODE_VERSION=`cat gen_deb.json | jq -r '."node_version"'`
MAIN=`cat gen_deb.json | jq -r '."main"'`

# generate folder structure
mkdir -p debinstall/deb-src/{DEBIAN,sysroot/{etc/init,usr/share/doc/$NAME}}

DEBIAN_DIR=debinstall/deb-src/DEBIAN/

# generate necessary files
# change directory for debian
cd $DEBIAN_DIR

# Control file
cat <<CONTROL > control
Package: $NAME
Version: $VERSION
Section: base
Priority: optional
Architecture: amd64
Installed-Size: SIZE
Depends:
Maintainer: Ginga One Devops <devops@gingaone.com>
Description: $DESCRIPTION

CONTROL

# prerm file
cat <<PRERM > prerm
#!/bin/bash
# Stop application before installing
#pm2 stop $NAME
PRERM

cat <<PREINST > preinst
#!/bin/bash

# AddUser
if id ginga >/dev/null 2>&1; then
  echo "User ginga already created"
else
  sudo useradd ginga -s /sbin/nologin #&& su -s /bin/bash ginga
  sudo mkdir -p /home/ginga
  sudo chmod -R 0755 /home/ginga
  sudo chown -R ginga:ginga /home/ginga
  sudo chown -R ginga:ginga /opt/gingasystems/apps/$NAME
  sudo echo "ginga ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ginga
  echo "User ginga created"
fi
as

sudo -H -u ginga /bin/bash -c '

  # Donwload, install, and activate nvm
  if ! type nvm > /dev/null; then
    #su -s /bin/bash ginga
    # donwload and install nvm
    echo "Installing NVM for \$USER"
    #curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.0/install.sh | bash
    wget -qO- https://raw.githubusercontent.com/creationix/nvm/v0.33.0/install.sh | bash

cat <<EOTBASH >> /home/ginga/.bashrc
export NVM_DIR="/home/ginga/.nvm"
[ -s "/home/ginga/.nvm/nvm.sh" ] && . "/home/ginga/.nvm/nvm.sh"
EOTBASH

    source /home/ginga/.bashrc

    echo "Installing Node for \$USER"
    # Installing specific node version for project
    nvm install $NODE_VERSION
  fi

  # Install PM2
  if ! type pm2 > /dev/null;
    #echo "Pm2 Installed"
  then
    echo "Installing pm2"
    npm install pm2 -g
  fi
'

PREINST

cat <<POSTINST > postinst
#!/bin/bash
# Stop application before installing
sudo -H -u ginga /bin/bash -c '
  source /home/ginga/.bashrc
  echo "Change directory to /opt/gingasystems/apps/$NAME"
  cd /opt/gingasystems/apps/$NAME
  echo "Current Directory"
  pwd
  npm install
  pm2 start $MAIN --name="$NAME" -i 4
'
POSTINST

# Setting right permission for control files
chmod -R 755 ../DEBIAN/

cd ../sysroot/etc/init/
cat <<CONF > $NAME.conf
# System Service $NAME
description "System Service $NAME"

start on filesystem
stop on runlevel [06]

console output
respawn

script
  PATH="/opt/gingasystems/apps/$NAME/:/usr/local/bin:/usr/bin:\$PATH"
  pm2 start $MAIN --name="$NAME" -i 4
  # pm2 restart /opt/gingasystems/apps/$NAME/server/index.js
end script
CONF

cd ../../../../../

# Generate .deb
set -u
set -e

SRC=/tmp/$NAME-src
DIST=/tmp/$NAME-dist
SYSROOT=$SRC/sysroot
DEBIAN=$SRC/DEBIAN

rm -rf $DIST
mkdir -p $DIST/

rm -rf $SRC

mkdir -p $SRC/
rsync -a debinstall/deb-src/ $SRC/
mkdir -p $SYSROOT/opt/gingasystems/apps/$NAME

rsync -a $NAME/ $SYSROOT/opt/gingasystems/apps/$NAME --delete


find $SRC/ -type d -exec chmod 0755 {} \;
find $SRC/ -type f -exec chmod go-w {} \;
chown -R root:root $SRC/

#SIZE=`du -s $SYSROOT | sed s'/[0-9]+//'` # s'/\s\+.*//'`
SIZE=`du -s $SYSROOT  | grep -o -E '[0-9]+' | head -1 | sed -e 's/^0\+//'`

pushd $SYSROOT/
tar czf $DIST/data.tar.gz [a-z]*
popd

sed -i -e "s/SIZE/$SIZE/g" $DEBIAN/control

pushd $DEBIAN
tar czf $DIST/control.tar.gz *
popd

pushd $DIST/
echo 2.0 > ./debian-binary

find $DIST/ -type d -exec chmod 0755 {} \;
find $DIST/ -type f -exec chmod go-w {} \;
chown -R root:root $DIST/
ar r $DIST/$NAME.deb debian-binary control.tar.gz data.tar.gz
popd

rsync -a $DIST/$NAME.deb ./

