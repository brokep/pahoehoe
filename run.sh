#!/bin/bash

# If the version string/numbers aren't setup already, we declare them here. The version 
# string is what defines this build. The version number will be used as the version code
# for F-Droid builds. The APK files uploaded to Google Play will use the build.gradle
# logic to generate unique version numbers (aka codes) for each ABI variant.

# The values used here should match the android/app/build.gradle file. Specifically, the 
# android -> lavabit -> versionName and android -> lavabit -> versionCode values. 
[ ! -n "$VERNUM" ] && export VERNUM="203"
[ ! -n "$VERSTR" ] && export VERSTR="1.0.3-RC"

# Handle self referencing, sourcing etc.
if [[ $0 != $BASH_SOURCE ]]; then
  export CMD=$BASH_SOURCE
else
  export CMD=$0
fi

# Ensure a consistent working directory so relative paths work.
pushd `dirname $CMD` > /dev/null
BASE=`pwd -P`
popd > /dev/null
cd $BASE

# Ignore errors during the init phase.
set -

# Set libvirt as the default provider, but allow an environment variable to override it.
[ ! -n "$PROVIDER" ] && export PROVIDER="libvirt"

# Cleanup.
[ -d $BASE/build/source/ ] && sudo umount --force $BASE/build/source/ &>/dev/null
[ -d $BASE/build/source/ ] && rmdir $BASE/build/source/ &>/dev/null
[ -d $BASE/build/ ] && rm --force --recursive $BASE/build/
vagrant destroy -f &>/dev/null

# Create a build directory, and a log subdirectory.
[ ! -d $BASE/build/ ] && mkdir $BASE/build/
[ ! -d $BASE/build/logs/ ] && mkdir $BASE/build/logs/

# Try and update the box. If we already have the current version, proceed. Otherwise
# download the latest box file. If the box is missing, or the download fails, we 
# use the add command to download it, and we try that three times, which will hopefully
# reduce the number of CI failures caused by temporal cloud issues.
vagrant box update --provider $PROVIDER --box "generic/centos8" &> "$BASE/build/logs/vagrant_box_add.txt" || \
  { vagrant box add --clean --force --provider $PROVIDER "generic/centos8" &> "$BASE/build/logs/vagrant_box_add.txt" ; } || \
  { sleep 120 ; vagrant box add --clean --force --provider $PROVIDER "generic/centos8" &>> "$BASE/build/logs/vagrant_box_add.txt" ; } || \
  { sleep 180 ; vagrant box add --clean --force --provider $PROVIDER "generic/centos8" &>> "$BASE/build/logs/vagrant_box_add.txt" ; } || \
  { tput setaf 1 ; printf "\nBox download failed. [ BOX = generic/centos8 ]\n\n" ; tput sgr0 ; \
  vagrant box remove --force --all --provider $PROVIDER "generic/centos8" &> /dev/null ; exit 1 ; }

vagrant box update --provider $PROVIDER --box "generic/debian10" &> "$BASE/build/logs/vagrant_box_add.txt" || \
  { vagrant box add --clean --force --provider $PROVIDER "generic/debian10" &>> "$BASE/build/logs/vagrant_box_add.txt" ; } || \
  { sleep 120 ; vagrant box add --clean --force --provider $PROVIDER "generic/debian10" &>> "$BASE/build/logs/vagrant_box_add.txt" ; } || \
  { sleep 180 ; vagrant box add --clean --force --provider $PROVIDER "generic/debian10" &>> "$BASE/build/logs/vagrant_box_add.txt" ; } || \
  { tput setaf 1 ; printf "\nBox download failed. [ BOX = generic/debian10 ]\n\n" ; tput sgr0 ; \
  vagrant box remove --force --all --provider $PROVIDER "generic/debian10" &> /dev/null ; exit 1 ; }

printf "\nBox download complete.\n"

# Create the virtual machines.
vagrant up --provider=$PROVIDER &> "$BASE/build/logs/vagrant_up.txt" && BOOTED=1 || \
 { RESULT=$? ; tput setaf 1 ; printf "Box startup error. Retrying. [ UP = $RESULT ]\n\n" ; tput sgr0 ; \
 vagrant destroy -f ; sleep 120 ; vagrant up --provider=$PROVIDER &>> "$BASE/build/logs/vagrant_up.txt" && BOOTED=1 } || \
 { RESULT=$? ; tput setaf 1 ; printf "Box startup error. Retrying. [ UP = $RESULT ]\n\n" ; tput sgr0 ; \
 vagrant destroy -f ; sleep 120 ; vagrant up --provider=$PROVIDER &>> "$BASE/build/logs/vagrant_up.txt" && BOOTED=1 } || \
 { RESULT=$? ; tput setaf 1 ; printf "Box startup error. Exiting. [ UP = $RESULT ]\n\n" ; tput sgr0 ; exit 1 ; }
 
printf "Box startup complete.\n"

 # Any errors past this point would be critical failures.
 set -e
 
# Upload the scripts.
vagrant upload centos-8-vpnweb.sh vpnweb.sh centos_vpn &> /dev/null
vagrant upload centos-8-openvpn.sh openvpn.sh centos_vpn &> /dev/null
vagrant upload debian-10-vpnweb.sh vpnweb.sh debian_vpn &> /dev/null
vagrant upload debian-10-openvpn.sh openvpn.sh debian_vpn &> /dev/null

vagrant upload debian-10-build-setup.sh setup.sh debian_build &> /dev/null
vagrant upload debian-10-rebuild.sh rebuild.sh debian_build &> /dev/null
vagrant upload debian-10-build.sh build.sh debian_build &> /dev/null

[ -f debian-10-build-key.sh ] && vagrant upload debian-10-build-key.sh key.sh debian_build &> /dev/null

vagrant ssh -c 'chmod +x vpnweb.sh openvpn.sh' centos_vpn &> /dev/null
vagrant ssh -c 'chmod +x vpnweb.sh openvpn.sh' debian_vpn &> /dev/null
vagrant ssh -c 'chmod +x setup.sh build.sh rebuild.sh' debian_build &> /dev/null

[ -f debian-10-build-key.sh ] && vagrant ssh -c 'chmod +x key.sh' debian_build &> /dev/null

# Provision the VPN service.
vagrant ssh --no-tty -c "sudo --login TZ=$TZ TERM=$TERM bash -e < vpnweb.sh" centos_vpn &> "$BASE/build/logs/centos_vpn.txt" || \
 { RESULT=$? ; tput setaf 1 ; printf "CentOS VPN error. [ VPNWEB = $RESULT ]\n\n" ; tput sgr0 ; exit 1 ; }
vagrant ssh --no-tty -c "sudo --login TZ=$TZ TERM=$TERM bash -e < openvpn.sh" centos_vpn &>> "$BASE/build/logs/centos_vpn.txt" || \
 { RESULT=$? ; tput setaf 1 ; printf "CentOS VPN error. [ OPENVPN = $RESULT ]\n\n" ; tput sgr0 ; exit 1 ; }

printf "CentOS VPN stage complete.\n"

vagrant ssh --no-tty -c "sudo --login TZ=$TZ TERM=$TERM bash -e < vpnweb.sh" debian_vpn &> "$BASE/build/logs/debian_vpn.txt" || \
 { RESULT=$? ; tput setaf 1 ; printf "Debian VPN error. [ VPNWEB = $RESULT ]\n\n" ; tput sgr0 ; exit 1 ; }
vagrant ssh --no-tty -c "sudo --login TZ=$TZ TERM=$TERM bash -e < openvpn.sh" debian_vpn &>> "$BASE/build/logs/debian_vpn.txt" || \
 { RESULT=$? ; tput setaf 1 ; printf "Debian VPN error. [ OPENVPN = $RESULT ]\n\n" ; tput sgr0 ; exit 1 ; }
 
printf "Debian VPN stage complete.\n"

# Compile the Android client.
vagrant ssh --no-tty -c "TZ=$TZ TERM=$TERM bash -ex setup.sh" debian_build &> "$BASE/build/logs/debian_build.txt" || \
 { RESULT=$? ; tput setaf 1 ; printf "Android build error. [ SETUP = $RESULT ]\n\n" ; tput sgr0 ; exit 1 ; }
 
printf "Android build setup complete.\n"
 
vagrant ssh --no-tty -c "TZ=$TZ TERM=$TERM VERNUM=$VERNUM VERSTR=$VERSTR bash -ex build.sh" debian_build &>> "$BASE/build/logs/debian_build.txt" || \
 { RESULT=$? ; tput setaf 1 ; printf "Android build error. [ BUILD = $RESULT ]\n\n" ; tput sgr0 ; exit 1 ; }

printf "Android build stage complete.\n"

# Save an SSH config file so we can extract the build artifacts.
vagrant ssh-config debian_build > $BASE/build/config

# If there is an output folder, extract the development APKs from the build environment.
vagrant ssh -c "test -d \$HOME/android/app/build/outputs/" debian_build &> /dev/null && {
  printf "get /home/vagrant/android/app/build/outputs/apk/lavabitInsecureFat/debug/Lavabit_Proxy_debug_$VERSTR.apk $BASE/build/outputs/Lavabit_Proxy_fat_insecure_debug_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/app/build/outputs/apk/lavabitProductionFat/debug/Lavabit_Proxy_debug_$VERSTR.apk $BASE/build/outputs/Lavabit_Proxy_fat_debug_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/app/build/outputs/apk/lavabitProductionFatweb/debug/Lavabit_Proxy_debug_$VERSTR.apk $BASE/build/outputs/Lavabit_Proxy_fatweb_debug_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/app/build/outputs/apk/lavabitProductionX86/beta/Lavabit_Proxy_x86_beta_$VERSTR.apk $BASE/build/outputs/Lavabit_Proxy_x86_beta_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/app/build/outputs/apk/lavabitProductionX86_64/beta/Lavabit_Proxy_x86_64_beta_$VERSTR.apk $BASE/build/outputs/Lavabit_Proxy_x86_64_beta_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/app/build/outputs/apk/lavabitProductionArmv7/beta/Lavabit_Proxy_armeabi-v7a_beta_$VERSTR.apk $BASE/build/outputs/Lavabit_Proxy_armeabi-v7a_beta_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/app/build/outputs/apk/lavabitProductionArm64/beta/Lavabit_Proxy_arm64-v8a_beta_$VERSTR.apk $BASE/build/outputs/Lavabit_Proxy_arm64-v8a_beta_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/app/build/outputs/apk/lavabitProductionFat/beta/Lavabit_Proxy_beta_$VERSTR.apk $BASE/build/outputs/Lavabit_Proxy_fat_beta_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/app/build/outputs/apk/lavabitProductionX86/release/Lavabit_Proxy_x86_release_$VERSTR.apk $BASE/build/outputs/Lavabit_Proxy_x86_release_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/app/build/outputs/apk/lavabitProductionX86_64/release/Lavabit_Proxy_x86_64_release_$VERSTR.apk $BASE/build/outputs/Lavabit_Proxy_x86_64_release_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/app/build/outputs/apk/lavabitProductionArmv7/release/Lavabit_Proxy_armeabi-v7a_release_$VERSTR.apk $BASE/build/outputs/Lavabit_Proxy_armeabi-v7a_release_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/app/build/outputs/apk/lavabitProductionArm64/release/Lavabit_Proxy_arm64-v8a_release_$VERSTR.apk $BASE/build/outputs/Lavabit_Proxy_arm64-v8a_release_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/app/build/outputs/apk/lavabitProductionFat/release/Lavabit_Proxy_release_$VERSTR.apk $BASE/build/outputs/Lavabit_Proxy_fat_release_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/app/build/outputs/apk/lavabitProductionFatweb/release/Lavabit_Proxy_web_release_$VERSTR.apk $BASE/build/outputs/Lavabit_Proxy_fatweb_release_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null || \
  { RESULT=$? ; tput setaf 1 ; printf "Outputs download error. [ OUTPUTS = $RESULT ]\n\n" ; tput sgr0 ; exit 1 ; }
}

# If there is a releases folder, extract the signed release APKs files from the build environment.
vagrant ssh -c "test -d \$HOME/android/releases/" debian_build &> /dev/null && {
  printf "get /home/vagrant/android/releases/SHA256SUMS $BASE/build/releases/SHA256SUMS\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_release_$VERSTR.apk $BASE/build/releases/Lavabit_Proxy_release_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_release_$VERSTR.apk.sig $BASE/build/releases/Lavabit_Proxy_release_$VERSTR.apk.sig\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_release_$VERSTR.apk.idsig $BASE/build/releases/Lavabit_Proxy_release_$VERSTR.apk.idsig\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_release_$VERSTR.apk.version $BASE/build/releases/Lavabit_Proxy_release_$VERSTR.apk.version\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_web_release_$VERSTR.apk $BASE/build/releases/Lavabit_Proxy_web_release_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_web_release_$VERSTR.apk.sig $BASE/build/releases/Lavabit_Proxy_web_release_$VERSTR.apk.sig\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_web_release_$VERSTR.apk.idsig $BASE/build/releases/Lavabit_Proxy_web_release_$VERSTR.apk.idsig\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_web_release_$VERSTR.apk.version $BASE/build/releases/Lavabit_Proxy_web_release_$VERSTR.apk.version\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_x86_release_$VERSTR.apk $BASE/build/releases/Lavabit_Proxy_x86_release_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_x86_release_$VERSTR.apk.sig $BASE/build/releases/Lavabit_Proxy_x86_release_$VERSTR.apk.sig\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_x86_release_$VERSTR.apk.idsig $BASE/build/releases/Lavabit_Proxy_x86_release_$VERSTR.apk.idsig\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_x86_release_$VERSTR.apk.version $BASE/build/releases/Lavabit_Proxy_x86_release_$VERSTR.apk.version\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_x86_64_release_$VERSTR.apk $BASE/build/releases/Lavabit_Proxy_x86_64_release_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_x86_64_release_$VERSTR.apk.sig $BASE/build/releases/Lavabit_Proxy_x86_64_release_$VERSTR.apk.sig\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_x86_64_release_$VERSTR.apk.idsig $BASE/build/releases/Lavabit_Proxy_x86_64_release_$VERSTR.apk.idsig\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_x86_64_release_$VERSTR.apk.version $BASE/build/releases/Lavabit_Proxy_x86_64_release_$VERSTR.apk.version\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_armeabi-v7a_release_$VERSTR.apk $BASE/build/releases/Lavabit_Proxy_armeabi-v7a_release_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_armeabi-v7a_release_$VERSTR.apk.sig $BASE/build/releases/Lavabit_Proxy_armeabi-v7a_release_$VERSTR.apk.sig\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_armeabi-v7a_release_$VERSTR.apk.idsig $BASE/build/releases/Lavabit_Proxy_armeabi-v7a_release_$VERSTR.apk.idsig\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_armeabi-v7a_release_$VERSTR.apk.version $BASE/build/releases/Lavabit_Proxy_armeabi-v7a_release_$VERSTR.apk.version\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_arm64-v8a_release_$VERSTR.apk $BASE/build/releases/Lavabit_Proxy_arm64-v8a_release_$VERSTR.apk\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_arm64-v8a_release_$VERSTR.apk.sig $BASE/build/releases/Lavabit_Proxy_arm64-v8a_release_$VERSTR.apk.sig\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_arm64-v8a_release_$VERSTR.apk.idsig $BASE/build/releases/Lavabit_Proxy_arm64-v8a_release_$VERSTR.apk.idsig\n" | sftp -F $BASE/build/config debian_build 1>/dev/null && \
  printf "get /home/vagrant/android/releases/Lavabit_Proxy_arm64-v8a_release_$VERSTR.apk.version $BASE/build/releases/Lavabit_Proxy_arm64-v8a_release_$VERSTR.apk.version\n" | sftp -F $BASE/build/config debian_build 1>/dev/null || \
  { RESULT=$? ; tput setaf 1 ; printf "Release download error. [ RELEASES = $RESULT ]\n\n" ; tput sgr0 ; exit 1 ; }
} || { 
  printf "Release builds missing. Skipping download.\n" ;
}

# Termux version 118 requires at least v24 of the Android SDK.
[ -d $BASE/build/termux/ ] && rm --force --recursive $BASE/build/termux/ ; mkdir --parents $BASE/build/termux/
curl --silent --location --output $BASE/build/termux/com.termux_118.apk https://f-droid.org/repo/com.termux_118.apk
printf "822ac152bd7c2d9770b87c1feea03f22f2349a91b94481b268c739493a260f0b  $BASE/build/termux/com.termux_118.apk" | sha256sum -c --quiet || exit 1

curl --silent --location --output $BASE/build/termux/com.termux.api_51.apk https://f-droid.org/repo/com.termux.api_51.apk
printf "781ff805619b104115fbf15499414715b4ea6ceb93c4935086a7e35966024f20  $BASE/build/termux/com.termux.api_51.apk" | sha256sum -c --quiet || exit 1

curl --silent --location --output $BASE/build/termux/com.termux.boot_7.apk https://f-droid.org/repo/com.termux.boot_7.apk
printf "35cae49192d073151e3177956ea4f1d6309c2330fed42ec046cbb44cee072a32  $BASE/build/termux/com.termux.boot_7.apk" | sha256sum -c --quiet || exit 1

curl --silent --location --output $BASE/build/termux/com.termux.widget_13.apk https://f-droid.org/repo/com.termux.widget_13.apk
printf "7ec99c3bd53e1fb8737f688bc26fdd0ae931f1f2f7eb9c855de1a0e4eb6147ae  $BASE/build/termux/com.termux.widget_13.apk" | sha256sum -c --quiet || exit 1

curl --silent --location --output $BASE/build/termux/com.termux.styling_29.apk https://f-droid.org/repo/com.termux.styling_29.apk
printf "77bafdb6c4374de0cdabe68f103aca37ef7b81e18272ea663bb9842c82920bec  $BASE/build/termux/com.termux.styling_29.apk" | sha256sum -c --quiet || exit 1

# Termux version 75 requires at least v21 of the Android SDK.
curl --silent --location --output $BASE/build/termux/com.termux_75.apk https://f-droid.org/archive/com.termux_75.apk
printf "d88444d9df4049c47f12678feb9579aaf2814a89e411d52653dc0a2509f883b5  $BASE/build/termux/com.termux_75.apk" | sha256sum -c --quiet || exit 1

# Download ConnectBot, which will work on devices with Android SDK v14 and higher..
[ -d $BASE/build/connectbot/ ] && rm --force --recursive $BASE/build/connectbot/ ; mkdir --parents $BASE/build/connectbot/
curl --silent --location --output $BASE/build/connectbot/org.connectbot_10908000.apk https://f-droid.org/repo/org.connectbot_10908000.apk
printf "fa9bda5d707ace0b3fdbf4a66d2a3e2b4ada147f261ed2fcce000e7180426044  $BASE/build/connectbot/org.connectbot_10908000.apk" | sha256sum -c --quiet || exit 1

# Download the OpenVPN Android GUI
[ -d $BASE/build/openvpn/ ] && rm --force --recursive $BASE/build/openvpn/ ; mkdir --parents $BASE/build/openvpn/
curl --silent --location --output $BASE/build/openvpn/de.blinkt.openvpn_189.apk https://f-droid.org/repo/de.blinkt.openvpn_189.apk
printf "a67fbbb73f1a0bcacc5dd51f8aaf8ee52454094a86b019a93bf0f44c44202d5a  $BASE/build/openvpn/de.blinkt.openvpn_189.apk" | sha256sum -c --quiet || exit 1

# Download the currently released Lavabit App
[ -d $BASE/build/lavabit/ ] && rm --force --recursive $BASE/build/lavabit/ ; mkdir --parents $BASE/build/lavabit/
curl --silent --location --output $BASE/build/lavabit/com.lavabit.pahoehoe_201.apk https://f-droid.org/repo/com.lavabit.pahoehoe_201.apk
printf "c091f6b50318c4cfb8d2edc175264cd82e03b9e2469889f8bbb9467bc2d405a2  $BASE/build/lavabit/com.lavabit.pahoehoe_201.apk" | sha256sum -c --quiet || exit 1

# Download CPU Info App
[ -d $BASE/build/cpuinfo/ ] && rm --force --recursive $BASE/build/cpuinfo/ ; mkdir --parents $BASE/build/cpuinfo/
curl --silent --location --output $BASE/build/cpuinfo/com.kgurgul.cpuinfo_40500.apk https://f-droid.org/repo/com.kgurgul.cpuinfo_40500.apk
printf "3f70b2cccf987f91e1e6887f66781040e00e76ea6a11cd9024b9b4573cd26855  $BASE/build/cpuinfo/com.kgurgul.cpuinfo_40500.apk" | sha256sum -c --quiet || exit 1

# [ ! -d $BASE/build/source/ ] && mkdir $BASE/build/source/
# sshfs vagrant@192.168.221.50:/home/vagrant/android $BASE/build/source -o uidfile=1000 -o gidfile=1000 \
# -o StrictHostKeyChecking=no -o IdentityFile=$BASE/.vagrant/machines/debian_build/libvirt/private_key

tput setaf 2; printf "Lavabit encrypted proxy build complete.\n"; tput sgr0
