package Devel::Coverage::Utils;

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
require Exporter;

@ISA = qw(Exporter);
@EXPORT = (); # Nothing by default
@EXPORT_OK = qw(read_dot_file store_data retrieve_data resolve_pathname);
%EXPORT_TAGS = ('all' => [@EXPORT_OK]);

1;

##############################################################################
#
#   Sub Name:       read_dot_file
#
#   Description:    Read the passed file as a coverperl dot-file containing
#                   include/exclude settings.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $file     in      scalar    File name
#
#   Globals:        %Devel::Coverage::libs
#
#   Returns:        Success:    1
#                   Failure:    0
#
##############################################################################
sub read_dot_file
{
    my $file = shift;

    local *FILE;
    open(FILE, "<$file");
    if ($?)
    {
        warn "Cannot open $file for reading: $!. Skipping.\n";
        return;
    }
    while (defined($_ = <FILE>))
    {
        chomp;
        next if /^\#/o;
             next if /^\s*$/o;
        if (/^\s*include\s+(\S+)/oi)
        {
             next unless (-e "$1");
            $Devel::Coverage::instrumentation{libs}->{$1} = 1;
        }
        elsif (/^\s*exclude\s+(\S+)/oi)
        {
             next unless (-e "$1");
            $Devel::Coverage::instrumentation{libs}->{$1} = 0;
        }
        elsif (/^\s*file\s+(.*?)\s*$/oi)
        {
            $Devel::Coverage::prefs{save_file} = $1;
        }
        elsif (/^\s*storage\s+(.*?)\s*$/oi)
        {
            $Devel::Coverage::prefs{storage} = $1;
        }
        elsif (/^\s*checksum\s+(.*?)\s*$/oi)
        {
            $Devel::Coverage::prefs{checksum} = $1;
        }
        else
        {
            warn "Unrecognized line $. of $file: $_\n";
        }
    }
    close FILE;

    1;
}

##############################################################################
#
#   Sub Name:       retrieve_data
#
#   Description:    Retrieve data from the specified file, utilizing the
#                   storage method $method (this allows arbitrary formats, for
#                   conversion utilities). Return the hash ref.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $file     in      scalar    Name of file holding data
#                   $method   in      scalar    Means by which data was
#                                                 originally stored.
#
#   Globals:        None.
#
#   Returns:        Success:    hashref
#                   Failure:    undef
#
##############################################################################
sub retrieve_data
{
    my ($file, $method) = @_;

    my $data;

    eval "use $method";
    if ($@)
    {
        die "Requested data storage method ``$method'' not available " .
            "on this system.\nDid you configure Devel::Coverage?\n";
    }

    if ($method eq 'Storable')
    {
        local *FH;
        if (-e "$file")
        {
            open(FH, "< $file") ||
                die "Could not open file $file for reading: $!";
            $data = Storable::retrieve_fd(\*FH);
            close FH;
        }
        else
        {
            $data = {};
        }
    }
    elsif ($method eq 'Data::Dumper')
    {
        local *FH;
        if (-e "$file")
        {
            open(FH, "< $file") ||
                die "Could not open file $file for reading: $!";
            $data = join('', <FH>);
            close FH;
            $data =~ /^/mo; $data = $';
            eval $data;
            $data = \%data;
        }
        else
        {
            $data = {};
        }
    }
    else
    {
        warn "Storage method $method not yet supported. Sorry.";
        $data = {};
    }

    $data;
}

##############################################################################
#
#   Sub Name:       store_data
#
#   Description:    Store the data in the hashref $data, to file $file, using
#                   method $method. This abstracts enough to allow for
#                   conversion utilities.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $data     in      hashref   Data to write.
#                   $file     in      scalar    File name to write to
#                   $method   in      scalar    Desired storage method
#
#   Globals:        $prefs{backup} - does the user want a backup of the old?
#
#   Returns:        Success:    1
#                   Failure:    0
#
##############################################################################
sub store_data
{
    my ($data, $file, $method) = @_;

    rename $file, "$file.bak" if (defined $Devel::Coverage::prefs{backup} and
                                  $Devel::Coverage::prefs{backup});

    eval "use $method";
    if ($@)
    {
        die "Requested data storage method ``$method'' not available " .
            "on this system.\nDid you configure Devel::Coverage?\n";
    }

    if ($method eq 'Storable')
    {
        local *FH;

        open(FH, "> $file") || die "Could not open $file for writing: $!";
        Storable::store_fd($data, \*FH);
        close FH;
    }
    elsif ($method eq 'Data::Dumper')
    {
        local *FH;
        local $Data::Dumper::Purity = 1;
        local $Data::Dumper::Indent = 0;

        open(FH, "> $file") || die "Could not open $file for writing: $!";
        print FH Data::Dumper->Dumpxs([$data], [qw(*data)]);
        close FH;
    }
    else
    {
        warn "Storage method $method not yet supported. Sorry.";
        return 0;
    }

    1;
}

##############################################################################
#
#   Sub Name:       resolve_pathname
#
#   Description:    Try and turn a filename into a fully-resolved path, taking
#                   into account relative paths, etc.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $cwd      in      scalar    Working directory
#                   $file     in      scalar    File name
#
#   Returns:        Success:    Qualified path
#
##############################################################################
sub resolve_pathname
{
    my ($cwd, $file) = @_;

    return $file if ($file =~ m|^/|o);
    return "$cwd/$file" if ($file !~ /^\./o);

    # Yuck
    $file = "$cwd/$file";
    my @old_path = split(/\//, $file);
    my @new_path = ();
    for (@old_path)
    {
        next if (! $_);
        next if ($_ eq '.');

        if ($_ eq '..')
        {
            die "Bad path $file?" if ($#new_path == -1);
            pop(@new_path);
            next;
        }

        push(@new_path, $_);
    }

    join('/', @new_path);
}
