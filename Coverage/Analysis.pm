package Devel::Coverage::Analysis;

use strict;
use vars qw(@ISA @EXPORT %coverperl $dotfile);
use File::Spec;
use IO::File;
use Exporter;

use Devel::Coverage::Utils qw(:all);
use Devel::Coverage::prefs;

@ISA = ();
@EXPORT = ();

for ($ENV{HOME}, File::Spec->curdir)
{
    next unless $_;
    $dotfile = File::Spec->catfile($_, $preferences{prefs_file});
    read_dot_file $dotfile if (-e $dotfile);
}

1;

###############################################################################
#
#   Sub Name:       new
#
#   Description:    Create a new object of this class from the specified
#                   file.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Class name or reference
#                   $file     in      scalar    Name of save file to read
#
#   Globals:        %prefs
#
#   Returns:        Success:    bless ref
#                   Failure:    undef
#
###############################################################################
sub new
{
    my $self = shift;
    my $file = shift;

    my $class = ref($self) || $self;

    $self = retrieve_data $file;

    bless $self, $class;
}

###############################################################################
#
#   Sub Name:       write
#
#   Description:    Write the data in $self out to the specified file.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      scalar    Object of this class
#
#   Globals:        %prefs
#
#   Returns:        Success:    1
#                   Failure:    0
#
###############################################################################
sub write
{
    my $self = shift;
    my $file = shift;

    store_data $file;
}

###############################################################################
#
#   Sub Name:       merge
#
#   Description:    Merge the data from a second file into $self. We do this
#                   by passing $file to new, and using the resultant hashref
#                   to access the old data. Uses the same approach as in the
#                   END routine in Devel::Coverage.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $file     in      scalar    File to merge in
#
#   Globals:        %prefs
#
#   Returns:        Success:    $self
#                   Failure:    undef
#
###############################################################################
sub merge
{
    my $self = shift;
    my $file = shift;

    my $old = retrieve_data $file;
    return undef unless defined $old;

    for $file (keys %{$old->{files}})
    {
        if (! exists $self->{files}{$file})
        {
            $self->{files}{$file} = $old->{files}{$file};
            next;
        }
        # Merge old data in with the new, unless the file itself is changed
        if ($self->{files}{$file}{modtime} == $old->{files}{$file}{modtime})
        {
            # Merge. If they haven't changed, we aren't worried about
            # discrepancies in the list of lines and subs
            for (1 .. $self->{files}{$file}{totallines})
            {
                next unless (defined $self->{files}{$file}{lines}[$_]);
                $self->{files}{$file}{lines}[$_] +=
                    $old->{files}{$file}{lines}[$_];
            }
            map
            {
                $self->{files}{$file}{subs}{$_}{hits} +=
                    $old->{files}{$file}{subs}{$_}{hits}
            } (keys %{$self->{files}{$file}{subs}});
            $self->{files}{$file}{runs} += $old->{files}{$file}{runs};
        }
        else
        {
            # This version of the file is different for whatever reason.
            # Warn the user if they requested, then discard the stale
            # data
            warn "Data merge: Instrumentation of $file overwriting instead " .
                "of merging due to differences.\n"
                    if ($preferences{conflict_warnings});
            $self->{files}{$file}{runs} = 1;
        }
    }
    $self->{runs} += $old->{runs};

    undef $old;

    $self;
}

#
# The real user-methods follow. These are the means of access to the data
# itself.
#

###############################################################################
#
#   Sub Name:       dirs
#
#   Description:    Return the list of directories that this object has as
#                   its list of places where various instrumented files live
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#
#   Returns:        Success:    list
#                   Failure:    undef
#
###############################################################################
sub dirs
{
    my $self = shift;

    unless (exists $self->{'dirs'})
    {
        $self->error("dirs: No key 'dirs' in table");
        return undef;
    }

    (sort keys %{$self->{'dirs'}});
}

###############################################################################
#
#   Sub Name:       files
#
#   Description:    Return a list of files-- either the whole list ($dir is
#                   null or undef) or the files for a specified $dir.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $dir      in      scalar    If specified, a specific dir
#                                                 to list files for.
#
#   Returns:        Success:    list
#                   Failure:    undef
#
###############################################################################
sub files
{
    my $self = shift;
    my $dir = shift;

    if (defined $dir and $dir)
    {
        unless (exists $self->{'dirs'}{$dir})
        {
            $self->error("files: No such dir $dir in table");
            return undef;
        }

        (sort @{$self->{'dirs'}{$dir}});
    }
    else
    {
        (sort keys %{$self->{files}});
    }
}

###############################################################################
#
#   Sub Name:       subs
#
#   Description:    Return the list of of subroutines for the named file, or a
#                   sorted list of all subroutines in all files.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $file     in      scalar    Specific file (optional)
#
#   Returns:        Success:    1
#                   Failure:    0
#
###############################################################################
sub subs
{
    my $self = shift;
    my $file = shift || '';

    if ($file)
    {
        unless (exists $self->{'files'}{$file})
        {
            $self->("subs: No file $file in data table");
            return undef;
        }
        return (sort keys %{$self->{'files'}{$file}{subs}});
    }
    else
    {
        my @subs;
        for ($self->files)
        {
            push(@subs, (keys %{$self->{'files'}{$_}{subs}}));
        }
        return sort @subs;
    }
}

###############################################################################
#
#   Sub Name:       lines
#
#   Description:    Return the list of trackable lines on the passed-in
#                   entity. $entity is first looked for as a file, since files
#                   have fully-qualified paths, and sub names can't have / in
#                   them.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $entity   in      scalar    A file or subroutine name
#
#   Returns:        Success:    list of sparse numbers (unless code was dense)
#                   Failure:    undef
#
###############################################################################
sub lines
{
    my $self = shift;
    my $entity = shift;

    my @lines;

    unless (defined $entity)
    {
        $self->error("lines: requires an entity");
        return undef;
    }

    if (exists $self->{'files'}{$entity})
    {
        @lines = grep(defined $self->{'files'}{$entity}{lines}[$_],
                      (1 .. $self->{'files'}{$entity}{totallines}));
        return @lines;
    }
    else
    {
        #
        # Have to figure out which file this sub is in
        #
        my $file;
        for $file ($self->files)
        {
            if (exists $self->{'files'}{$file}{'subs'}{$entity})
            {
                my ($start, $end) = $self->total_lines($entity);
                @lines =
                    grep(defined $self->{'files'}{$file}{lines}[$_],
                         ($start .. $end));
                return @lines;
            }
        }

        #
        # Wasn't found
        #
        $self->error("lines: $entity not recognized as a file or subroutine " .
                     "in table");
        return undef;
    }

    @lines;
}

###############################################################################
#
#   Sub Name:       total_lines
#
#   Description:    Sort of like lines() but returns the total number of lines
#                   in a file, or in a sub. If called in a list context with
#                   a sub as $entity, it returns the (start, end) pair instead
#                   of a count.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $entity   in      scalar    File or sub specification
#
#   Returns:        Success:    number or tuple
#                   Failure:    undef
#
###############################################################################
sub total_lines
{
    my $self = shift;
    my $entity = shift;

    my ($start, $end);

    unless (defined $entity)
    {
        $self->error("total_lines requires an entity");
        return undef;
    }

    if (exists $self->{'files'}{$entity})
    {
        return $self->{'files'}{$entity}{totallines};
    }
    else
    {
        #
        # Have to figure out which file this sub is in
        #
        my $file;
        for $file ($self->files)
        {
            if (exists $self->{'files'}{$file}{'subs'}{$entity})
            {
                ($start, $end) =
                    $self->{'files'}{$file}{'subs'}{$entity}{dbinfo} =~
                        /.*:(\d+)-(\d+)/o;
                return ((wantarray) ? ($start, $end) : ($end - $start + 1));
            }
        }

        #
        # Wasn't found
        #
        $self->error("total_lines: $entity not found as file or subroutine " .
                     "in table");
        return undef;
    }
}

###############################################################################
#
#   Sub Name:       runs
#
#   Description:    Return the number of times run, either overall from the
#                   top-level object, or for a specified file.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $file     in      scalar    Optional file to use
#
#   Returns:        Success:    count
#                   Failure:    undef
#
###############################################################################
sub runs
{
    my $self = shift;
    my $file = shift;

    if (defined $file and $file)
    {
        return ($self->{'files'}{$file}{runs})
            if (exists $self->{'files'}{$file});
        $self->error("runs: $file not in table");
        return undef;
    }
    else
    {
        return $self->{runs};
    }
}

###############################################################################
#
#   Sub Name:       count
#
#   Description:    Return the hit-count for a given line or subroutine, based
#                   on whether $entity is a number or not. If they are asking
#                   for sub data, then $file is actually optional.
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $file     in      scalar    File (optional for subs) to
#                                                 look for $entity within
#                   $entity   in      scalar    Entity to get counts for
#
#   Returns:        Success:    number
#                   Failure:    undef
#
###############################################################################
sub count
{
    my $self = shift;
    my $file = shift;
    my $entity = shift;

    unless (defined $file and $file)
    {
        $self->error("count: requires at least a subroutine, or file and " .
                     "line number arguments");
        return undef;
    }

    if (defined $entity and $entity =~ /^\d+$/o)
    {
        #
        # Treat it as a line number, $file is a filename
        #
        unless (defined $self->{'files'}{$file})
        {
            $self->error("count: No file $file in table");
            return undef;
        }
        unless ($entity >= 1 and
                $entity <= $self->{'files'}{$file}{totallines} and
                defined $self->{'files'}{$file}{'lines'}[$entity])
        {
            $self->error("count: Line $entity of $file out of range or not " .
                         "breakable");
            return undef;
        }

        return $self->{'files'}{$file}{'lines'}[$entity];
    }
    else
    {
        #
        # $file might be the subroutine, or it might be the file and $entity
        # be the subroutine.
        #
        if (exists $self->{'files'}{$file})
        {
            # $entity is subroutine
            unless (defined $self->{'files'}{$file}{'subs'}{$entity})
            {
                $self->error("count: Subroutine $entity not in table for " .
                             "$file");
                return undef;
            }
            return $self->{'files'}{$file}{'subs'}{$entity}{hits};
        }
        else
        {
            #
            # They skipped passing file. Move subname into $entity and figure
            # out which file it's in.
            #
            $entity = $file;
            for $file ($self->files)
            {
                return ($self->{'files'}{$file}{'subs'}{$entity}{hits})
                    if (defined $self->{'files'}{$file}{'subs'}{$entity});
            }
            # Didn't find it
            $self->error("count: Subroutine $entity not in table");
            return undef;
        }
    }
}

###############################################################################
#
#   Sub Name:       error
#
#   Description:    Set or return the current error message on $self
#
#   Arguments:      NAME      IN/OUT  TYPE      DESCRIPTION
#                   $self     in      ref       Object of this class
#                   $error    in      scalar    If passed, new error text
#
#   Globals:        None.
#
#   Environment:    None.
#
#   Returns:        text
#
###############################################################################
sub error
{
    my $self = shift;
    my $error = shift || '';

    $self->{__error__} = $error if $error;

    $self->{__error__};
}
