#!/bin/bash
#copies a package from stage to internal epel-fuel-folsom
if [ -z "$1" ]; then
 echo "Usage: $0 pkgname"
fi
pkgname=$1
cd /usr/src/repo/epel-fuel-folsom-stage
files=$(find . -name $pkgname*)
for file in $files; do
  echo "Copying $file"
  cp "$file" "../epel-fuel-folsom/$file"
done

