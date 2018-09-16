#!/usr/bin/perl

=head1 NAME

ftp_sync.pl - Sync a directory with an ftp server

=cut

use strict;
use warnings;
use Net::FTP;
use IO::Prompt qw(prompt);
use File::Find qw(find);

#use CGI::Ex::Dump qw(debug);
sub debug { require Data::Dumper; print Data::Dumper::Dumper(@_) }

### times to run the daemon
our $SRC_DIR    = '/usr/local/share/pinger/data'; # source directory - full path - no trailing slash
our $DEST_DIR   = '/incoming/2001:da8:270:2018:f816:3eff:fef3:bd3';                     # destination directory - full path - no trailing slash
our $DEST_HOST  = 'ftp.slac.stanford.edu';          # remote hostname
our $DEST_USER  = 'anonymous';          # remote username

our $EXCLUDE    = [                       # list of files to exclude (that work with rsync patterns)
                   ];

###----------------------------------------------------------------###

main();

sub main {
    ### setup config
    my $config = {
        src_dir   => $SRC_DIR,
        dest_dir  => $DEST_DIR,
        host      => $DEST_HOST,
        user      => $DEST_USER,
        exclude   => $EXCLUDE,
        @ARGV,
    };
    ### these must end with slash
    $config->{'dest_dir'} =~ s|/+$||;
    $config->{'src_dir'}  =~ s|/+$||;

    $| = 1;
    my $time = time;

   # my $pass = $config->{'pass'} || prompt("Please enter the password for $config->{'user'}\@$config->{'host'}: ", -e => '*');
    my $pass = 'saqibutm@outloo.com';
    print "Connect in...\n";
    my $f = Net::FTP->new($config->{'host'}, Passive => 1, Debug => 0) || die "Couldn't ftp to $config->{'host'}: $@";

    print "Logging in...\n";
    $f->login($config->{'user'}, $pass) || die "Couldn't login to $config->{'host'}: ".$f->message;
    $f->binary;

    my $files = {};

    ### grab local file list
    find(sub {
        my $file = $File::Find::name;
        $file =~ s|^\Q$config->{'src_dir'}\E/*||;
        return if ! length($file);
        return if $file =~ /\bCVS\b/;
        my ($size, $mtime) = (stat $_)[7, 9];
        $files->{$file} = {
            local_is_dir => (-d _ ? 1 : 0),
            local_size   => $size,
            local_mtime  => $mtime,
        };
    }, $config->{'src_dir'});
    #debug $files;
    #return;

    ### get remote files
    print "Getting files from \"$config->{'dest_dir'}\"\n";
    my $get_files;
    $get_files = sub {
        my ($dir) = @_;
        my $old_dir = $f->pwd;
        $f->cwd($dir);
        my @files = $f->dir;
        foreach my $line (@files) {
            #drwx------   3 ftpuser  www          4096 Jun  9  2006 perl5lib",
            #-rw-------   1 ftpuser  www          4697 Dec 18 09:17 photo2.html",
            next if $line =~ /^total\s+\d+$/;
            my ($perm, $i, $user, $grp, $size, $jon, $day, $yearhour, $file) = split(/\s+/, $line, 9);
            next if $file =~ /^\.\.?$/;
            debug $line if ! $file;
            my $is_dir = $perm =~ /^d/ ? 1 : 0;
            my $full = "$dir/$file";
            $full =~ s|^\Q$config->{'dest_dir'}\E||;
            $full =~ s|^/+||g;
            print "$full                                            \r";
            my $ref = $files->{$full} ||= {};
            $ref->{'remote_size'}   = $size;
            $ref->{'remote_is_dir'} = $is_dir;
            if ($ref->{'local_size'} # only bother to get the mdtm if the sizes are the same
                && ! $ref->{'remote_is_dir'}
                && $ref->{'local_size'} == $ref->{'remote_size'}) {
                $ref->{'remote_mtime'} = $f->mdtm($file);
            }
            if ($is_dir) {
                $get_files->("$dir/$file");
            }
        }
        $f->cwd($old_dir);
    };
    $get_files->($config->{'dest_dir'});
    print "\n";
    #debug $files;
    #return;

    ###----------------------------------------------------------------###

    print "Syncing files...\n";

    ### remove files that don't belong
    foreach my $full (reverse sort keys %$files) { # longest first will remove files in a dir before the dir
        my $info = $files->{$full};
        my $needs_update;
        my ($path, $file) = $full =~ m|^(.*?)([^/]+)$| ? ($1, $2) : do { debug $full; die "Bad file \"$full\"" };
        $path =~ s|/+$||;
        my $cd = $config->{'dest_dir'} .'/'. $path;
        if ($info->{'remote_is_dir'} && ! $info->{'local_is_dir'}) {
            print "Removing dir $full\n";
            $f->cwd($cd)     || die "Couldn't cwd to $cd: ".$f->message;
            $f->rmdir($file) || die "Couldn't remove $full: ".$f->message;
        } elsif (! $info->{'remote_is_dir'}
                 && defined $info->{'remote_size'}
                 && ! defined $info->{'local_size'}) {
            print "Removing file $full\n";
            $f->cwd($cd)      || die "Couldn't cwd to $cd: ".$f->message;
            $f->delete($file) || die "Couldn't delete $full: ".$f->message;
        }
    }

    ### add or update files that are out of date
    foreach my $full (sort keys %$files) { # shortest first will create dirs before files
        my $info = $files->{$full};
        my $needs_update;
        my ($path, $file) = $full =~ m|^(.*?)([^/]+)$| ? ($1, $2) : do { debug $full; die "Bad file \"$full\"" };
        $path =~ s|/+$||;
        my $cd = $config->{'dest_dir'} .'/'. $path;
        if ($info->{'local_is_dir'}
            && ! $info->{'remote_is_dir'}) {
            print "Creating dir  $full\n";
            $f->cwd($cd)     || die "Couldn't cwd to $cd: ".$f->message;
            $f->mkdir($file) || die "Couldn't mkdir $full: ".$f->message;
        } elsif (! $info->{'local_is_dir'}) {
            my $src = $config->{'src_dir'} .'/'. $full;
            if (defined $info->{'local_size'}
                && $info->{'local_size'} != ($info->{'remote_size'} || 0)) {
                print "". ($info->{'remote_size'} ? "Updating" : "Creating")." file $full (because of size difference)\n";
                $f->cwd($cd)         || die "Couldn't cwd to $cd: ".$f->message; 
                $f->put($src, $file) || die "Couldn't put $full: ".$f->message;
            } elsif (defined $info->{'local_mtime'}
                     && defined $info->{'remote_mtime'}
                     && $info->{'local_mtime'} > $info->{'remote_mtime'}) {
                print "Updating file $full (because of modtime)\n";
                $f->cwd($cd)         || die "Couldn't cwd to $cd: ".$f->message;
                $f->put($src, $file) || die "Couldn't put $full: ".$f->message;
            }
        }

    }

    my $elapsed = time - $time;
    print "Done in $elapsed seconds\n";

}

