use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'Shib::ShibUI',
    VERSION_FROM  => 'lib/Shib/ShibUI.pm',
    PREREQ_PM     => {
        'Plack::Builder::Conditionals' => 0,
        'Plack::Middleware::Scope::Container' => 0,
        'Plack::Handler::Starlet' => 0,
        'Kossy' =>  '0.06',
        'URI' => 0,
        'Log::Minimal' => 0,
        'Try::Tiny' => 0,
        'JSON::XS' => 0,
        'Time::Piece' => 0,
        'Time::Seconds' => 0,
        'Time::Piece::MySQL' => 0,
        'DBI' => 0,
        'DBD::mysql' => 0,
        'DBIx::Sunny' => 0,
        'Scope::Container::DBI' => 0,
        'Furl' => 0,
        'HTTP::Request::Common' => 0,
        'Data::SExpression' => 0,
        # Net::Hadoop::Hive::QueryBuilder
        # http://github.com/tagomoris/Net-Hadoop-Hive-QueryBuilder
    },
    MIN_PERL_VERSION => '5.014001'
);
