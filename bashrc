if [[ $- == *i* ]];
then
    bind '"\e[A": history-search-backward'
    bind '"\e[B": history-search-forward'
fi

INSTANCEID="`sudo curl -s http://169.254.169.254/latest/meta-data/instance-id`"
SERVER_IDENTIFIER=$INSTANCEID
EC2_SECURITY_GROUP="`sudo wget -q -O - http://instance-data/latest/meta-data/security-groups || die \"wget security-zone has failed: $?\"`"

if [ "$color_prompt" = yes ]; 
    then PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@$EC2_SECURITY_GROUP\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@$EC2_SECURITY_GROUP:\w\$'
fi

