package Devel::Coverage;

use strict;
use vars qw(@ISA $VERSION %instrumentation %libs);

use Devel::Coverage::prefs;
use Devel::Coverage::Utils ':all';
use File::Spec;
use Cwd 'cwd';

#
# Set up the run-time environment
#
BEGIN
{
    @ISA = qw();
    $VERSION = '0.2';

    *DB::resolve_pathname = \&Devel::Coverage::resolve_pathname;
    *DB::inst  = \%Devel::Coverage::instrumentation;
    %DB::lines = ();
    %DB::subs = ();

    #
    # Initialize our data stores
    #
    $instrumentation{files} = {};
    $instrumentation{dirs}  = {};
    $instrumentation{libs}  = {};

    unless ($preferences{default_file})
    {
        my $cmd = (File::Spec->splitpath($0))[2];
        $preferences{default_file} = "$cmd.cvp";
    }

    #
    # Before we look at include/exclude directives, mark all the values of
    # @INC for inclusion. The configuration process gave them the change to
    # exclude these, not to mention the dot-files.
    #
    grep($libs{$_} = 1, @INC);

    if ($preferences{include})
    {
        grep($instrumentation{libs}{$_} = 1, split(/:/,
                                                   $preferences{include}));
    }
    if ($preferences{exclude})
    {
        # Don't just undef the key, a value of 0 marks it for discrimination
        grep($instrumentation{libs}{$_} = 0, split(/:/,
                                                   $preferences{exclude}));
    }

    #
    # Basic personal prefs
    #
    my $dotfile;
    for ($ENV{HOME}, File::Spec->curdir)
    {
        next unless $_;
        $dotfile = File::Spec->catfile($_, $preferences{prefs_file});
        read_dot_file $dotfile if (-e $dotfile);
    }

    $instrumentation{'cwd'} = cwd;
}

#
# Generate the report at the end
#
sub END
{
    my ($file, %file, $sub, $start, $end, $ln, $old_data, %tmp);
    $DB::trace = 0;

    #
    # Start by collating the data gathering in %DB::subs and %DB::lines
    #
    for (keys %DB::subs)
    {
        ($file, $sub) = split(/:/, $_, 2);
        next unless (exists $instrumentation{files}{$file} &&
                     exists $instrumentation{files}{$file}{subs}{$sub});
        $instrumentation{files}{$file}{subs}{$sub}{hits} = $DB::subs{$_};
        $instrumentation{files}{$file}{subs}{$sub}{dbinfo} = $DB::sub{$sub};
    }
    for (keys %DB::lines)
    {
        ($file, $ln) = split(/:/, $_);
        next unless (exists $instrumentation{files}{$file});
        $instrumentation{files}{$file}{lines}[$ln] = $DB::lines{$_};
    }

    my $data_file = $preferences{save_file} || $preferences{default_file};
    $data_file .= '.cvp' unless (substr($data_file, -4) eq '.cvp');

    #
    # Normalize the filename keys. Take the full pathname, and basically
    # re-key this data under that value.
    #
    for $file (keys %{$instrumentation{files}})
    {
        if ($file eq $instrumentation{files}{$file}{fullpath})
        {
            delete $instrumentation{files}{$sub}{fullpath};
            next;
        }

        $sub = $instrumentation{files}{$file}{fullpath};
        $instrumentation{files}{$sub} = $instrumentation{files}{$file};
        delete $instrumentation{files}{$file};
        delete $instrumentation{files}{$sub}{fullpath};
    }

    $old_data = retrieve_data $data_file;

    for $file (keys %{$old_data->{dirs}})
    {
        # Add in any entries not already known from this run
        %tmp = map { $_, 1 } (@{$old_data->{dirs}{$file}});
        map { $tmp{$_}++ } (@{$instrumentation{dirs}{$file}})
            if (defined $instrumentation{dirs}{$file});
        $instrumentation{dirs}{$file} = [sort keys %tmp];
    }
    for $file (keys %{$old_data->{files}})
    {
        if (! exists $instrumentation{files}{$file})
        {
            $instrumentation{files}{$file} = $old_data->{files}{$file};
            next;
        }
        # Merge old data in with the new, unless the file itself is changed
        if ($instrumentation{files}{$file}{modtime} ==
            $old_data->{files}{$file}{modtime})
        {
            # Merge. If they haven't changed, we aren't worried about
            # discrepancies in the list of lines and subs
            for (1 .. $instrumentation{files}{$file}{totallines})
            {
                next unless
                    (defined $instrumentation{files}{$file}{lines}[$_]);
                $instrumentation{files}{$file}{lines}[$_] +=
                    $old_data->{files}{$file}{lines}[$_];
            }
            map
            {
                $instrumentation{files}{$file}{subs}{$_}{hits} +=
                    $old_data->{files}{$file}{subs}{$_}{hits};
            } (keys %{$instrumentation{files}{$file}{subs}});
        }
        else
        {
            # This version of the file is different for whatever reason.
            # Warn the user if they requested, then discard the stale
            # data
            warn "Instrumentation of $file overwriting instead of " .
                "merging due to differences.\n"
                    if ($preferences{conflict_warnings});
        }
    }

    $instrumentation{runs} = $old_data->{runs} || 0;
    $instrumentation{runs}++;
    delete $instrumentation{'cwd'}; # No longer needed

    store_data \%instrumentation, $data_file;

    #
    # Leave this in for now, as a means by which I can debug output without
    # major hacks (just commenting out storage declaration in prefs file).
    #
    map
    {
        %file = %{$instrumentation{files}{$_}};
        print "$file{fullpath}\n";
        for $sub (sort keys %{$file{subs}})
        {
            next if ($sub =~ /::(BEGIN|END)$/o);
            printf("\t%-3d %s\n", $file{subs}{$sub}{hits}, $sub);
            ($start, $end) = $DB::sub{$sub} =~ /^.*:(\d+)-(\d+)/o;
            for ($ln = $start; $ln <= $end; $ln++)
            {
                next unless (defined $file{lines}[$ln]);
                printf("\t\t%-4d %-4d\n", $file{lines}[$ln], $ln);
                $file{lines}[$ln] = undef;
            }
        }
        for ($ln = 1; $ln <= $file{totallines}; $ln++)
        {
            next unless (defined $file{lines}[$ln]);
            printf("\t%-4d %-4d\n", $file{lines}[$ln], $ln);
        }
        print "\n";
    } (sort keys %{$instrumentation{files}})
        if ($preferences{debugging});

    return;
}

package DB;

no strict;

BEGIN { $DB::trace = 1; }

sub postponed
{
    local *dbline = shift;

    my $filename = $dbline;
    $filename =~ s/^_<//o;
    return if ($filename =~ /\(eval \d+/o);
    # Not currently any way to derive the actual filename from the path given
    return if ($filename =~ /autosplit into /);
    # Skip our files
    return if ($filename =~ m|Devel/Coverage|);
    my ($excl_key, $incl_key) = ('', '');
    for (sort { length $b <=> length $a } (grep($inst{libs}{$_} == 0,
                                                keys %{$inst{libs}})))
    {
        if (substr($filename, 0, length($_)) eq $_)
        {
            $excl_key = $_;
            last;
        }
    }
    for (sort (grep($inst{libs}{$_} == 1, keys %{$inst{libs}})))
    {
        if (substr($filename, 0, length($_)) eq $_)
        {
            $incl_key = $_;
            last;
        }
    }
    return if ($excl_key and (length($incl_key) < length($excl_key)));

    #
    # OK. We're pretty sure we'll track this one after all.
    #
    map
    {
        $inst{files}{$filename}{subs}{$_} = {};
        $inst{files}{$filename}{subs}{$_}{hits} = 0;
        $inst{files}{$filename}{subs}{$_}{dbinfo} = $sub{$_};
    }
    (grep((substr($sub{$_}, 0, length($filename)+1) eq "$filename:"),
          keys %sub));

    local $^W = 0;
    $inst{files}{$filename}{lines} = [];
    my $ln;
    for ($ln = 1; $ln <= $#dbline; $ln++)
    {
        $inst{files}{$filename}{lines}[$ln] = undef;
        next if ($dbline[$ln] == 0);
        $inst{files}{$filename}{lines}[$ln] = 0
            unless (defined $inst{files}{$filename}{lines}[$ln]);
    }
    $inst{files}{$filename}{totallines} = $#dbline;
    $inst{files}{$filename}{modtime} = (stat $filename)[9];
    $inst{files}{$filename}{fullpath} = resolve_pathname($inst{cwd},$filename);
    my $dir = (File::Spec->splitpath($inst{files}{$filename}{fullpath}))[1];
    if (defined $inst{dirs}{$dir})
    {
        # Add this full pathname to the list, then re-sort it and re-assign it
        my @tmp = @{$inst{dirs}{$dir}};
        push(@tmp, $inst{files}{$filename}{fullpath});
        $inst{dirs}{$dir} = [sort @tmp];
    }
    else
    {
        # Create the list with this entry
        $inst{dirs}{$dir} = [$inst{files}{$filename}{fullpath}];
    }
}

sub DB
{
    my ($package, $filename, $line) = caller;

    $lines{"$filename:$line"}++;
}

sub sub
{
    $sub{$sub} =~ /^(.*):\d+/o if (defined $sub{$sub});
    my $filename = $1 || '';
    $subs{"$filename:$sub"}++;
    &$sub;
}

1;

__END__

=head1 NAME

Devel::Coverage - Perl module to perform coverage analysis

=head1 SYNOPSIS

    perl -d:Coverage script_name [ args ]

=head1 DESCRIPTION

This software is still very early-alpha quality. Use the tool C<coverperl> to
analyze the files that result from running your scripts with coverage enabled.

=head1 AUTHOR

Randy J. Ray <rjray@blackperl.com>

=head1 SEE ALSO

L<Devel::DProf>

=cut
