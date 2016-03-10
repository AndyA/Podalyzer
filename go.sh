#!/bin/sh

rm -f report/*
#./podfeeder -db=mc.db http://mojocrash.net/category/podcasts/feed
./podalyzer --db=mc.db --outdir=report --title='Mojo Crash' \
    --path=/assets \
    --feed='/index.php?feed=rss2&category_name=podcasts' \
    --feed='/category/podcasts/feed' logs

