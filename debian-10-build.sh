#!/bin/bash -e
# export GRADLE_OPTS=-Dorg.gradle.daemon=false
# alias javac='javac -Xlint:-deprecation -Xlint:-unchecked'
# export JDK_JAVAC_OPTIONS="-Xlint:-deprecation -Xlint:-unchecked"
[ -d $HOME/android ] && find $HOME/android -mindepth 1 -depth -exec rm -rf {} \;
git clone https://github.com/lavabit/pahoehoe.git android && cd android && FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch --subdirectory-filter android
# Update the Development Fingerprints
curl --silent --insecure https://api.centos.local/provider.json > $HOME/android/app/src/test/resources/preconfigured/centos.local.json
curl --silent --insecure https://api.centos.local/ca.crt > $HOME/android/app/src/test/resources/preconfigured/centos.local.pem
curl --silent --insecure https://api.debian.local/provider.json > $HOME/android/app/src/test/resources/preconfigured/debian.local.json
curl --silent --insecure https://api.debian.local/ca.crt > $HOME/android/app/src/test/resources/preconfigured/debian.local.pem
./scripts/build_deps.sh
#./gradlew --warning-mode none build
./gradlew --warning-mode none assemble
./gradlew --warning-mode none check
# ./gradlew --warning-mode none bundle
# ./gradlew --warning-mode none assembleDebug
# ./gradlew --warning-mode none assembleRelease
# ./gradlew --warning-mode none connectedCheck
