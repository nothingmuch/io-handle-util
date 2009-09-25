package IO::Handle::Prototype::Fallback;

use strict;
use warnings;

use Carp ();

use parent qw(IO::Handle::Prototype);

sub new {
    my ( $class, @args ) = @_;

    $class->SUPER::new(
        $class->_process_callbacks(@args),
    );
}

sub __write { shift->_cb(__write => @_) }

sub _process_callbacks {
    my ( $class, %user_cb ) = @_;

    my %cb = ( $class->_base_callbacks );

    foreach my $fallback (qw(__write print write syswrite)) {
        if ( exists $user_cb{$fallback} ) {
            %cb = (
                %cb,
                $class->_default_write_callbacks($fallback),
                %user_cb,
            );
            last;
        }
    }

    # these are a little more complicated, they need to wrap the user's
    # callbacks due to buffering
    foreach my $fallback (qw(read getline)) {
        if ( exists $user_cb{$fallback} ) {
            my $method = "_default_${fallback}_fallbacks";
            %cb = (
                %cb,
                $class->$method(\%user_cb),
            );
        }
    }

    return \%cb;
}

sub _base_callbacks {
    my $class = shift;

    return (
        opened => sub { 1 },
        blocking => sub {
            my ( $self, @args ) = @_;

            Carp::croak("Can't set blocking mode on iterator") if @args;

            return 1;
        },
    );
}

# these need to mix in buffering
sub _default_getline_callbacks {
    #wrap getline
    # add buffering support
    # add eof

    return (
        getlines => sub {
            my $self = shift;

            my @accum;

            while ( defined(my $next = $self->getline) ) {
                push @accum, $next;
            }

            return @accum;
        }
    );
}

sub _default_read_callbacks {
    # wrap read
    # add buffering with useful ungetc equiv
    return (
        getc => sub {
            shift->read(my $c, 1);
            return $c;
        },
    );
}

sub _default_write_callbacks {
    my ( $class, $canonical ) = @_;

    return (
        autoflush => sub { 1 },
        sync      => sub { },
        flush     => sub { },

        # these are defined in terms of a canonical print method, either write,
        # syswrite or print
        __write => sub {
            my ( $self, $str ) = @_;
            local $\;
            local $,;
            $self->$canonical($str);
        },
        print => sub {
            my $self = shift;
            my $ofs = defined $, ? $, : '';
            my $ors = defined $\ ? $\ : '';
            $self->__write( join($ofs, @_) . $ors );
        },

        (map { $_ => sub {
            my ( $self, $str, $len, $offset ) = @_;
            $len = length($str) unless defined $len;
            $offset ||= 0;
            $self->__write(substr($str, $offset, $len));
        } } qw(write syswrite)),

        # wrappers for print
        printf => sub {
            my ( $self, $f, @args ) = @_;
            $self->print(sprintf $f, @args);
        },
        say => sub {
            local $\ = "\n";
            shift->print(@_);
        },
        printflush => sub {
            my $self = shift;
            my $autoflush = $self->autoflush;
            my $ret = $self->print(@_);
            $self->autoflush($autoflush);
            return $ret;
        }
    );
}

__PACKAGE__

# ex: set sw=4 et:

__END__

