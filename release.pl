#!/usr/bin/perl -w

use strict;

use Getopt::Long;
use Pod::Usage;
use Memoize;
use File::Basename;
use File::Spec::Functions;
use Mail::Sendmail;

my $VERSION = '0.1';

my @TAR     = qw(/usr/bin/tar zcf);
my @RSYNC   = qw(/usr/bin/rsync -av -e ssh);
my @CP      = qw(/bin/cp);
my @RM      = qw(/bin/rm -rf);
my @MKDIR   = qw(/bin/mkdir -p);

my $SMTP    = 'post.hexten.net';
my $FROM    = 'andy@hexten.net';

my $KB      = 1024;             # Size of one KB
my $MB      = $KB * $KB;        #   "      "  MB
my $GB      = $MB * $KB;        #   "      "  GB
my $TB      = $GB * $KB;        #   "      "  TB

my %versions = ( );

memoize('should_have_version');

my $man         = 0;                # Show man page?
my $help        = 0;                # Show help?
my $force       = 0;                # Force updates?
my $target      = undef;            # Target file
my $destdir     = undef;
my $desturl     = undef;
my $template    = undef;
my $mailto      = undef;

GetOptions('help|?'         => \$help,
           'man'            => \$man,
           'target=s'       => \$target,
           'destdir=s'      => \$destdir,
           'desturl=s'      => \$desturl,
           'template=s'     => \$template,
           'mailto=s'       => \$mailto) or pod2usage(2);

pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;
pod2usage(2) unless @ARGV && defined $target;   # Need some files

my @files = ( );

while (my $f = shift) {
    my ($type, $optional) = could_have_version($f);
    if (defined($type)) {
        my $ver = get_file_version($f, $type);
        if (defined($ver)) {
            push @{$versions{$ver}}, $f;
        } else {
            push @{$versions{'<none>'}}, $f
                unless $optional;
        }
    }
    # At the moment we're just copying the arguments - but we
    # have the opportunity to edit the files list if necessary
    push @files, $f;
}

my @versions = keys(%versions);
if (@versions > 1) {
    print "The following versions were found:\n";
    for (sort keys %versions) {
        print '  ' . $_, ' => ', join(', ', @{$versions{$_}}), "\n";
    }
    print "Please ensure all release files have the same version number.\n";
    exit(1);
}

my $ver = $versions[0];
my $out = "$target-$ver";
my $tar = "$out.tar.gz";

cmd(@MKDIR, $out);
local_copy(@files, $out);

# Tar up the file for release
cmd(@TAR, $tar, $out);
cmd(@RM, $out);

print "Created $tar\n";
my $size = -s $tar;

if (defined($destdir)) {
    copy($tar, $destdir);
    print "Copied $tar to $destdir\n";
}

if (defined($desturl)) {
    my $destfile = "$desturl/$tar";
    print "File uploaded to $destfile\n";
    if (defined($template)) {
        my $message = load_file($template);
        my $subst = sub {
            return load_file($_[0]);
        };
        my %ctx = (
            VERSION     => $ver,
            SIZE        => fmt_size($size),
            LINK        => $destfile,
            LOCAL       => strip_url($destfile),
            ARCHIVE     => $tar,
            DATE        => scalar gmtime
        );
        # File substitution
        $message =~ s/ %: ([^%]+) % / $subst->($1) /iexg;
        # Token substitution
        $message =~ s/ % (\w+) % / $ctx{$1} /iexg;
        print "\n$message\n";
        mail($mailto, "$target $ver released", $message)
            if defined $mailto;
    }
}

sub load_file {
    my $n = shift;
    my $f;
    local *T;
    open T, "<$n" or die "Can't read $n ($!)\n";
    { local $/; $f = <T>; }
    close T;
    return $f;
}

sub mail {
    my ($to, $subject, $body) = @_;

    my %msg = (
        Smtp    => $SMTP,
        From    => $FROM,
        To      => $to,
        Subject => $subject,
        Message => $body
    );

    sendmail(%msg) or die $Mail::Sendmail::error;
}

sub cmd {
    my $c = join(' ', @_);
    print "$c\n";
    system(@_) and die "$c failed ($!)\n";
}

sub local_copy {
    my $dst = pop @_;
    for my $file (@_) {
        my $dstdir = catfile($dst, dirname($file));
        cmd(@MKDIR, $dstdir);
        cmd(@CP, $file, $dstdir);
    }
}

sub copy {
    my ($src, $dst) = @_;
    if ($dst =~ /^rsync:(.*)$/) {
        cmd(@RSYNC, $src, $1) and die "rsync failed ($!)\n";
    } else {
        cmd(@CP, $src, $dst) and die "cp failed ($!)\n";
    }
}

sub should_have_version {
    my ($f) = @_;
    
    return 'perl' if $f =~ m!\.p(l|m)$!;
    return 'text' if $f =~ m!\.txt$!;
    return 'text' if $f =~ m!(README|COPYING|THANKS|AUTHORS|NEWS)!;
    
    open F, "<$f" or die "Can't read $f ($!)\n";
    my $fl = <F>;
    chomp $fl;
    close F;
    
    return 'perl' if $fl =~ m!/perl!;
    
    return undef;
}

sub could_have_version {
    my $type = should_have_version($_[0]);
    
    return (undef, undef)
        unless defined $type;

    my @opt = qw(html css text);

    my $could = scalar(grep($_ eq $type, @opt));
    return ($type, $could);
}

sub get_file_version {
    my ($f, $type) = @_;
    
    my %patterns = (
        'perl'  => '^my\s+\$VERSION\s+=\s+[\'"](.+?)["\'];',
        'text'  => 'version\s+([\d\.]+)'
    );
        
    my $pat = $patterns{$type} ||
        die "Don't know how to find the version of a $type file\n";
    
    my $ver = undef;
    local *F;
    open F, "<$f" or die "Can't read $f ($!)\n";
    LINE: while (<F>) {
        chomp;
        if (/$pat/o) {
            $ver = $1;
            last LINE;
        }
    }
    close F;
    return $ver;
}

sub fmt_size {
    my $sz = shift;
    if ($sz > $TB * 5) {
        return sprintf("%.2fTb", $sz / $TB)
    } elsif ($sz > $GB * 5) {
        return sprintf("%.2fGb", $sz / $GB)
    } elsif ($sz > $MB * 5) {
        return sprintf("%.2fMb", $sz / $MB)
    } elsif ($sz > $KB * 5) {
        return sprintf("%.2fKb", $sz / $KB)
    } else {
        return sprintf("%db", $sz);
    }
}

sub strip_url {
    my $url = shift;
    $url =~ s!^http://[^/]+!!;
    return $url;
}

__END__

=head1 NAME

podfeeder - Extract show names from an RSS feed

=head1 SYNOPSIS

podfeeder [options] -db=[file] [feed ...]

 Options:

    -db=[file]              name of a file to contain file path to 
                            podcast name mappings; mandatory
    -force                  update all shows found in feed
    -help                   see this text
    -man                    see this text as a man page

=head1 OPTIONS

=over 8

=item B<-db>

This option is mandatory. It names the text file that contains the mapping between podcast URIs
and show names. Once updated using B<podfeeder> pass the name of this file to B<podalyzer> to
have shows properly named in the podalyzer report.

=item B<-force>

Force B<podfeeder> to update all entries in the mapping file for which it finds entries in the
feed. Without this flag only missing mappings will be added to the mapping file.

=back

=head1 DESCRIPTION

B<podfeeder> fetches and analyses one or more RSS feeds to extract show names for URIs and updates
a mapping file which can then be passed to B<podalyser> to generate reports in which shows are
correctly named.

=head1 EXAMPLES

    podfeeder -db=mapping.db http://example.com/category/podcasts/feed
    podalyzer -db=mapping.db --outdir=report --title='Example Podcast' logs 

=head1 SEE ALSO

    podalyser

=head1 AUTHORS

    Written by Andy Armstrong (andy@hexten.net) with much inspiration from Kevin Devin
    (Friends in Tech). Kevin's podstats script may be found here:

    http://forums.friendsintech.com/viewtopic.php?t=\
       40&sid=055c024f369658b97e01dd7ef282d71d

    (url wrapped for formatting - here is a shorter version: http://lyxus.net/cfv)

=head1 BUGS

    If you find any please report them to andy@hexten.net.

=cut
