#!/bin/bash
#Christophe Deze - Rectorat de Nantes
#Cédric Frayssinet - Mission Tice Ac-lyon
#Xavier GAREL - Mission Tice Ac-lyon
#############################################
#Script d'integration de station ubuntu 12.04 sur un scribe 2.x
#testé avec Scribe 2.3
#############################################
# version 1.1
# Run using sudo, of course.
#############################################
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


ipscribepardefaut="172.16.0.241"
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
apt-get install -y ldap-auth-client libpam-mount smbfs nscd numlockx

########################################################################
# Configuration du fichier pour le LDAP /etc/ldap.conf
########################################################################
echo "
# /etc/ldap.conf
host $ipscribe
base o=gouv, c=fr
nss_override_attribute_value shadowMax 999
" > /etc/ldap.conf

########################################################################
# activation des groupes des users du ldap
########################################################################
echo "Name: activate /etc/security/group.conf
Default: yes
Priority: 900
Auth-Type: Primary
Auth:
        required                        pam_group.so use_first_pass" > /usr/share/pam-configs/my_groups

########################################################################
#auth ldap
########################################################################
echo "[open_ldap]
nss_passwd=passwd:  files ldap
nss_group=group: files ldap
nss_shadow=shadow: files ldap
nss_netgroup=netgroup: nis
" > /etc/auth-client-config/profile.d/open_ldap

########################################################################
#application de la conf nsswitch
########################################################################
auth-client-config -t nss -p open_ldap

########################################################################
#modules PAM mkhomdir pour pam-auth-update
########################################################################
echo "Name: Make Home directory
Default: yes
Priority: 128
Session-Type: Additional
Session:
       optional                        pam_mkhomedir.so silent
" > /usr/share/pam-configs/mkhomedir

grep "auth    required     pam_group.so use_first_pass"  /etc/pam.d/common-auth  >/dev/null; if [ $? == 0 ];then echo "/etc/pam.d/common-auth Ok"; else echo  "auth    required     pam_group.so use_first_pass" >> /etc/pam.d/common-auth;fi

########################################################################
# mise en place de la conf pam.d
########################################################################
pam-auth-update consolekit ldap libpam-mount unix mkhomedir my_groups --force

########################################################################
# mise en place des groupes pour les users ldap dans /etc/security/group.conf
########################################################################
grep "*;*;*;Al0000-2400;floppy,audio,cdrom,video,plugdev,scanner" /etc/security/group.conf  >/dev/null; if [ $? != 0 ];then echo "*;*;*;Al0000-2400;floppy,audio,cdrom,video,plugdev,scanner" >> /etc/security/group.conf; else echo "group.conf ok";fi

########################################################################
#on remet debconf dans sa conf initiale
########################################################################
export DEBIAN_FRONTEND="dialog"
export DEBIAN_PRIORITY="high"

########################################################################
#parametrage du script de demontage du netlogon pour lightdm
########################################################################
touch /etc/lightdm/logonscript.sh
grep "if mount | grep -q \"/tmp/netlogon\" ; then umount /tmp/netlogon ;fi" /etc/lightdm/logonscript.sh  >/dev/null
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

# echo "GVFS_DISABLE_FUSE=1" >> /etc/environment

########################################################################
#Paramétrage pour remplir pam_mount.conf
########################################################################

eclairng="<volume user=\"*\" fstype=\"cifs\" server=\"$ipscribe\" path=\"eclairng\" mountpoint=\"/media/scribe\" />"
grep "/media/scribe" /etc/security/pam_mount.conf.xml  >/dev/null
if [ $? != 0 ]
then
  sed -i "/<\!-- Volume definitions -->/a\ $eclairng" /etc/security/pam_mount.conf.xml
else
  echo "eclairng deja present"
fi

homes="<volume user=\"*\" fstype=\"cifs\" server=\"$ipscribe\" path=\"perso\" mountpoint=\"~/Documents\" />"
grep "mountpoint=\"~\"" /etc/security/pam_mount.conf.xml  >/dev/null
if [ $? != 0 ]
then sed -i "/<\!-- Volume definitions -->/a\ $homes" /etc/security/pam_mount.conf.xml
else
  echo "homes deja present"
fi

netlogon="<volume user=\"*\" fstype=\"cifs\" server=\"$ipscribe\" path=\"netlogon\" mountpoint=\"/tmp/netlogon\"  sgrp=\"DomainUsers\" />"
grep "/tmp/netlogon" /etc/security/pam_mount.conf.xml  >/dev/null
if [ $? != 0 ]
then
  sed -i "/<\!-- Volume definitions -->/a\ $netlogon" /etc/security/pam_mount.conf.xml
else
  echo "netlogon deja present"
fi

grep "<cifsmount>mount -t cifs //%(SERVER)/%(VOLUME) %(MNTPT) -o \"noexec,nosetuids,mapchars,cifsacl,serverino,nobrl,iocharset=utf8,user=%(USER),uid=%(USERUID)%(before=\\",\\" OPTIONS)\"</cifsmount>" /etc/security/pam_mount.conf.xml  >/dev/null
if [ $? != 0 ]
then
  sed -i "/<\!-- pam_mount parameters: Volume-related -->/a\ <cifsmount>mount -t cifs //%(SERVER)/%(VOLUME) %(MNTPT) -o \"noexec,nosetuids,mapchars,cifsacl,serverino,nobrl,iocharset=utf8,user=%(USER),uid=%(USERUID)%(before=\\",\\" OPTIONS)\"</cifsmount>" /etc/security/pam_mount.conf.xml
else
  echo "mount.cifs deja present"
fi

########################################################################
#/etc/profile
########################################################################
echo "
export LC_ALL=fr_FR.utf8
export LANG=fr_FR.utf8
export LANGUAGE=fr_FR.utf8
" >> /etc/profile

########################################################################
#ne pas creer les dossiers par defaut dans home
########################################################################
sed -i "s/enabled=True/enabled=False/g" /etc/xdg/user-dirs.conf

########################################################################
# les profs peuvent sudo
########################################################################
grep "%DomainAdmins ALL=(ALL) ALL" /etc/sudoers > /dev/null
if [ $?!=0 ]
then
  sed -i "/%admin ALL=(ALL) ALL/a\%DomainAdmins ALL=(ALL) ALL" /etc/sudoers
else
  echo "prof deja dans sudo"
fi

########################################################################
#parametrage du lightdm.conf
#activation du pave numerique par greeter-setup-script=/usr/bin/numlockx on
########################################################################
echo "[SeatDefaults]
    user-session=ubuntu
    greeter-session=unity-greeter
    allow-guest=false
    greeter-show-manual-login=true
    greeter-hide-users=true
    session-setup-script=/etc/lightdm/logonscript.sh
    session-cleanup-script=/etc/lightdm/logoffscript.sh
    greeter-setup-script=/usr/bin/numlockx on" > /etc/lightdm/lightdm.conf

#supression de l'applet fast-user-switch-applet
#gconftool --direct --config-source xml:readwrite:/etc/gconf/gconf.xml.mandatory --type bool --set '/desktop/gnome/lockdown/disable_user_switching' true
gconftool --direct --config-source xml:readwrite:/etc/gconf/gconf.xml.mandatory --type list --list-type=string --set '/apps/panel/default_setup/general/applet_id_list' '[clock,notification_area,show_desktop_button,window_list,workspace_switcher,trashapplet]'

########################################################################
#suppression de l'envoi des rapport d'erreurs
########################################################################
echo "enabled=0" >/etc/default/apport

########################################################################
#suppression de l'applet network-manager
########################################################################
sed -i "s/X-GNOME-Autostart-enabled=true/X-GNOME-Autostart-enabled=false/g" /etc/xdg/autostart/nm-applet.desktop

echo "reboot necessaire"

