#!/usr/local/bin/perl

use Config;
use File::Basename qw(&basename &dirname);

# List explicitly here the variables you want Configure to
# generate.  Metaconfig only looks for shell variables, so you
# have to mention them as if they were shell variables, not
# %Config entries.  Thus you write
#  $startperl
# to ensure Configure will look for $Config{startperl}.

# This forces PL files to create target in same directory as PL file.
# This is so that make depend always knows where to find PL derivatives.
chdir(dirname($0));
($file = basename($0)) =~ s/\.PL$//;
$file =~ s/\.pl$//
	if ($Config{'osname'} eq 'VMS' or
	    $Config{'osname'} eq 'OS2');  # "case-forgiving"

open OUT,">$file" or die "Can't create $file: $!";

print "Extracting $file (with variable substitutions)\n";

# In this section, perl variables will be expanded during extraction.
# You can use $Config{...} to use Configure variables.

print OUT <<"!GROK!THIS!";
$Config{'startperl'}
    eval 'exec perl -S \$0 "\$@"'
	if 0;
!GROK!THIS!

# In the following, perl variables are not expanded during extraction.

print OUT <<'!NO!SUBS!';
##############################################################################
#
#   @(#)$Id: coverperl.PL,v 1.1 1997/09/01 23:06:59 rjray Exp rjray $  
#
#   Description:    
#
#   Functions:      
#
#   Libraries:      Devel::Coverage::Utils
#                   Storable (maybe)
#                   Data::Dumper (maybe)
#
##############################################################################

use lib '/u/rjray';
use Devel::Coverage::Utils qw(read_dot_file retrieve_data);

require 'Devel/Coverage/coverperl_prefs.pl';
read_dot_file("$ENV{HOME}/.coverperl") if (-e "$ENV{HOME}/.coverperl");
read_dot_file("./.coverperl") if (-e "./.coverperl");

*prefs = \%Devel::Coverage::prefs;

my $file = shift(@ARGV);
$file = $prefs{default_file} unless ($file);

die "No CoverPerl data file $file" unless (-e "$file");

$data = retrieve_data($file, ($prefs{storage} || $prefs{default_storage}));
%inst = %{$data};

print "Total of $inst{runs} instrumentation runs.\n\n";

for $file (sort keys %{$inst{files}})
{
    print "$file\n";
    for $sub (sort keys %{$inst{files}{$file}{subs}})
    {
	next if ($sub =~ /::(BEGIN|END)$/o);
	printf("\t%-3d %s\n",
	       ($inst{files}{$file}{subs}{$sub}{hits} || 0), $sub);
	($start, $end) =
	    $inst{files}{$file}{subs}{$sub}{dbinfo} =~ /^.*:(\d+)-(\d+)/o;
	for ($ln = $start; $ln <= $end; $ln++)
	{
	    next unless (defined $inst{files}{$file}{lines}[$ln]);
	    printf("\t\t%-4d line %-4d\n",
		   $inst{files}{$file}{lines}[$ln], $ln);
	    undef $inst{files}{$file}{lines}[$ln];
	}
    }
    for ($ln = 1; $ln <= $inst{files}{$file}{totallines}; $ln++)
    {
	next unless (defined $inst{files}{$file}{lines}[$ln]);
	printf("\t%-4d line %-4d\n", $inst{files}{$file}{lines}[$ln], $ln);
    }
    print "\n";
}
!NO!SUBS!

close OUT or die "Can't close $file: $!";
chmod 0755, $file or die "Can't reset permissions for $file: $!\n";
exec("$Config{'eunicefix'} $file") if $Config{'eunicefix'} ne ':';
