#!/usr/bin/perl
#             __________               __   ___.
#   Open      \______   \ ____   ____ |  | _\_ |__   _______  ___
#   Source     |       _//  _ \_/ ___\|  |/ /| __ \ /  _ \  \/  /
#   Jukebox    |    |   (  <_> )  \___|    < | \_\ (  <_> > <  <
#   Firmware   |____|_  /\____/ \___  >__|_ \|___  /\____/__/\_ \
#                     \/            \/     \/    \/            \/
# $Id$
#

$ROOT="..";



my $ziptool="zip";
my $output="rockbox.zip";
my $verbose;
my $exe;
my $target;

while(1) {
    if($ARGV[0] eq "-r") {
        $ROOT=$ARGV[1];
        shift @ARGV;
        shift @ARGV;    
    }

    elsif($ARGV[0] eq "-z") {
        $ziptool=$ARGV[1];
        shift @ARGV;
        shift @ARGV;    
    }

    elsif($ARGV[0] eq "-o") {
        $output=$ARGV[1];
        shift @ARGV;
        shift @ARGV;    
    }

    elsif($ARGV[0] eq "-v") {
        $verbose =1;
        shift @ARGV;
    }
    else {
        $target = $ARGV[0];
        $exe = $ARGV[1];
        last;
    }
}


my $firmdir="$ROOT/firmware";

my $cppdef = $target;


sub filesize {
    my ($filename)=@_;
    my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
        $atime,$mtime,$ctime,$blksize,$blocks)
        = stat($filename);
    return $size;
}

sub buildlangs {
    my ($outputlang)=@_;
    my $dir = "$ROOT/apps/lang";
    opendir(DIR, $dir);
    my @files = grep { /\.lang$/ } readdir(DIR);
    closedir(DIR);

    for(@files) {
        my $output = $_;
        $output =~ s/(.*)\.lang/$1.lng/;
        print "lang $_\n" if($verbose);
        system ("$ROOT/tools/binlang $dir/english.lang $dir/$_ $outputlang/$output >/dev/null 2>&1");
    }
}

sub buildzip {
    my ($zip, $image, $notplayer)=@_;

    # remove old traces
    `rm -rf .rockbox`;

    mkdir ".rockbox", 0777;
    mkdir ".rockbox/langs", 0777;
    mkdir ".rockbox/rocks", 0777;
    mkdir ".rockbox/codecs", 0777;
    mkdir ".rockbox/codepages", 0777;
    mkdir ".rockbox/wps", 0777;
    mkdir ".rockbox/themes", 0777;
    mkdir ".rockbox/backdrops", 0777;

    my $c = 'find apps -name "*.codec" ! -empty -exec cp {} .rockbox/codecs/ \;';
    print `$c`;

    system("$ROOT/tools/codepages");
    my $c = 'find . -name "*.cp" ! -empty -exec mv {} .rockbox/codepages/ \; >/dev/null 2>&1';
    print `$c`;

    my @call = `find .rockbox/codecs -type f`;
    if(!$call[0]) {
        # no codec was copied, remove directory again
        rmdir(".rockbox/codecs");

    }


    $c= 'find apps "(" -name "*.rock" -o -name "*.ovl" ")" ! -empty -exec cp {} .rockbox/rocks/ \;';
    print `$c`;

    open VIEWERS, "$ROOT/apps/plugins/viewers.config" or
        die "can't open viewers.config";
    @viewers = <VIEWERS>;
    close VIEWERS;

    open VIEWERS, ">.rockbox/viewers.config" or
        die "can't create .rockbox/viewers.config";
    mkdir ".rockbox/viewers", 0777;
    foreach my $line (@viewers) {
        if ($line =~ /([^,]*),([^,]*),/) {
            my ($ext, $plugin)=($1, $2);
            my $r = "${plugin}.rock";
            my $oname;

            my $dir = $r;
            my $name;

            # strip off the last slash and file name part
            $dir =~ s/(.*)\/(.*)/$1/;
            # store the file name part
            $name = $2;

            # get .ovl name (file part only)
            $oname = $name;
            $oname =~ s/\.rock$/.ovl/;

            # print STDERR "$ext $plugin $dir $name $r\n";

            if(-e ".rockbox/rocks/$name") {
                if($dir ne "rocks") {
                    # target is not 'rocks' but the plugins are always in that
                    # dir at first!
                    `mv .rockbox/rocks/$name .rockbox/$r`;
                }
                print VIEWERS $line;
            }
            elsif(-e ".rockbox/$r") {
                # in case the same plugin works for multiple extensions, it
                # was already moved to the viewers dir
                print VIEWERS $line;
            }

            if(-e ".rockbox/rocks/$oname") {
                # if there's an "overlay" file for the .rock, move that as
                # well
                `mv .rockbox/rocks/$oname .rockbox/$dir`;
            }
        }
    }
    close VIEWERS;
    
    if($notplayer) {
        `cp $ROOT/apps/plugins/sokoban.levels .rockbox/rocks/`; # sokoban levels
        `cp $ROOT/apps/plugins/snake2.levels .rockbox/rocks/`; # snake2 levels

        mkdir ".rockbox/fonts", 0777;

        opendir(DIR, "$ROOT/fonts") || die "can't open dir fonts";
        my @fonts = grep { /\.bdf$/ && -f "$ROOT/fonts/$_" } readdir(DIR);
        closedir DIR;

        for(@fonts) {
            my $f = $_;

            print "FONT: $f\n" if($verbose);
            my $o = $f;
            $o =~ s/\.bdf/\.fnt/;
            my $cmd ="$ROOT/tools/convbdf -f -o \".rockbox/fonts/$o\" \"$ROOT/fonts/$f\" >/dev/null 2>&1";
            print "CMD: $cmd\n" if($verbose);
            `$cmd`;
            
        }

    }

    if($image) {
        # image is blank when this is a simulator
        if( filesize("rockbox.ucl") > 1000 ) {
            `cp rockbox.ucl .rockbox/`;  # UCL for flashing
        }
        if( filesize("rombox.ucl") > 1000) {
            `cp rombox.ucl .rockbox/`;  # UCL for flashing
        }
    }

    mkdir ".rockbox/docs", 0777;
    for(("BATTERY-FAQ",
         "CUSTOM_CFG_FORMAT",
         "CUSTOM_WPS_FORMAT",
         "FAQ",
         "LICENSES",
         "NODO",
         "TECH")) {
        `cp $ROOT/docs/$_ .rockbox/docs/$_.txt`;
    }

    # Now do the WPS dance
    if(-d "$ROOT/wps") {
        system("perl $ROOT/wps/wpsbuild.pl -r $ROOT $ROOT/wps/WPSLIST $target");
    }
    else {
        print STDERR "No wps module present, can't do the WPS magic!\n";
    }

    # now copy the file made for reading on the unit:
    #if($notplayer) {
    #    `cp $webroot/docs/Help-JBR.txt .rockbox/docs/`;
    #}
    #else {
    #    `cp $webroot/docs/Help-Stu.txt .rockbox/docs/`;
    #}

    buildlangs(".rockbox/langs");

    `rm -f $zip`;
    `find .rockbox | xargs $ziptool $zip >/dev/null`;

    if($image) {
        `$ziptool $zip $image`;
    }

    # remove the .rockbox afterwards
    `rm -rf .rockbox`;
}

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
 localtime(time);

$mon+=1;
$year+=1900;

$date=sprintf("%04d%02d%02d", $year,$mon, $mday);
$shortdate=sprintf("%02d%02d%02d", $year%100,$mon, $mday);

# made once for all targets
sub runone {
    my ($type, $target)=@_;

    # build a full install zip file 
    buildzip($output, $target,
             ($type eq "player")?0:1);
};

if(!$exe) {
    # not specified, guess!
    if($target =~ /(recorder|ondio)/i) {
        $exe = "ajbrec.ajz";
    }
    elsif($target =~ /iriver/i) {
        $exe = "rockbox.iriver";
    }
    elsif($target =~ /gmini/i) {
        $exe = "rockbox.gmini";
    }
    else {
        $exe = "archos.mod";
    }
}
elsif($exe =~ /rockboxui/) {
    # simulator, exclude the exe file
    $exe = "";
}

if($target =~ /player/i) {
    runone("player", $exe);
}
else {
    runone("recorder", $exe);
}

