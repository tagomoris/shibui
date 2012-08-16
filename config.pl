+{
    # application server listen address/port
    host => '127.0.0.1',
    port => '5127',
    front_proxy => [],
    allow_from => [],

    # MySQL DSN and username/password
    dsn => 'dbi:mysql:shibui;hostname=127.0.0.1',
    db_username => 'root',
    db_password => '',

    # Hive Frontend shib host
    shib => {
        host => 'shib.host.local',
        support_huahin => 1,
    },
    # HRForecast hostname
    hrforecast => {
        host => 'hrforecast.host.local',
    },
    # Custom views
    views => {
        # index => 'index.tx',
        # docs => 'docs.tx',
    },
};

