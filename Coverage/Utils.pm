package Devel::Coverage::Utils;

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

use Data::Dumper;
use Symbol;
use File::Spec;
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
##############################################################################
sub read_dot_file
{
    my $file = shift;

    my $fh = gensym;
    open($fh, "<$file");
    if ($?)
    {
        warn "Cannot open $file for reading: $!. Skipping.\n";
        return;
    }

    while (defined($_ = <$fh>))
    {
        chomp;
        next if /^\#/;
        next if /^\s*$/;

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
            $Devel::Coverage::preferences{save_file} = $1;
        }
        elsif (/^\s*checksum\s+(.*?)\s*$/oi)
        {
            $Devel::Coverage::preferences{checksum} = $1;
        }
        else
        {
            warn "Unrecognized line $. of $file: $_\n";
        }
    }
    close $fh;

    return;
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
#
#   Globals:        None.
#
#   Returns:        Success:    hashref
#                   Failure:    undef
#
##############################################################################
sub retrieve_data
{
    my ($file) = @_;

    my ($data, %data);

    my $fh = gensym;
    if (-e "$file")
    {
        open($fh, "< $file") ||
            die "Could not open file $file for reading: $!";
        $data = join('', <$fh>);
        close $fh;
        $data =~ /^/mo; $data = $';
        eval $data;
        $data = \%data;
    }
    else
    {
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
#
#   Globals:        $preferences{backup} - does user want a backup of the old?
#
#   Returns:        Success:    1
#                   Failure:    0
#
##############################################################################
sub store_data
{
    my ($data, $file) = @_;

    rename $file, "$file.bak" if ($Devel::Coverage::preferences{backup});

    my $fh = gensym;
    local $Data::Dumper::Purity = 1;
    local $Data::Dumper::Indent = 0;

    open($fh, "> $file") || die "Could not open $file for writing: $!";
    print $fh (Data::Dumper->Dumpxs([$data], [qw(*data)]));
    close $fh;

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

    $file = File::Spec->catfile($cwd, $file)
	unless File::Spec->file_name_is_absolute($file);
    my @old_path = File::Spec->splitdir($file);
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

    File::Spec->catfile('', @new_path);
}
