# ABSTRACT: YAML-file-based session backend for Dancer

package Dancer::Session::YAML;
use Moo;
use Dancer::Core::Types;
use Carp;
use Fcntl ':flock';
use Dancer::FileUtils qw(path set_file_mode);

with 'Dancer::Core::Role::Session';

=head1 DESCRIPTION

This module implements a session engine based on YAML files. Session are stored
in a I<session_dir> as YAML files. The idea behind this module was to provide a
transparent session storage for the developer.

This backend is intended to be used in development environments, when looking
inside a session can be useful.

It's not recommended to use this session engine in production environments.

=head1 CONFIGURATION

The setting B<session> should be set to C<YAML> in order to use this session
engine in a Dancer application.

Files will be stored to the value of the setting C<session_dir>, whose default
value is C<appdir/sessions>.

Here is an example configuration that use this session engine and stores session
files in /tmp/dancer-sessions

    session: "YAML"
    session_dir: "/tmp/dancer-sessions"

=method new Dancer::Session::YAML(%attributes);

=attr session_dir

=cut

# needed for new session when they get created
# FIXME this won't be needed anymore when we split the design in two:
# a Session class for session objects
# a SessionFactory for handling session (the session_dir belongs here)
my $_last_session_dir_used;

my %_session_dir_initialized;
has session_dir => (
    is => 'ro',
    isa => Str,
    default => sub { $_last_session_dir_used },
    trigger => sub {
        my ($self, $session_dir) = @_;

        if (! exists $_session_dir_initialized{$session_dir}) {
            $_session_dir_initialized{$session_dir} = 1;
            if (!-d $session_dir) {
                mkdir $session_dir
                  or croak "session_dir $session_dir cannot be created";
            }
        }

        $_last_session_dir_used = $session_dir;
    },
);

# static

sub BUILD {
    my $self = shift;

    eval "use YAML::Any";
    croak "YAML::Any is needed and is not installed: $@" if $@;
}

# create a new session and return the newborn object
# representing that session

=method create

Synonym for new

=cut
sub create { goto &new }

=method reset();

to avoid checking if the sessions directory exists everytime a new session is
created, this module maintains a cache of session directories it has already
created. C<reset> wipes this cache out, forcing a test for existence
of the sessions directory next time a session is created. It takes no argument.

This is particulary useful if you want to remove the sessions directory on the
system where your app is running, but you want this session engine to continue
to work without having to restart your application.
=cut

# deletes the dir cache
sub reset {
    my ($class) = @_;
    %_session_dir_initialized = ();
}

=method 

Return the session object corresponding to the given id

=cut
sub retrieve {
    my ($self, $id) = @_;
    my $session_file = $self->yaml_file($id);

    return unless -f $session_file;

    open my $fh, '+<', $session_file or die "Can't open '$session_file': $!\n";
    flock $fh, LOCK_EX or die "Can't lock file '$session_file': $!\n";
    my $new_session = YAML::Any::LoadFile($fh);
    close $fh or die "Can't close '$session_file': $!\n";

    return $new_session;
}

# instance

=method yaml_file
=cut
sub yaml_file {
    my ($self, $id) = @_;
    return path($self->session_dir, "$id.yml");
}

=method destroy
=cut
sub destroy {
    my ($self) = @_;
    unlink $self->yaml_file($self->id) if -f $self->yaml_file($self->id);
}

=method flush
=cut
sub flush {
    my $self         = shift;
    my $session_file = $self->yaml_file( $self->id );

    open my $fh, '>', $session_file or die "Can't open '$session_file': $!\n";
    flock $fh, LOCK_EX or die "Can't lock file '$session_file': $!\n";
    set_file_mode($fh);
    print {$fh} YAML::Any::Dump($self);
    close $fh or die "Can't close '$session_file': $!\n";

    return $self;
}

1;

=head1 DEPENDENCY

This module depends on L<YAML>.

=head1 SEE ALSO

See L<Dancer::Session> for details about session usage in route handlers.

=cut
