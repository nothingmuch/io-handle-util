package IO::Handle::Util;

use strict;
use warnings;

use warnings::register;

use Scalar::Util ();

# we use this to create errors
#use autodie ();

# perl blesses IO objects into these namespaces, make sure they are loaded
use IO::Handle ();
use FileHandle ();

# fake handle types
#use IO::String ();
#use IO::Handle::Iterator ();

#use IO::Handle::Prototype::Fallback ();

use Sub::Exporter -setup => {
    exports => [qw(
            io_to_write_cb
            io_to_read_cb
            io_to_string
            io_to_array
            io_to_list

            io_from_any
            io_from_ref
            io_from_string
            io_from_object
            io_from_array
            io_from_scalar_ref
            io_from_thunk
            io_from_getline
            io_from_write_cb
            io_prototype

            is_real_fh
    )],
    groups => {
        io_to => [qw(
            io_to_write_cb
            io_to_read_cb
            io_to_string
            io_to_array
            io_to_list
        )],

        io_from => [qw(
            io_from_any
            io_from_ref
            io_from_string
            io_from_object
            io_from_array
            io_from_scalar_ref
            io_from_thunk
            io_from_getline
            io_from_write_cb
        )],

        coercion => [qw(
            :io_to
            :io_from
        )],

        misc => [qw(
            io_prototype
            is_real_fh
        )],
    },
};

sub io_to_write_cb ($) {
    my $fh = io_from_any(shift);

    return sub {
        local $,;
        local $\;
        $fh->print(@_) or do {
            my $e = $!;
            require autodie;
            die autodie::exception->new(
                function => q{CORE::print}, args => [@_],
                message => "\$E", errno => $e,
            );
        }
    }
}

sub io_to_read_cb ($) {
    my $fh = io_from_any(shift);

    return sub { scalar $fh->getline() };
}

sub io_to_string ($) {
    my $thing = shift;

    if ( defined $thing and not ref $thing ) {
        return $thing;
    } else {
        my $fh = io_from_any($thing);

        # list context is in case ->getline ignores $/,
        # which is likely the case with ::Iterator
        local $/;
        return join "", <$fh>;
    }
}

sub io_to_list ($) {
    my $thing = shift;

    warnings::warnif(__PACKAGE__, "io_to_list not invoked in list context")
        unless wantarray;

    if ( ref $thing eq 'ARRAY' ) {
        return @$thing;
    } else {
        my $fh = io_from_any($thing);
        return <$fh>;
    }
}

sub io_to_array ($) {
    my $thing = shift;

    if ( ref $thing eq 'ARRAY' ) {
        return $thing;
    } else {
        my $fh = io_from_any($thing);

        return [ <$fh> ];
    }
}

sub io_from_any ($) {
    my $thing = shift;

    if ( ref $thing ) {
        return io_from_ref($thing);
    } else {
        return io_from_string($thing);
    }
}

sub io_from_ref ($) {
    my $ref = shift;

    if ( Scalar::Util::blessed($ref) ) {
        return io_from_object($ref);
    } elsif ( ref $ref eq 'GLOB' and *{$ref}{IO}) {
        # once IO::Handle is required, entersub DWIMs method invoked on globs
        # there is no need to bless or IO::Wrap if there's a valid IO slot
        return $ref;
    } elsif ( ref $ref eq 'ARRAY' ) {
        return io_from_array($ref);
    } elsif ( ref $ref eq 'SCALAR' ) {
        return io_from_scalar_ref($ref);
    } elsif ( ref $ref eq 'CODE' ) {
        Carp::croak("Coercing an IO object from a coderef is ambiguous. Please use io_from_thunk, io_from_getline or io_from_write_cb directly.");
    } else {
        Carp::croak("Don't know how to make an IO from $ref");
    }
}

sub io_from_object ($) {
    my $obj = shift;

    if ( $obj->isa("IO::Handle") or $obj->can("getline") && $obj->can("print") ) {
        return $obj;
    } elsif ( $obj->isa("Path::Class::File") ) {
        return $obj->openr; # safe default or open for rw?
    } else {
        # FIXME URI? IO::File? IO::Scalar, IO::String etc? make sure they all pass
        Carp::croak("Object does not seem to be an IO::Handle lookalike");
    }
}

sub io_from_string ($) {
    my $string = shift; # make sure it's a copy, IO::String will use \$_[0]
    require IO::String;
    return IO::String->new($string);
}

sub io_from_array ($) {
    my $array = shift;

    my @array = @$array;

    require IO::Handle::Iterator;

    # IO::Lines/IO::ScalarArray is part of IO::stringy which is considered bad.
    IO::Handle::Iterator->new(sub {
        if ( @array ) {
            return shift @array;
        } else {
            return;
        }
    });
}

sub io_from_scalar_ref ($) {
    my $ref = shift;
    require IO::String;
    return IO::String->new($ref);
}

sub io_from_thunk ($) {
    my $thunk = shift;

    my @lines;

    require IO::Handle::Iterator;

    return IO::Handle::Iterator->new(sub {
        if ( $thunk ) {
            @lines = $thunk->();
            undef $thunk;
        }

        if ( @lines ) {
            return shift @lines;
        } else {
            return;
        }
    });
}

sub io_from_getline ($) {
    my $cb = shift;

    require IO::Handle::Iterator;

    return IO::Handle::Iterator->new($cb);
}

sub io_from_write_cb ($) {
    my $cb = shift;

    io_prototype( __write => sub { $cb->($_[1]) } );
}

sub io_prototype {
    require IO::Handle::Prototype::Fallback;
    IO::Handle::Prototype::Fallback->new(@_);
}

# returns true if the handle is (hopefully) suitable for passing to things that
# want to do non method operations on it, including operations that need a
# proper file descriptor
sub is_real_fh ($) {
    my $fh = shift;

    my $reftype = Scalar::Util::reftype($fh);

    if (   $reftype eq 'IO'
        or $reftype eq 'GLOB' && *{$fh}{IO}
    ) {
        # if it's a blessed glob make sure to not break encapsulation with
        # fileno($fh) (e.g. if you are filtering output then file descriptor
        # based operations might no longer be valid).
        # then ensure that the fileno *opcode* agrees too, that there is a
        # valid IO object inside $fh either directly or indirectly and that it
        # corresponds to a real file descriptor.

        my $m_fileno = $fh->fileno;

        return '' unless defined $m_fileno;
        return '' unless $m_fileno >= 0;

        my $f_fileno = fileno($fh);

        return '' unless defined $f_fileno;
        return '' unless $f_fileno >= 0;

        return 1;
    } else {
        # anything else, including GLOBS without IO (even if they are blessed)
        # and non GLOB objects that look like filehandle objects cannot have a
        # valid file descriptor in fileno($fh) context so may break.
        return '';
    }
}

__PACKAGE__

# ex: set sw=4 et:

__END__
