#!/usr/bin/perl

###############
### MODULES ###
###############

# preliminaries
use Modern::Perl '2014';
use English;
use utf8;		# script itself is in UTF-8

# core modules
use Getopt::Long;
use List::Util		qw/min/;
use Term::ANSIColor	qw/:constants/;

# non-core modules
use Data::Dumper;	# for debugging
use File::Slurp;
use MediaWiki::Bot;
use PerlIO::Util;	# for ->push_layer on *STDOUT etc

##############################
### CONFIGURATION DEFAULTS ###
##############################

# run anonymously?
# NOTE: MediaWiki::Bot 5.006003 is unable to login to newer wikis, due to
# the module's lack of maintenance and the frequent and
# backwards-incompatible changes to the MediaWiki API.
our $be_anonymous	= 1;

# debugging level to be passed to MediaWiki::Bot (0, 1 or 2).
our $debug_level	= 0;

# filename for Chris C's still_list.txt; should be downloaded from 
# https://github.com/ceebo/glider_synth/blob/master/still_list.txt
our $still_list_txt	= "still_list.txt";

# filename for Bob Shemyakin's list; should be copied from
# http://conwaylife.com/forums/viewtopic.php?p=39164#p39164 (or a later post
# that contains an updated version).
our $bob_shemyakin_txt	= "bob_shemyakin.txt";

# filename for Bob Shemyakin's 16-bit list; should be copied from
# http://conwaylife.com/forums/viewtopic.php?p=39299#p39299 (or a later post
# that contains an updated version).
our $still16_txt	= "still16.txt";

# category to fetch pages from; suggested values are "Strict still lifes" or
# "Still lifes".
our $category		= "Strict still lifes";

# username to use.
our $username		= "Apple Bot";

# password to use. Don't specify this here; pass it on the command line.
our $password		=> undef;

####################################################
### NO NEED TO CHANGE ANYTHING BEYOND THIS POINT ###
####################################################

# version and name
our $VERSION	= 0.01;
our $NAME	= "applebot.pl";

# we may dump debug info, in which case sorted hash keys would be nice.
$Data::Dumper::Sortkeys = 1;

# autoflush STDOUT
$OUTPUT_AUTOFLUSH = 1;

# also write console output to log file
*STDOUT->push_layer(tee => 'output.applebot.log');

# process options
GetOptions(
    "password|p=s"	=> \$password,
    "username|u=s"	=> \$username,
    "anonymous!"	=> \$be_anonymous,
    ) or usage();

# create a bot object we'll be using to operate
our $applebot = MediaWiki::Bot->new({
#    assert		=> 'bot',		# uncomment once Apple Bot has a bot flag on the wiki.
    operator		=> 'Apple Bottom',
#    protocol		=> 'https',		# does not currently work due to an invalid SSL certificate
    protocol		=> 'http',
    host		=> 'conwaylife.com',
    debug		=> $debug_level,
});

# call MAIN routine and exit
exit MAIN();

####################
### MAIN ROUTINE ###
####################

sub MAIN {

    my $starting_time = time;
    
    # introduce ourselves
    say "Howdy, this is ", BRIGHT_BLUE, $NAME, RESET, " v", BRIGHT_WHITE, $VERSION, RESET;
    say "Starting up at ", BRIGHT_WHITE, scalar localtime($starting_time), RESET, ".";

    # make sure Chris C's datafile exist.  We can live without Bob
    # Shemyakin's, but this one is essential for now.
    -e $still_list_txt
        or die "$still_list_txt not found.";
    
    # this hash will hold information on our objects.
    my $objects = {};
    
    # read Chris C.'s list
    print "Reading Chris C.'s list... ";
    my @ceebo_lines = read_file($still_list_txt);

    # process Chris C.'s list
    foreach my $ceebo_line (@ceebo_lines) {
    
        # split line into object number (e.g.  4.1), apgcode (e.g.  xs4_33)
        # and glider count (e.g.  2)
        my ($number, $apgcode, $synthesis) = split /\s+/, $ceebo_line;
        
        # record this object in our objects hash.
        $objects->{$apgcode} = {
            'number'		=> $number,
            'ceebo_synthesis'	=> $synthesis,
        };

    }
    
    say GREEN, "done", RESET, " (", BRIGHT_WHITE, (scalar @ceebo_lines), RESET, " lines read)";
    
    # Bob Shemyakin does not list apgcodes, so we construct a temporary
    # helper hash converting object numbers to codes.
    my %number2code = map {
        $objects->{$_}->{'number'} => $_
    } keys %$objects;
        
    # read Bob Shemyakin's list, if found
    if(-e $bob_shemyakin_txt) {
    
        print "Reading Bob Shemyakin's list... ";
        my @bob_lines = read_file($bob_shemyakin_txt);
        
        # the first line is a header line; ignore that.
        shift @bob_lines;
        
        # process Bob Shemyakin's list
        foreach my $bob_line (@bob_lines) {
        
            # split line into fields
            my ($overall_number, $bits, $bits_number, $chris_gliders, $bob_gliders, $delta_g) = split /\s+/, $bob_line;
            
            # this is the number we're interested in.
            my $number = "${bits}.${bits_number}";
            
            if(exists $number2code{$number}) {
                # we have an apgcode.
                $objects->{$number2code{$number}}->{'bob_synthesis'} = $bob_gliders;
            
            } else {
                # this shouldn't happen.
                warn "Could not identify object from Bob Shemyakin's list: $bob_line";
            
            }
        }
        
        say GREEN, "done", RESET, " (", BRIGHT_WHITE, (scalar @bob_lines), RESET, " lines read)";
    }
    
    # read Bob Shemyakin's still16.txt list, if found
    if(-e $still16_txt) {
    
        print "Reading Bob Shemyakin's 16-bit list... ";
        my @bob_lines = read_file($still16_txt);
        
        # the first line is a header line; ignore that.
        shift @bob_lines;
        
        # process Bob Shemyakin's list
        foreach my $bob_line (@bob_lines) {
        
            # split line into fields
            my ($bits, $bits_number, $bob_gliders) = split /\s+/, $bob_line;
            
            # "999 gliders" indicates no synthesis.
            next if $bob_gliders == 999;
            
            # this is the number we're interested in.
            my $number = "${bits}.${bits_number}";
            
            if(exists $number2code{$number}) {
                # we have an apgcode.
                $objects->{$number2code{$number}}->{'bob2_synthesis'} = $bob_gliders;
            
            } else {
                # this shouldn't happen.
                warn "Could not identify object from Bob Shemyakin's still16.txt list: $bob_line";
            
            }
        }
        
        say GREEN, "done", RESET, " (", BRIGHT_WHITE, (scalar @bob_lines), RESET, " lines read)";
    }
    
    # debugging: dump our object hash.
    debug_dump($objects);
    
    # log in to the wiki
    unless($be_anonymous) {
    
        # make sure user provided username and password.
        if(($username // "") eq "" or ($password // "") eq "") {
            die "No username/password specified!";
        }
    
        print "Logging in to the LifeWiki as ", BRIGHT_WHITE, $username, RESET, "... ";
        $applebot->login({
                username	=> "Apple Bot",
                password	=> "",
            }) or die "Login failed";
        say GREEN, "done", RESET;
        
    }

    # get list of page titles        
    print "Getting list of wiki pages... ";
    my @page_titles = $applebot->get_pages_in_category(
        "Category:$category",
        {
            max	=> 0,	# return all results
        }
    );
    say GREEN, "done", RESET, " (", BRIGHT_WHITE, (scalar @page_titles), RESET, " articles found)";
    
    foreach my $page_title (@page_titles) {
    
        # get page text
        print "Getting wikitext for ${page_title}... ";
        my $wikitext = $applebot->get_text($page_title);
        
        # this could conceivably happen if a page gets deleted after we
        # fetched the list of page titles.
        unless(defined $wikitext) {
            say BRIGHT_RED, "page does not exist!";
            next;
        }
        
        say GREEN, "done", RESET;
        
        # apgcode and synthesis
        my $apgcode	= undef;
        my $synthesis	= undef;
        
        # attempt to extract glider synthesis
        if($wikitext =~ m/synthesis\s*=\s*([^\s\|]+)/g) {
            $synthesis = $1;
            
#            say "\tSynthesis: ", BRIGHT_WHITE, $synthesis, RESET;
#        } else {
#            say "\tNo synthesis found";
        }
        
        # attempt to extract apgcode
        if($wikitext =~ m/\{\{LinkCatagolue\|[^\}]*(xs(\d+)_([0-9a-z]+))/g) {
            $apgcode = $1;
        
#            say "\tapgcode: ", BRIGHT_WHITE, $apgcode, RESET;
#        } else {
#            say "\tNo apgcode found";
        }
        
        # did we extract an apgcode?
        if(defined $apgcode) {
        
            # yes; remember page title and synthesis count
            $objects->{$apgcode}->{'page_title'}	= $page_title;
            $objects->{$apgcode}->{'wiki_synthesis'}	= $synthesis;
            
        }
        
    }
    
    say "Wiki         | Chris        | Bob          | Bob (16 bit) | Pattern";
    say "-------------+--------------+--------------+--------------+--------------";
    
    # Find objects we could improve (sorted by page title, only taking into
    # account objects that are on the wiki in the first place).
    foreach my $apgcode (sort { $objects->{$a}->{'page_title'} cmp $objects->{$b}->{'page_title'} } grep { exists $objects->{$_}->{'page_title'} } keys %$objects) {

        # if we have the wiki_synthesis (sub)hash key, the object was found
        # on the wiki (but the associated value may be undefined if no
        # glider synthesis count was extracted).  Same for Chris C.'s
        # synthesis.
        if(exists $objects->{$apgcode}->{'wiki_synthesis'}) {
        
            # extract synthesis counts, for convenience
            my ($wiki, $ceebo, $bob, $bob2, $page_title) = 
                map { 
                    $objects->{$apgcode}->{$_} 
                } ("wiki_synthesis", "ceebo_synthesis", "bob_synthesis", "bob2_synthesis", "page_title");
                
            # best synthesis in Chris's and Bob's files
            my $best = min ($ceebo // 999999, $bob // 999999, $bob2 // 999999);
            
            # skip patterns not on any list.
            next if $best == 999999;
            
            # is the wiki synthesis suboptimal?
            if(!defined $wiki or $best < $wiki) {
            
                # formatted values for prniting.
                my $wiki_p  = (defined $wiki)  ? sprintf("%12d", $wiki ) : "           -";
                my $ceebo_p = (defined $ceebo) ? sprintf("%12d", $ceebo) : "           -";
                my $bob_p   = (defined $bob)   ? sprintf("%12d", $bob  ) : "           -";
                my $bob2_p  = (defined $bob2)  ? sprintf("%12d", $bob2 ) : "           -";
            
                print $wiki_p;
                print " | ";
                print BOLD if ($ceebo // 999999) == $best;
                print $ceebo_p;
                print RESET;
                print " | ";
                print BOLD if ($bob   // 999999) == $best;
                print $bob_p;
                print RESET;
                print " | ";
                print BOLD if ($bob2  // 999999) == $best;
                print $bob2_p;
                print RESET;
                print " | ";
                say   $page_title;
            }
                
        }
            
    }
        
    # log out of the wiki
    unless($be_anonymous) {

        print "Logging out... ";        
        $applebot->logout();
        say GREEN, "done", RESET;    
        
    }
    
    # say goodbye
    say "Finished at ", BRIGHT_WHITE, scalar localtime(time), RESET, ".";
    
    # success!
    return 0;
}

###################
### SUBROUTINES ###
###################

# print usage information
sub usage {
    print <<ENDOFUSAGE;
Usage: $0 [options]

Options:

    --anonymous             Do not login (default). Negate with --no-anonymous.
    --username=<...>        Use specified username for logging in.
    --password=<...>        Use specified password for logging in.

ENDOFUSAGE

    exit 1;
}

# dump some data to our debug dump file
sub debug_dump {

    # file handle state variable
    state $DUMPER_FILE;
    
    # try to open file, if necessary
    unless(defined $DUMPER_FILE) {
    
        # we actually genuinely don't care if this fails. If it doesn't, the
        # dump won't get logged, and we'll try to open the file again next
        # time.  Of course it's not ideal if the dump doesn't get logged,
        # but what alternative is there, really?
        open $DUMPER_FILE, ">", "dumper.txt";
    }
    
    # if the file is open, log our dump. If the open failed, the dump will
    # silently be "dumped", no pun intended.  Since this is just logging
    # this isn't a big deal, and there's not much we can do anyway.
    if(defined $DUMPER_FILE) {
        say $DUMPER_FILE Data::Dumper::Dumper(@_);
    }
    
    # note that the dump file never gets closed explicitely in this entire
    # script.
}
