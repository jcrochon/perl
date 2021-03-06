#!/usr/bin/perl

 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#    Jason C. Rochon                                                                    #
#    Mar 13, 2015                                                                       #
#                                                                                       #
#    Notes:                                                                             #
#                                                                                       #
#        1.) cron job: weekly from gateway-2                                            #
#                                                                                       #
#        2.) Searches for 2003 machines via nmap and reports:                           #
#              A.) Hostname                                                             #
#              B.) IP                                                                   #
#              C.) MAC                                                                  #
#              D.) OS                                                                   #
#                                                                                       #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

#use strict;
#use warnings;
#use Data::Dumper::Simple;

use Getopt::Std;
use Nmap::Parser;

 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#   Usage: /usr/local/flowtools/nmap_parsers/parse-device-netsecs -q XP devices.xml     #
#                                                                                       #
#   Options: -h   Help      displays help topic                                         #
#            -q   Query     which OS to query                                           #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

our %opt;
getopts( 'hq:', \%opt );    # values in %opts{q}

 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#   Print Help                                                                          #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if ( $opt{h} ) {
    print "\n  Usage:\n\t/usr/local/flowtools/nmap_parsers/parse-device-netsecs -q XP devices.xml\n\n"
      . "Options:\n"
      . "\t-h \tHelp\t\tdisplays help topic\n"
      . "\t-q \tQuery\t\twhich OS to query\n\n";
    exit;
}

 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#   Parse File                                                                          #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

my $np     = new Nmap::Parser;
my $infile = $ARGV[0];
$np->parsefile($infile);

 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#   Session Data                                                                        #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

my $si = $np->get_session;

print "Windows $opt{q} Machines" . "\nOnline between " . $si->start_str . " and " . $si->time_str;

 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#   Find Machines                                                                       #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

our @zones;
for my $host ( $np->all_hosts ) {
    my $os = $host->os_sig;

    my @array_names = $os->all_names;

print $host->ipv4_addr . "\n[@array_names]\n";
print (grep {/$opt{q}/} @array_names);
print "\nDebugging names above...\n";

    next unless defined $os->osgen;
    if ( ( $os->osgen eq $opt{q} ) or ( grep { /$opt{q}/ } @array_names ) ) {
        my $zone = ( $host->hostname . "\t" . $host->ipv4_addr . "\t" . $host->mac_addr . "\t" . $os->name . "\n" );
        push( @zones, $zone );
    }
}

 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#   Print Sorted File                                                                   #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

my @newzones = sort { ( $a =~ /.*\.(.*\.uic\.edu) *./ )[0] cmp( $b =~ /.*\.(.*\.uic\.edu) *./ )[0] } @zones;

&print_netsecs( \@newzones );

 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#   Priming DB2 Access                                                                  #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

my %pbopt;
use UIC::Paw;

BEGIN {
    %pbopt = (
        DB2 => {
            TBCREATOR => 'pb',
            DATABASE  => 'ACCCDATA',
            USER      => 'webpbrw',
            PASSWD    => UIC::Paw::get('webpbrw@rabbit'),
        }
    );
}

use UIC::MQ::BasicClients;
use PBUIC   (%pbopt);
use UIC::PW (%pbopt);

 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#   Query Who To CC                                                                     #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

sub who_cc {
    $z = shift;

    my $ps = PersonSet->fill(
        -LIAISON_TYPE   => 'NETSEC',
        -ZONE_2_LIAISON => $z,
    );

    my @people = $ps->getPersistents;

    unless (@people) {
        $ps = PersonSet->fill(
            -LIAISON_TYPE   => 'REACH',
            -ZONE_2_LIAISON => $z,
        );

        @people = $ps->getPersistents;
    }

    foreach my $p (@people) {
        push( @$cc, $p->pnetid . '@uic.edu' );
    }
    $cc = join( ';', @$cc );
    return ($cc);
}

 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#   Print Netsecs                                                                       #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

sub print_netsecs {
    my $zones   = shift;
    my $oldzone = '';

    foreach (@$zones) {
        my $zone = $1 if ( $_ =~ /.*\.(.*\.uic\.edu).*/ );
        my $currzone = $zone;

        print "\n\nZone: $zone" unless ( $oldzone eq $currzone );
        print "\nNetsec: " . &who_cc($zone) unless ( $oldzone eq $currzone );

        print "\n$&";    # all info

        $oldzone = $currzone;
    }
    print "\n";
}

 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#   Exit Routine                                                                        #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

print "\n\n";
exit;
