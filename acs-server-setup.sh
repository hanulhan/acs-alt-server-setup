#!/bin/bash -eux

MOUNTPOINT=/mnt/s3
PATH_TO_FILE=/home/ubuntu/acs-alt-server-setup
PATH_TO_SCRIPT=$PATH_TO_FILE/acs-server-setup.sh
LOGFILE=$PATH_TO_FILE/acs-server-setup.log
UPDATE_STATE_FILE=$PATH_TO_FILE/update-state.txt
KEYSTORE_FILE=$PATH_TO_FILE/Tomcat/acentic.neu.keystore
WAR_FILE=ACS.war
TOMCAT7_USER_ID=106
TOMCAT7_GROUP_ID=111


export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical


#exec >> $LOGFILE 2>&1

PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:


# Function do set the update state to a file
function setUpdateState {
   UPDATE_STATE=$1
   doLog "Set the update State to $1"
   echo $UPDATE_STATE > $UPDATE_STATE_FILE
}

function doLog {
   echo $1
   echo $1 >> $LOGFILE
}

function doLogUpdateState {
    doLog "########## $1 ##########"
}

function package_exists() {
    dpkg -s $1 &> /dev/null
    return $?    
}

# $1 old uid
# $2 new uid
function changeUid () {
   local user=$( getent passwd "$1" | cut -d: -f1 )
   usermod -u $NEW_ID $user
   #find / -user $OLD_ID -exec chown -h $NEW_ID {} \;
   echo $user
}


# $1 old guid
# $2 new guid
# $3 user
function changeGid () {
   local group=$( getent group "$1" | cut -d: -f1 )
   groupmod -g $NEW_GROUP $group
   #find / -user $OLD_ID -exec chown -h $NEW_ID {} \;
   usermod -g $NEW_GROUP $user
   echo $group
}


#Check if Logfile already exists. 
if [ ! -f $LOGFILE ];
then
   touch $LOGFILE
   doLog "Start script"
else
   doLog "Restart script"
fi


#Check if the update-state-file already exists
if [ ! -f $UPDATE_STATE_FILE ];
then
    doLog "UpdateState file does not exists. Create it"
    touch $UPDATE_STATE_FILE
    setUpdateState 1
else
    UPDATE_STATE=$(< ${UPDATE_STATE_FILE})
    doLog "UpdateState= $UPDATE_STATE"
fi





case $UPDATE_STATE in


1) #Installation step 1. Update packages
   doLogUpdateState "UPDATE-STATE $UPDATE_STATE: Update packages list"


   # install cronjob to procede execution after restart
   doLog "==> install cronjob"
   echo "@reboot $PATH_TO_SCRIPT" > mycron
   crontab mycron
   rm mycron


   # Disable the release upgrader
   doLog "==> Disabling the release upgrader"
   if [ ! -f "/etc/update-manager/release-upgrades.001" ];
   then
      cp release-upgrades release.upgrades.001
      sed -i.bak 's/^Prompt=.*$/Prompt=never/' /etc/update-manager/release-upgrades
   fi

   doLog "==> Checking version of Ubuntu"
   . /etc/lsb-release

   if [[ $DISTRIB_RELEASE == 16.04 ]]; then
      systemctl disable apt-daily.service # disable run when system boot
      systemctl disable apt-daily.timer   # disable timer run
   else
      echo "Not $DISTRIB_RELEASE"
   fi
   

   # get the ubuntu package list
   apt-get -y update
   sleep 5
   doLog "==> Performing upgrade (all packages and kernel)"
   apt-get -q -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" upgrade
   sleep 5

   doLog "==> Performing dist-upgrade (all packages and kernel)"
   apt-get -q -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" dist-upgrade
   sleep 5

   apt-get -y autoremove

   doLog "==> Finished apt-get upgrade. Reboot now"
   setUpdateState 2
   echo "Mountpoint: $(findmnt -M "$MOUNTPOINT")"
   #reboot
   ;&

2) # Installation step 2: Ubuntu installation 1
   doLogUpdateState "UPDATE-STATE $UPDATE_STATE: bashrc and vimrc"

   if [ ! -f "/home/ubuntu/.bashrc.001" ];
   then
       cp /home/ubuntu/.bashrc /home/ubuntu/.bashrc.001
       cat $PATH_TO_FILE/bashrc >> /home/ubuntu/.bashrc
   fi
   
   if [ ! -f "/home/ubuntu/.vimrc" ];
   then
       echo "colorscheme desert" > /home/ubuntu/.vimrc
   fi
  

   setUpdateState 3
   ;&   # Fall through


3) # Installation step 3: Ubuntu installation 2

   doLogUpdateState "UPDATE-STATE $UPDATE_STATE: Ubuntu installation 2"

   doLog "change user rights for curl and wget"
   chmod 744 /usr/bin/curl
   chmod 744 /usr/bin/wget

   setUpdateState 4
   ;&   # Fall through

4) # Installation step 4: Ubuntu installation 3

   doLogUpdateState "UPDATE-STATE 4: disable ipv6"
   
   if [ $( cat /proc/sys/net/ipv6/conf/all/disable_ipv6) -ne 1 ];
   then
       doLog "==> 2.5 disable ipv6"
       echo "net.ipv6.conf.all.disable_ipv6=1"     >> /etc/sysctl.conf
       echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf
       echo "net.ipv6.conf.lo.disable_ipv6=2"      >> /etc/sysctl.conf
       sysctl -p
   else
       echo "ipv6 already disabled"
   fi   


   setUpdateState 5
   ;&   # Fall through
   
5) # Installation step 5: install s3fs

   doLogUpdateState "UPDATE-STATE 5: install packages for s3fs"
   
   PACKAGE='automake autotools-dev fuse g++ git libcurl4-gnutls-dev libfuse-dev libssl-dev libxml2-dev make pkg-config'
   apt-get -q -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" install $PACKAGE
   setUpdateState 6
   ;&   # Fall through

6) # Installation step 6:

   doLogUpdateState "UPDATE-STATE 6: make s3fs"

   if [ ! -d "/home/ubuntu/s3fs-fuse" ];
   then   
       cd /home/ubuntu 
       git clone https://github.com/s3fs-fuse/s3fs-fuse.git
       cd s3fs-fuse
       ./autogen.sh
       ./configure
       make
       make install
       cd $PATH_TO_FILE
   fi

   setUpdateState 7
   ;&   # Fall through

7) # Installation step 7:

   doLogUpdateState "UPDATE-STATE 7: create user and group for tomcat7"
   if [ ! $(cat /etc/group | grep -i 'tomcat7') ];
   then
      groupadd --system --gid $TOMCAT7_GROUP_ID tomcat7
   fi
   if [ ! $(cat /etc/passwd | grep -i 'tomcat7') ];
   then
      useradd  --system --uid $TOMCAT7_USER_ID --gid $TOMCAT7_GROUP_ID tomcat7
   fi
   setUpdateState 8
   ;&   # Fall through
   
8) # Installation step 8:

   doLogUpdateState "UPDATE-STATE 8: mount"

   if [ ! -d "/mnt/data" ];
   then
       mkdir /mnt/data
   fi   
   if [ ! -d "/mnt/bigdata" ];
   then
       mkdir /mnt/bigdata
   fi   
   if [ ! -d "/mnt/efs" ];
   then
       mkdir /mnt/efs
   fi
   
   chown tomcat7:tomcat7 /mnt/efs
   
   if [ ! $(mount | grep -i '/mnt/efs') ];
   then
       mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 fs-88941b41.efs.eu-west-1.amazonaws.com:/ /mnt/efs
   fi
   
   setUpdateState 10
   ;&   # Fall through
   
10) # Installation step 10: fstab

    doLogUpdateState "UPDATE-STATE 10: fstab"
   setUpdateState 14
   sleep 2
   ;&      # Fall through


14) # Installation step 14: Java

   doLogUpdateState "UPDATE-STATE 14: Java"
   
   PACKAGE=openjdk-8-jdk
   if ! package_exists $PACKAGE; then
      apt-get -q -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" install $PACKAGE
   else
       echo "$PACKAGE already installed"
   fi
  

   setUpdateState 16
   ;&      # Fall through

16) # Installation step 16: nfs-common

   doLogUpdateState "UPDATE-STATE 16: nfs common"
   PACKAGE=nfs-common
   if ! package_exists $PACKAGE; then
      apt-get -q -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" install $PACKAGE
   else
       echo "$PACKAGE already installed"
   fi
   
   setUpdateState 18
   ;&      # Fall through

18) # Install Tomcat7

   doLogUpdateState "UPDATE-STATE 18: Tomcat7 installation"

   PACKAGE=tomcat7
   if ! package_exists $PACKAGE; then
      apt-get -q -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" install $PACKAGE
   else
       echo "$PACKAGE already installed"
   fi
   setUpdateState 20
   ;&      # Fall through


20) # Setup Tomcat7

   doLogUpdateState "UPDATE-STATE 20: Tomcat7 setup"
   service tomcat7 stop

   doLog "==> Copy tomcat-server configuration files"
   mv /var/lib/tomcat7/conf/web.xml /var/lib/tomcat7/conf/web.xml.001
   mv /var/lib/tomcat7/conf/context.xml /var/lib/tomcat7/conf/context.xml.001
   mv /var/lib/tomcat7/conf/server.xml /var/lib/tomcat7/conf/server.xml.001
   cp $PATH_TO_FILE/Tomcat/conf/*.xml /var/lib/tomcat7/conf/
   chown -R root:tomcat7 /var/lib/tomcat7/conf/*.xml

   cp $PATH_TO_FILE/Tomcat/conf/setenv.sh /usr/share/tomcat7/bin
   chmod +x /usr/share/tomcat7/bin/setenv.sh
   
   if [ ! -d "/home/ubuntu/keystore" ];
   then
      mkdir /home/ubuntu/keystore
   fi

   cp $KEYSTORE_FILE /home/ubuntu/keystore
   chown -R tomcat7:tomcat7 /home/ubuntu/keystore
   
   cp $PATH_TO_FILE/Tomcat/virtualHost/*.xml /var/lib/tomcat7/conf/Catalina/localhost/
   
   echo '<% response.sendRedirect("/ACS"); %>' >  /var/lib/tomcat7/webapps/ROOT/index.jsp   

   if [ ! -d "/var/log/tomcat7" ];
   then
        mkdir /var/log/tomcat7
   fi
   
   chown tomcat7:tomcat7 /var/log/tomcat7
   ls -s /var/log/tomcat7 /var/lib/tomcat7
   chown -h tomcat7:tomcat7 /var/lib/tomcat7
   
   setUpdateState 22
   ;&

22)
   doLogUpdateState "UPDATE-State 22: Tomcat libs"

   cp $PATH_TO_FILE/Tomcat/lib/*.jar /usr/share/tomcat7/lib/
   chown tomcat7:tomcat7 /usr/share/tomcat7/lib/cas-client-core*
   chown tomcat7:tomcat7 /usr/share/tomcat7/lib/session-userPreference*
   chown tomcat7:tomcat7 /usr/share/tomcat7/lib/slf4j-api*
   chown tomcat7:tomcat7 /usr/share/tomcat7/lib/tomcat-catalina-jmx-remote*
   
   setUpdateState 25
   ;&

25)
   doLogUpdateState "UPDATE-State 25: disable tomcat runlevel"

   sudo update-rc.d tomcat7 disable
   setUpdateState 32
   ;&
   
32)
   doLogUpdateState "UPDATE-State 32: port freigabe"
   if [ ! -f "/etc/authbind/byport/80" ];
   then
      touch /etc/authbind/byport/80
      chmod 500 /etc/authbind/byport/80
      chown tomcat7 /etc/authbind/byport/80
   else
      echo "authbind for port 80 already exists"
   fi

   if [ ! -f "/etc/authbind/byport/443" ];
   then
      touch /etc/authbind/byport/443
      chmod 500 /etc/authbind/byport/443
      chown tomcat7 /etc/authbind/byport/443
   else
      echo "authbind for port 443 already exists"
   fi
  
   setUpdateState 34
   ;&   

34)
   doLogUpdateState "UPDATE-State 34: cron"

   doLog "==> delete crontab for ubuntu"
   crontab -r || true		# ignore error message


   doLog "==> 2.4 Allow root only to add cron job"

   if [ ! -f "/etc/cron.allow" ];
   then   
       echo "root" > /etc/cron.allow
   else
      echo "/etc/cron.allow already exists"
   fi

   if [ ! -f "/etc/cron.deny" ];
   then   
      echo "deamon
            bin
            smtp
            deamon
            nuucp
            listen
            nobody
            noaccess
            tomcat7
            ubunt" > /etc/cron.deny
   else
      echo "/etc/cron.deny already exists"
   fi

   setUpdateState 36
   ;&

36)
   doLogUpdateState "UPDATE-State 36: fonts"

   if [ ! -d "/mnt/efs/data/fonts" ];
   then
       mkdir /mnt/efs/data/fonts
       fc-cache -f /mnt/efs/data/fonts
   fi
   
   PACKAGE=ttf-mscorefonts-installer
   if ! package_exists $PACKAGE; then
      apt-get -q -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" install $PACKAGE
   else
      echo "$PACKAGE already exists"
   fi
   

  
   setUpdateState 38
   ;&

38)
   doLogUpdateState "UPDATE-State 38: ffmpeg"

   PACKAGE=ffmpeg
   if ! package_exists $PACKAGE; then
      apt-get -q -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" install $PACKAGE
   else
      echo "$PACKAGE already exists"
   fi
  
   setUpdateState 40
   ;&
   
40)
   doLogUpdateState "UPDATE-State 40: fstab"
   
    if [ ! -f "/etc/fstab.001" ];
    then
        cp /etc/fstab /etc/fstab.001
        cat $PATH_TO_FILE/fstab >> /etc/fstab
    fi

   
   setUpdateState 99
   ;&
   
99)
   doLogUpdateState "UPDATE-State 99: Start tomcat"
   
   doLog "==> copy war and start tomcat"
   #cp /home/ubuntu/$WAR_FILE /var/lib/tomcat7/webapps
   #sudo chown tomcat7:tomcat7 /var/lib/tomcat7/webapps/$WAR_FILE
   #service tomcat7 start
   setUpdateState 100
   ;&
   
   
100)

   touch $PATH_TO_FILE/UPDATE_FINISHED
   ;;

esac



















