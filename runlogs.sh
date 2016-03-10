#!/bin/sh

podalyzer=/root/bin/podalyzer
podfeeder=/root/bin/podfeeder

feed=http://example.com/category/podcasts/feed
title='My Podcast'

webroot=/usr/local/apache-php
logdir=$webroot/logs
filtlogdir=podcasts

outdir=$webroot/htdocs/stats

cd $logdir
mkdir -p $filtlogdir

# Update filtered logs
for log in access_log*
do
    flog=`echo $filtlogdir/$log | sed -e 's/\.gz$//'`
    if [ ! -f $flog -o $log -nt $flog ]
    then
	    $podalyzer --filter $log > $flog
    fi
done

# Read feed
$podfeeder --db=shows.db --force $feed
$podalyzer --db=shows.db --outdir=$outdir --title="$title" $filtlogdir
