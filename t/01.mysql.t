use t::Utils;
use Test::More;
use Uc::Model::Twitter;

BEGIN {
    eval "use DBD::mysql";
    plan skip_all => 'needs DBD::mysql for testing' if $@;
}

our $dbh = eval {t::Utils->setup_mysql_dbh()};
if ($@) {
    plan skip_all => 'needs ALL PRIVILEGES ON test.* for testing';
}
else {
    plan tests => 5;
}

our $class;
subtest "connect" => sub {
    plan tests => 1;

    $class = Uc::Model::Twitter->new( dbh => $dbh );

    isa_ok $class, 'Uc::Model::Twitter';
};

subtest "create and drop tables" => sub {
    plan tests => 2;
    my $sth;
    my $needs = [qw/profile_image remark status user/];

    $class->create_table();

    $sth = $class->execute(q{SHOW TABLES});
    my $got = [sort grep { $_ ~~ $needs } map { $_->[0] } @{$sth->fetchall_arrayref}];
    is_deeply $got, $needs, 'checking 4 tables are created';

    $class->drop_table();

    $sth = $class->execute(q{SHOW TABLES});
    ok ! scalar @{$sth->fetchall_arrayref};
};


$class->create_table();


subtest "find_or_create_profile_from_user" => sub {
    plan tests => 7;

    can_ok $class, 'find_or_create';
    can_ok $class, 'find_or_create_profile_from_user';

    # get tweet
    my $status = t::Utils->open_json_file('t/show_status.20.json');

    # create
    my $user1 = $class->find_or_create_profile_from_user($status->{user});
    isa_ok $user1, 'Teng::Row';

    # find
    my $user2 = $class->find_or_create_profile_from_user($status->{user});
    isa_ok $user2, 'Teng::Row';

    # create other name profile
    $status->{user}{name} = 'Cormorant';
    my $user3 = $class->find_or_create_profile_from_user($status->{user});
    isa_ok $user3, 'Teng::Row';

    ok($user1->id == $user2->id and $user1->profile_id eq $user2->profile_id ? 1 : 0)
        or diag explain [
            { n => 1, id => $user1->id, profile_id => $user1->profile_id },
            { n => 2, id => $user2->id, profile_id => $user2->profile_id },
        ];
    ok($user1->id == $user3->id and $user1->profile_id ne $user3->profile_id ? 1 : 0)
        or diag explain [
            { n => 1, id => $user1->id, profile_id => $user1->profile_id },
            { n => 3, id => $user3->id, profile_id => $user3->profile_id },
        ];

    $class->delete('user');
};

subtest "find_or_create_status_from_tweet" => sub {
    plan tests => 12;

    can_ok $class, 'find_or_create';
    can_ok $class, 'find_or_create_status_from_tweet';

    # get tweet
    my $status1 = t::Utils->open_json_file('t/show_status.20.json');

    # create
    my $tweet1 = $class->find_or_create_status_from_tweet($status1);
    isa_ok $tweet1, 'Teng::Row';

    # find
    my $tweet2 = $class->find_or_create_status_from_tweet($status1);
    isa_ok $tweet2, 'Teng::Row';

    # single
    my $tweet3 = $class->single('status', { id => $status1->{id} });
    isa_ok $tweet3, 'Teng::Row';

    # cmp 3 results
    ok $tweet1->id eq $tweet2->id and $tweet1->id eq $tweet3->id ? 1 : 0;

    # get tweet with retweet
    my $status2 = t::Utils->open_json_file('t/show_status.243149503589400576.json');

    # create
    my $tweet4 = $class->find_or_create_status_from_tweet($status2);
    isa_ok $tweet4, 'Teng::Row';

    # find
    my $tweet5 = $class->find_or_create_status_from_tweet($status2);
    isa_ok $tweet5, 'Teng::Row';

    # single
    my $tweet6 = $class->single('status', { id => $status2->{id} });
    isa_ok $tweet6, 'Teng::Row';

    # cmp 3 results
    ok $tweet4->id eq $tweet5->id and $tweet4->id eq $tweet6->id ? 1 : 0;

    # get original tweet
    my $tweet7 = $class->single('status', { id => $tweet6->retweeted_status_id });
    isa_ok $tweet7, 'Teng::Row';

    # check relation
    ok $tweet6->retweeted_status_id eq $tweet7->id ? 1 : 0;

    $class->delete('status');
    $class->delete('user');
};

subtest "update_or_create_remark_with_retweet" => sub {
    plan tests => 19;

    can_ok $class, 'update_or_create';
    can_ok $class, 'update_or_create_remark_with_retweet';

    # get tweet with retweet
    my $status = t::Utils->open_json_file('t/show_status.243149503589400576.json');

    my $tweet = $class->find_or_create_status_from_tweet($status);
    isa_ok $tweet, 'Teng::Row';

    my %update = (
        id => $tweet->retweeted_status_id,
        user_id => $tweet->user_id,
    );

    $update{retweeted} = 1;

    my $remark1 = $class->update_or_create_remark_with_retweet(\%update);
    isa_ok $remark1, 'Teng::Row';

    ok $remark1->id == $tweet->retweeted_status_id and $remark1->user_id == $tweet->user_id ? 1 : 0;
    ok $remark1->retweeted;

    $update{retweeted} = 0;
    $update{favorited} = 1;

    my $remark2 = $class->update_or_create_remark_with_retweet(\%update);
    isa_ok $remark2, 'Teng::Row';

    ok ! $remark2->retweeted;
    ok   $remark2->favorited;

    $update{id}        = $tweet->id;
    $update{retweeted} = 1;

    my $remark3 = $class->update_or_create_remark_with_retweet(
        \%update,
        { retweeted_status => $status->{retweeted_status} }
    );
    isa_ok $remark3, 'Teng::Row';

    my $remark4 = $class->single('remark', { id => $tweet->retweeted_status_id });
    isa_ok $remark4, 'Teng::Row';

    ok $remark3->retweeted;
    ok $remark4->retweeted;

    $update{retweeted} = 0;
    $update{favorited} = 1;

    my $remark5 = $class->update_or_create_remark_with_retweet(\%update);
    isa_ok $remark5, 'Teng::Row';

    my $remark6 = $class->single('remark', { id => $tweet->retweeted_status_id });
    isa_ok $remark6, 'Teng::Row';

    is $remark5->retweeted, $update{retweeted};
    is $remark6->favorited, $update{favorited};
    cmp_ok $remark5->retweeted, '==', $remark6->retweeted;
    cmp_ok $remark5->favorited, '==', $remark6->favorited;

    $class->delete('remark');
    $class->delete('status');
    $class->delete('user');
};

$class->drop_table();


done_testing;