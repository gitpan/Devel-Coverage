package Devel::Coverage;

#
# Set up the run-time environment
#
BEGIN
{
    use Devel::Coverage::Utils ':all';
    use Cwd 'cwd';

    @ISA = qw();
    $VERSION = '0.1';

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

    #
    # Read the preferences file to set things like the storage method, global-
    # level libs and excludes, picking default names, yada yada yada...
    #
    require 'Devel/Coverage/coverperl_prefs.pl';

    unless (defined $prefs{default_file} and $prefs{default_file})
    {
        my $cmd = $0;
        $cmd =~ s|.*/||o;
        $prefs{default_file} = "$cmd.cvp";
    }

    #
    # Before we look at include/exclude directives, mark all the values of
    # @INC for inclusion. The configuration process gave them the change to
    # exclude these, not to mention the dot-files.
    #
    grep($libs{$_} = 1, @INC);

    if (defined $prefs{include} and $prefs{include})
    {
        grep($instrumentation{libs}{$_} = 1, split(/:/, $prefs{include}));
    }
    if (defined $prefs{exclude} and $prefs{exclude})
    {
        # Don't just undef the key, a value of 0 marks it for discrimination
        grep($instrumentation{libs}{$_} = 0, split(/:/, $prefs{exclude}));
    }

    #
    # Basic personal prefs
    #
    read_dot_file("$ENV{HOME}/.coverperl") if (-e "$ENV{HOME}/.coverperl");
    # Local to the running dir
    read_dot_file("./.coverperl") if (-e "./.coverperl");

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

    my $storage = $prefs{storage} || $prefs{default_storage};
    my $data_file = $prefs{save_file} || $prefs{default_file};
    $data_file .= '.cvp' unless ($data_file =~ /\.cvp$/o);

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
    if ($storage)
    {
        $old_data = retrieve_data($data_file, $storage);

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
                        $old_data->{files}{$file}{subs}{$_}{hits}
                } (keys %{$instrumentation{files}{$file}{subs}});
            }
            else
            {
                # This version of the file is different for whatever reason.
                # Warn the user if they requested, then discard the stale
                # data
                warn "Instrumentation of $file overwriting instead of " .
                    "merging due to differences.\n"
                        if ($prefs{conflict_warnings});
            }
        }
        $instrumentation{runs} = $old_data->{runs} || 0;
        $instrumentation{runs}++;
        delete $instrumentation{'cwd'}; # No longer needed

        store_data \%instrumentation, $data_file, $storage;
        return;
    }

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
    } (sort keys %{$instrumentation{files}});
}

package DB;

BEGIN { $DB::trace = 1; }

sub postponed
{
    local *dbline = shift;

    my $filename = $dbline;
    $filename =~ s/^_<//o;
    return if ($filename =~ /\(eval \d+/o);
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
        $incl_key = $_, last
            if (substr($filename, 0, length($_)) eq $_);
    }
    return if ($excl_key and (not length($incl_key) > length($excl_key)));

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
    my ($dir) = $inst{files}{$filename}{fullpath} =~ m|(.*)/|o;
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

=head1 AUTHOR

Randy J. Ray <rjray@uswest.com>

=head1 SEE ALSO

L<Devel::DProf>

=cut
