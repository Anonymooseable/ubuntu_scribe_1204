#!/bin/bash
#Christophe Deze - Rectorat de Nantes
#script d'integration de station ubuntu 10.10 sur un scribe NG
#testé avec Scribe 2.2.2
#
# version 1.0.1
# Run as root, of course.
if [ "$UID" -ne "0" ]
then
  echo "Il faut etre root pour executer ce script. ==> sudo "
  exit 
fi 
. /etc/lsb-release
if [ "$DISTRIB_RELEASE" != "12.04" ]
then 
	echo " pas ubuntu 12.04"
	exit
fi


ipscribepardefaut="192.168.0.99"
ipscribe=""
#export http_proxy=""
echo "Donnez l'ip du scribe par défaut : $ipscribepardefaut "
read ipscribe

if [ "$ipscribe" == "" ]
then
 echo "ip non renseignée"
 ipscribe=$ipscribepardefaut
fi
echo "scribe = "$ipscribe

#rendre debconf silencieux
export DEBIAN_FRONTEND="noninteractive"
export DEBIAN_PRIORITY="critical"
#installation des paquets necessaires
apt-get update
apt-get install -y ldap-auth-client  libpam-mount   smbfs nscd

#Fichiers de config

# /etc/ldap.conf
echo "
# /etc/ldap.conf
host $ipscribe
base o=gouv, c=fr
nss_override_attribute_value shadowMax 999
" > /etc/ldap.conf



#auth ldap
echo "[open_ldap]
nss_passwd=passwd:  files ldap
nss_group=group: files ldap 
nss_shadow=shadow: files ldap 
nss_netgroup=netgroup: nis
" > /etc/auth-client-config/profile.d/open_ldap
#application de la conf nsswitch
auth-client-config -t nss -p open_ldap
#modules PAM mkhomdir pour pam-auth-update
echo "Name: Make Home directory
Default: yes
Priority: 128
Session-Type: Additional
Session:
        optional                        pam_mkhomedir.so silent
" > /usr/share/pam-configs/mkhomedir
# mise en place de la conf pam.d
pam-auth-update consolekit  ldap  libpam-mount  unix mkhomedir --force


#on remet debconf dans sa conf initiale
export DEBIAN_FRONTEND="dialog"
export DEBIAN_PRIORITY="high" 

########################################################################
#parametrage du script de demontage du netlogon pour lightdm
########################################################################
touch /etc/lightdm/logonscript.sh
grep "if mount | grep -q \"/tmp/netlogon\" ; then umount /tmp/netlogon ;fi" /etc/lightdm/logonscript.sh >/dev/null
if [ $? == 0 ]
then
  echo "Presession Ok"
else
  echo "if mount | grep -q \"/tmp/netlogon\" ; then umount /tmp/netlogon ;fi" >> /etc/lightdm/logonscript.sh
fi
chmod +x /etc/lightdm/logonscript.sh

touch /etc/lightdm/logoffscript.sh
echo "sleep 2 \
umount -f /tmp/netlogon \ 
umount -f \$HOME
" > /etc/lightdm/logoffscript.sh
chmod +x /etc/lightdm/logoffscript.sh

echo "GVFS_DISABLE_FUSE=1" >> /etc/environment

########################################################################
#Paramétrage pour remplir pam_mount.conf
########################################################################

homes="<volume user=\"*\" fstype=\"cifs\" server=\"$ipscribe\" ssh=\"0\" path=\"perso\" mountpoint=\"~\" sgrp=\"DomainUsers\" />"
netlogon="<volume user=\"*\" fstype=\"cifs\" server=\"$ipscribe\" path=\"netlogon\" mountpoint=\"/tmp/netlogon\"  sgrp=\"DomainUsers\" />"
eclairng="<volume user=\"*\" fstype=\"cifs\" server=\"$ipscribe\" path=\"eclairng\" mountpoint=\"/media/Partages Scribe\" sgrp=\"DomainUsers\" />"

grep "/media/Partages Scribe" /etc/security/pam_mount.conf.xml  >/dev/null
if [ $? != 0 ]
then
  sed -i "/<\!-- Volume definitions -->/a\ $eclairng" /etc/security/pam_mount.conf.xml
else
  echo "eclairng deja present"
fi

grep "mountpoint=\"~\"" /etc/security/pam_mount.conf.xml  >/dev/null
if [ $? != 0 ]
then
  sed -i "/<\!-- Volume definitions -->/a\ $homes" /etc/security/pam_mount.conf.xml
else
  echo "homes deja present"
fi

grep "/tmp/netlogon" /etc/security/pam_mount.conf.xml  >/dev/null
if [ $? != 0 ]
then
  sed -i "/<\!-- Volume definitions -->/a\ $netlogon" /etc/security/pam_mount.conf.xml
else
  echo "netlogon deja present"
fi

########################################################################
#nosuid,nodev,loop,encryption,fsck,nonempty,allow_root,allow_other
#options de montages
########################################################################
mntoptions="<cifsmount>mount -t cifs //%(SERVER)/%(VOLUME) %(MNTPT) -o \"noexec,nosetuids,mapchars,cifsacl,serverino,nobrl,iocharset=utf8,user=%(USER),uid=%(USERUID)%(before=\\",\\" OPTIONS)\"</cifsmount>"

grep "<cifsmount>mount -t cifs //%(SERVER)/%(VOLUME) %(MNTPT) -o \"noexec,nosetuids,mapchars,cifsacl,serverino,nobrl,iocharset=utf8,user=%(USER),uid=%(USERUID)%(before=\\",\\" OPTIONS)\"</cifsmount>" /etc/security/pam_mount.conf.xml  >/dev/null
if [ $? != 0 ]
then
  sed -i "/<\!-- pam_mount parameters: Volume-related -->/a\ <cifsmount>mount -t cifs //%(SERVER)/%(VOLUME) %(MNTPT) -o \"noexec,nosetuids,mapchars,cifsacl,serverino,nobrl,iocharset=utf8,user=%(USER),uid=%(USERUID)%(before=\\",\\" OPTIONS)\"</cifsmount>" /etc/security/pam_mount.conf.xml
else
  echo "mount.cifs deja present"
fi

grep "umount //$ipscribe/perso"  /etc/security/pam_mount.conf.xml  >/dev/null
if [ $? != 0 ]
then
  sed -i "/<mkmountpoint enable=\"1\" remove=\"true\" \/>/a\ <umount> umount \/\/$ipscribe\/perso<\/umount><umount>umount \/\/$ipscribe\/netlogon<\/umount><umount>umount \/\/$ipscribe\/eclairng <\/umount>" /etc/security/pam_mount.conf.xml
else
  echo "unmount perso deja present"
fi

#/etc/profile
echo "
export LC_ALL=fr_FR.utf8
export LANG=fr_FR.utf8
export LANGUAGE=fr_FR.utf8
" >> /etc/profile
#ne pas creer les dossiers par defaut dans home
sed -i "s/enabled=True/enabled=False/g" /etc/xdg/user-dirs.conf

# les profs peuvent sudo
grep "%DomainAdmins ALL=(ALL) ALL" /etc/sudoers > /dev/null; if [ $?!=0 ];then sed -i "/%admin ALL=(ALL) ALL/a\%DomainAdmins ALL=(ALL) ALL" /etc/sudoers; else echo "prof deja dans sudo";fi 

########################################################################
#parametrage du lightdm.conf
#activation du pave numerique par greeter-setup-script=/usr/bin/numlockx on
########################################################################
echo "
[SeatDefaults]
  user-session=ubuntu
  greeter-session=unity-greeter
  allow-guest=false
  greeter-show-manual-login=true
  greeter-hide-users=true
  session-setup-script=/etc/lightdm/logonscript.sh
  session-cleanup-script=/etc/lightdm/logoffscript.sh
" > /etc/lightdm/lightdm.conf

#/etc/security/group.conf
grep "*;*;*;Al0000-2400;floppy,audio,cdrom,video,plugdev,scanner" /etc/security/group.conf  >/dev/null; if [ $? != 0 ];then echo "*;*;*;Al0000-2400;floppy,audio,cdrom,video,plugdev,scanner" >> /etc/security/group.conf; else echo "group.conf ok";fi

#supression de l'applet fast-user-switch-applet
#gconftool --direct --config-source xml:readwrite:/etc/gconf/gconf.xml.mandatory --type bool --set '/desktop/gnome/lockdown/disable_user_switching' true
gconftool --direct --config-source xml:readwrite:/etc/gconf/gconf.xml.mandatory --type list --list-type=string --set '/apps/panel/default_setup/general/applet_id_list' '[clock,notification_area,show_desktop_button,window_list,workspace_switcher,trashapplet]'

sed -i "s/X-GNOME-Autostart-enabled=true/X-GNOME-Autostart-enabled=false/g" /etc/xdg/autostart/nm-applet.desktop

echo "reboot necessaire"
