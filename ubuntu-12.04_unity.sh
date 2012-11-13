#!/bin/bash
# Christophe Deze - Rectorat de Nantes
# script d'integration de station ubuntu 12.04 sur un scribe NG
# testé avec Scribe 2.2 et 2.3
# Quelques adaptations de Cédric Frayssinet (numlock actif, ajout du proxy Firefox, suppression panel, launcher par défaut...), adaptations valables pour Unity
# Version 1.1.1
# Run as root, of course.

########################################################################
#paramétrage par défaut
#changez les valeurs, ainsi, il suffira de taper 'entrée' à chaque question
########################################################################
ipscribepardefaut="172.16.0.241"
ipproxypardefaut=""
portproxypardefaut="3128"
pagedemarragepardefaut="http://www2.ac-lyon.fr/serv_ress/mission_tice/wiki/doku.php"
exclusionsproxypardefaut="127.0.0.1, localhost"

########################################################################
#vérification de la bonne version d'Ubuntu
########################################################################
if [ "$UID" -ne "0" ]
then
 echo "Il faut être root pour exécuter ce script : ==> sudo !"
 exit
fi
. /etc/lsb-release
if [ "$DISTRIB_RELEASE" != "12.04" ]
then
   echo " pas ubuntu 12.04"
   exit
fi

########################################################################
### Questionnaire : IP du scribe, proxy firefox, port proxy, exception proxy #####
########################################################################
ipscribe=""
#export http_proxy=""
echo "Donnez l'ip du Scribe (par défaut : $ipscribepardefaut) : "
read ipscribe

# IP SCRIBE #
if [ "$ipscribe" == "" ]
then
echo "ip scribe non renseignée !"
ipscribe=$ipscribepardefaut
fi
echo "IP du Scribe = "$ipscribe

# IP Proxy #
echo "Donnez l'ip du proxy (par défaut : $ipproxypardefaut) : "
read ipproxy

if [ "$ipproxy" == "" ]
then
echo "ip proxy non renseignée !"
ipproxy=$ipproxypardefaut
fi
echo "IP du Proxy = "$ipproxy

# Port du Proxy #
echo "Donnez le port du proxy (par défaut : $portproxypardefaut) : "
read portproxy

if [ "$portproxy" == "" ]
then
echo "Port proxy non renseigné !"
portproxy=$portproxypardefaut
fi
echo "Port du proxy = "$portproxy

# Page de démarrage de Firefox #
echo "Donnez la page de démarrage de Firefox avec http:// (par défaut : $pagedemarragepardefaut) : "
read pagedemarrage

if [ "$pagedemarrage" == "" ]
then
echo "Page de démarrage non renseignée !"
pagedemarrage=$pagedemarragepardefaut
fi
echo "Page de démarrage choisie = "$pagedemarrage

# Exclusions proxy #
echo "Donner les exclusions de proxy - séparés par des virgules (par défaut : $exclusionsproxypardefaut) : "
read exclusionsproxy

if [ "$exclusionsproxy" == "" ]
then
echo "Exclusions non renseignées !"
exclusionsproxy=$exclusionsproxypardefaut
fi
echo "Page de démarrage choisie = "$exclusionsproxy

########################################################################
#rendre debconf silencieux
########################################################################
export DEBIAN_FRONTEND="noninteractive"
export DEBIAN_PRIORITY="critical"

########################################################################
#Mettre la station à l'heure à partir du serveur Scribe
########################################################################
ntpdate $ipscribe

########################################################################
#installation des paquets necessaires
#numlockx pour le verrouillage du pave numerique
#unattended-upgrades pour forcer les mises à jour de sécurité à se faire
########################################################################
apt-get update
apt-get install -y ldap-auth-client libpam-mount smbfs nscd numlockx unattended-upgrades

########################################################################
# activation auto des mises à jour de sécu
########################################################################
echo "APT::Periodic::Update-Package-Lists \"1\";
APT::Periodic::Unattended-Upgrade \"1\";" > /etc/apt/apt.conf.d/20auto-upgrades

########################################################################
#parametrage du proxy systeme
########################################################################
echo "Acquire::http::proxy \"http://$ipproxy:$portproxy/\";
Acquire::ftp::proxy \"ftp://$ipproxy:$portproxy/\";
Acquire::https::proxy \"https://$ipproxy:$portproxy/\";" > /etc/apt/apt.conf

########################################################################
#ajout d'un parametrage afin de faire fonctionner add-apt-repository derriere un proxy
echo "Defaults env_keep = https_proxy" >> /etc/sudoers
########################################################################

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
grep "if mount | grep -q \"/tmp/netlogon\" ; then umount /tmp/netlogon ;fi"  /etc/lightdm/logonscript.sh  >/dev/null; if [ $? == 0 ];then echo "Presession Ok"; else echo  "if mount | grep -q \"/tmp/netlogon\" ; then umount /tmp/netlogon ;fi" >> /etc/lightdm/logonscript.sh;fi
chmod +x /etc/lightdm/logonscript.sh

touch /etc/lightdm/logoffscript.sh
echo "sleep 2
umount -f /tmp/netlogon 
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
grep "/media/Partages Scribe" /etc/security/pam_mount.conf.xml  >/dev/null; if [ $? != 0 ];then sed -i "/<\!-- Volume definitions -->/a\ $eclairng" /etc/security/pam_mount.conf.xml; else echo "eclairng deja present";fi
grep "mountpoint=\"~\"" /etc/security/pam_mount.conf.xml  >/dev/null; if [ $? != 0 ];then sed -i "/<\!-- Volume definitions -->/a\ $homes" /etc/security/pam_mount.conf.xml; else echo "homes deja present";fi
grep "/tmp/netlogon" /etc/security/pam_mount.conf.xml  >/dev/null; if [ $? != 0 ];then sed -i "/<\!-- Volume definitions -->/a\ $netlogon" /etc/security/pam_mount.conf.xml; else echo "netlogon deja present";fi

########################################################################
#nosuid,nodev,loop,encryption,fsck,nonempty,allow_root,allow_other
#options de montages
########################################################################
mntoptions="<cifsmount>mount -t cifs //%(SERVER)/%(VOLUME) %(MNTPT) -o \"noexec,nosetuids,mapchars,cifsacl,serverino,nobrl,iocharset=utf8,user=%(USER),uid=%(USERUID)%(before=\\",\\" OPTIONS)\"</cifsmount>"
grep "<cifsmount>mount -t cifs //%(SERVER)/%(VOLUME) %(MNTPT) -o \"noexec,nosetuids,mapchars,cifsacl,serverino,nobrl,iocharset=utf8,user=%(USER),uid=%(USERUID)%(before=\\",\\" OPTIONS)\"</cifsmount>" /etc/security/pam_mount.conf.xml  >/dev/null; if [ $? != 0 ];then sed -i "/<\!-- pam_mount parameters: Volume-related -->/a\ <cifsmount>mount -t cifs //%(SERVER)/%(VOLUME) %(MNTPT) -o \"noexec,nosetuids,mapchars,cifsacl,serverino,nobrl,iocharset=utf8,user=%(USER),uid=%(USERUID)%(before=\\",\\" OPTIONS)\"</cifsmount>" /etc/security/pam_mount.conf.xml; else echo "mount.cifs deja present";fi


grep "umount //$ipscribe/perso"  /etc/security/pam_mount.conf.xml  >/dev/null; if [ $? != 0 ];then sed -i "/<mkmountpoint enable=\"1\" remove=\"true\" \/>/a\ <umount> umount \/\/$ipscribe\/perso<\/umount><umount>umount \/\/$ipscribe\/netlogon<\/umount><umount>umount \/\/$ipscribe\/eclairng <\/umount>" /etc/security/pam_mount.conf.xml; else echo "unmount perso deja present";fi

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
grep "%DomainAdmins ALL=(ALL) ALL" /etc/sudoers > /dev/null; if [ $?!=0 ];then sed -i "/%admin ALL=(ALL) ALL/a\%DomainAdmins ALL=(ALL) ALL" /etc/sudoers; else echo "prof deja dans sudo";fi
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

########################################################################
#supression de l'applet switch-user pour ne pas voir les derniers connectés
#paramétrage d'un laucher unity par défaut : nautilus, firefox, libreoffice, calculatrice, editeur de texte et capture d'ecran
########################################################################
echo "[com.canonical.indicator.session]
user-show-menu=false
[org.gnome.desktop.lockdown]
disable-user-switching=true
disable-lock-screen=true
[com.canonical.Unity.Launcher]
favorites=[ 'nautilus-home.desktop', 'firefox.desktop','libreoffice-startcenter.desktop', 'gcalctool.desktop','gedit.desktop','gnome-screenshot.desktop' ]
" > /usr/share/glib-2.0/schemas/my-defaults.gschema.override
glib-compile-schemas /usr/share/glib-2.0/schemas

########################################################################
#paramétrage de Firefox
########################################################################
echo "pref(\"general.config.obscure_value\", 0);
pref(\"general.config.filename\", \"firefox.cfg\");" > /etc/firefox/syspref.js

echo "// Lock specific preferences in Firefox so that users cannot edit them
lockPref(\"network.proxy.type\", 1);
lockPref(\"network.proxy.http\", \"$ipproxy\");
lockPref(\"network.proxy.http_port\", $portproxy);
lockPref(\"network.proxy.share_proxy_settings\", true) ;
lockPref(\"network.proxy.no_proxies_on\", \"$exclusionsproxy\") ;
lockPref(\"browser.startup.page\", 1) ;
lockPref(\"browser.startup.homepage\", \"$pagedemarrage\");" > /usr/lib/firefox/firefox.cfg

########################################################################
#suppression de l'envoi des rapport d'erreurs
########################################################################
echo "enabled=0" >/etc/default/apport

########################################################################
#suppression de l'applet network-manager
########################################################################
sed -i "s/X-GNOME-Autostart-enabled=true/X-GNOME-Autostart-enabled=false/g" /etc/xdg/autostart/nm-applet.desktop

########################################################################
#suppression du menu messages
########################################################################
apt-get remove indicator-messages -y

########################################################################
#nettoyage station avant clonage
########################################################################

apt-get autoclean
apt-get autoremove

########################################################################
#FIN
########################################################################
echo "C'est fini ! Reboot nécessaire..."
