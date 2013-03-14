#!/bin/bash
# Signs all packages and runs mash for every tag

tags=$(koji list-tags | grep -v -- "-build")
for tag in tags; do
  sign.exp $tag
  sudo /usr/bin/mash --outputdir=/mnt/mash $tag
done
