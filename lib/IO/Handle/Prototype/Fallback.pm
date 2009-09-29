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
sub __read  { shift->_cb(__read => @_)  }

sub _process_callbacks {
    my ( $class, %user_cb ) = @_;

    if ( keys %user_cb == 1 ) {
        # these callbacks require wrapping of the user's callback to add
        # buffering, so we short circuit the entire process
        foreach my $fallback (qw(__read read getline)) {
            if ( my $cb = $user_cb{$fallback} ) {
                my $method = "_default_${fallback}_callbacks";

                return $class->_process_callbacks(
                    $class->$method($cb),
                );
            }
        }
    }

    my @fallbacks = $class->_base_callbacks;

    # additional fallbacks based on explicitly provided callbacks

    foreach my $fallback (qw(__write print write syswrite)) {
        if ( exists $user_cb{$fallback} ) {
            push @fallbacks, $class->_default_write_callbacks($fallback);
            last;
        }
    }

    if ( exists $user_cb{getline} ) {
        push @fallbacks, $class->_simple_getline_callbacks;
    }

    if ( exists $user_cb{read} ) {
        push @fallbacks, $class->_simple_read_callbacks;
    }

    # merge everything
    my %cb = (
        @fallbacks,
        %user_cb,
    );

    return \%cb;
}

sub _base_callbacks {
    my $class = shift;

    return (
        fileno => sub { undef },
        stat => sub { undef },
        opened => sub { 1 },
        blocking => sub {
            my ( $self, @args ) = @_;

            Carp::croak("Can't set blocking mode on iterator") if @args;

            return 1;
        },
    );
}

sub _make_read_callbacks {
    my ( $class, $read ) = @_;

    no warnings 'uninitialized';

    return (
        # these fallbacks must wrap the underlying reading mechanism
        __read => sub {
            my $self = shift;
            if ( exists $self->{buf} ) {
                return delete $self->{buf};
            } else {
                my $ret = $self->$read;

                unless ( defined $ret ) {
                    $self->{eof}++;
                }

                return $ret;
            }
        },
        getline => sub {
            my $self = shift;

            return undef if $self->{eof};

            if ( ref $/ ) {
                $self->read(my $ret, ${$/});
                return $ret;
            } elsif ( defined $/ ) {
                getline: {
                    if ( defined $self->{buf} and (my $off = index($self->{buf}, $/)) > -1 ) {
                        return substr($self->{buf}, 0, $off + length($/), '');
                    } else {
                        if ( defined( my $chunk = $self->$read ) ) {
                            $self->{buf} .= $chunk;
                            redo getline;
                        } else {
                            $self->{eof}++;

                            if ( length( my $buf = delete $self->{buf} ) ) {
                                return $buf;
                            } else {
                                return undef;
                            }
                        }
                    }
                }
            } else {
                my $ret = delete $self->{buf};

                while ( defined( my $chunk = $self->$read ) ) {
                    $ret .= $chunk;
                }

                $self->{eof}++;

                return $ret;
            }
        },
        read => sub {
            my ( $self, undef, $length, $offset ) = @_;

            if ( $offset and length($_[1]) < $offset ) {
                $_[1] .= "\0" x ( $offset - length($_[1]) );
            }

            while (length($self->{buf}) < $length) {
                if ( defined(my $next = $self->$read) ) {
                    $self->{buf} .= $next;
                } else {
                    # data ended but still under $length, return all that remains and
                    # empty the buffer
                    my $ret = length($self->{buf});

                    if ( $offset ) {
                        substr($_[1], $offset) = delete $self->{buf};
                    } else {
                        $_[1] = delete $self->{buf};
                    }

                    $self->{eof}++;
                    return $ret;
                }
            }

            my $read;
            if ( $length > length($self->{buf}) ) {
                $read = delete $self->{buf};
                $length = length($read);
            } else {
                $read = substr($self->{buf}, 0, $length, '');
            }

            if ( $offset ) {
                substr($_[1], $offset) = $read;
            } else {
                $_[1] = $read;
            }

            return $length;
        },
        eof => sub {
            my $self = shift;
            $self->{eof};
        },
        ungetc => sub {
            my ( $self, $ord ) = @_;

            substr( $self->{buf}, 0, 0, chr($ord) );

            return;
        },
    );
}

sub _default___read_callbacks {
    my ( $class, $read ) = @_;

    $class->_make_read_callbacks($read);
}

sub _default_read_callbacks {
    my ( $class, $read ) = @_;

    $class->_make_read_callbacks(sub {
        my $self = shift;

        if ( $self->$read(my $buf, ref $/ ? ${ $/ } : 4096) ) {
            return $buf;
        } else {
            return undef;
        }
    });
}

sub _default_getline_callbacks {
    my ( $class, $getline ) = @_;

    $class->_make_read_callbacks(sub {
        local $/ = ref $/ ? $/ : \4096;
        $_[0]->$getline;
    });
}

sub _simple_read_callbacks {
    my $class = shift;

    return (
        # these are generic fallbacks defined in terms of the wrapping ones
        sysread => sub {
            shift->read(@_);
        },
        getc => sub {
            my $self = shift;

            if ( $self->read(my $str, 1) ) {
                return $str;
            } else {
                return undef;
            }
        },
    );
}

sub _simple_getline_callbacks {
    my $class = shift;

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

