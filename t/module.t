use Test2::V0;
use Daemon::Device;

my $my_process = $$;
my $my_log     = 'daemon_device_test_' . $my_process . '.log';

my @module_params = (
    daemon => {
        name        => 'daemon_device_test',
        pid_file    => 'daemon_device_test_' . $my_process . '.pid',
        stderr_file => $my_log,
        stdout_file => $my_log,
        quiet       => 1,
    },

    spawn => 3,

    parent => sub {
        my ($device) = @_;
        warn "PARENT $$ start\n";
        sleep 1 while (1);
    },

    child => sub {
        my ($device) = @_;
        warn "CHILD $$ start\n";
        while (1) {
            exit unless ( $device->parent_alive );
            sleep 1;
        }
    },

    on_startup       => sub { warn "EVENT $$ on_startup\n"       },
    on_shutdown      => sub { warn "EVENT $$ on_shutdown\n"      },
    on_spawn         => sub { warn "EVENT $$ on_spawn\n"         },
    on_parent_hup    => sub { warn "EVENT $$ on_parent_hup\n"    },
    on_child_hup     => sub { warn "EVENT $$ on_child_hup\n"     },
    on_parent_death  => sub { warn "EVENT $$ on_parent_death\n"  },
    on_child_death   => sub { warn "EVENT $$ on_child_death\n"   },
    on_replace_child => sub { warn "EVENT $$ on_replace_child\n" },
);

my $obj;
ok( $obj = Daemon::Device->new(@module_params), 'Daemon::Device->new()' );
is( ref $obj, 'Daemon::Device', 'ref $object' );

$obj->{_daemon}->do_start;

sub get_log_file {
    open( my $log_file, '<', $my_log );
    my @log_file = map { chomp; $_ } <$log_file>;
    close($log_file);
    return \@log_file;
}

my $good = 0;
for ( 1 .. 10 ) {
    sleep 1;
    my $log_file = &get_log_file;
    if (
        scalar( grep { $_ =~ /PARENT \d+ start/ } @$log_file ) and
        scalar( grep { $_ =~ /CHILD \d+ start/ } @$log_file ) == 3
    ) {
        $good = 1;
        last;
    }
}
ok( $good, 'Parent and 3 (and no more) children started in under 10 seconds' );

my @pids = map { /(\d+)/; $1 } grep { $_ =~ /CHILD \d+ start/ } @{&get_log_file};

kill( 'TERM', shift @pids );
kill( 'KILL', pop @pids );

$good = 0;
for ( 1 .. 10 ) {
    sleep 1;
    my $log_file = &get_log_file;
    if ( scalar( grep { $_ =~ /on_replace_child/ } @$log_file ) == 2 ) {
        $good = 1;
        last;
    }
}
ok( $good, '2 children were appropriately replaced in under 10 seconds' );

$obj->{_daemon}->do_stop;

$good = 0;
for ( 1 .. 10 ) {
    sleep 1;
    my $log_file = &get_log_file;
    if (
        scalar( grep { $_ =~ /on_shutdown/ } @$log_file ) == 1 and
        scalar( grep { $_ =~ /on_child_death/ } @$log_file ) == 4
    ) {
        $good = 1;
        last;
    }
}
ok( $good, 'Shutdown properly took place in under 10 seconds' );

is(
    { map { s/\d+/D/; $_ => 1 } @{ &get_log_file } },
    {
        'CHILD D start'            => 1,
        'EVENT D on_child_death'   => 1,
        'EVENT D on_parent_death'  => 1,
        'EVENT D on_replace_child' => 1,
        'EVENT D on_shutdown'      => 1,
        'EVENT D on_spawn'         => 1,
        'EVENT D on_startup'       => 1,
        'PARENT D start'           => 1,
    },
    'Event actions appear to have all been conducted (and no extra actions)',
);

$obj->{_daemon}->do_stop;

unlink $my_log;
done_testing;
