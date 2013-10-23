package Shib::ShibUI::Web;

use 5.014;
use utf8;

use Kossy;
use URI;
use Log::Minimal;

use JSON::XS qw//;
use Furl;

use Shib::ShibUI::Data;
use Shib::ShibUI::HRForecastUtil;
use Shib::ShibUI::ShibUtil;
use Shib::ShibUI::QueryUtil;

use Time::Piece;
use Time::Seconds;

use Try::Tiny;

use Data::Dumper;

sub shib {
    Shib::ShibUI->config->{shib};
}

sub custom_view {
    my $view = shift;
    Shib::ShibUI->config->{views}->{$view};
}

sub data {
    my $self = shift;
    $self->{__data} ||= Shib::ShibUI::Data->new();
    $self->{__data};
}

sub mark {
    my ($self, $username, $query_id) = @_;
    $self->data->add_readers($username, $query_id);
}

use Net::Hadoop::Hive::QueryBuilder;
sub query_builder {
    Net::Hadoop::Hive::QueryBuilder->new(
        plugins => [
            {type => 's', name => 'and_toplevel', proc => \&Shib::ShibUI::QueryUtil::and_toplevel},
            {type => 'f', name => 'parse_agent', proc => \&Shib::ShibUI::QueryUtil::udf_parse_agent},
            {type => 'f', name => 'is_in', proc => \&Shib::ShibUI::QueryUtil::udf_is_in},
            {type => 'f', name => 'is_pc', proc => \&Shib::ShibUI::QueryUtil::udf_is_pc},
            {type => 'f', name => 'is_smartphone', proc => \&Shib::ShibUI::QueryUtil::udf_is_smartphone},
            {type => 'f', name => 'is_mobilephone', proc => \&Shib::ShibUI::QueryUtil::udf_is_mobilephone},
            {type => 'f', name => 'is_appliance', proc => \&Shib::ShibUI::QueryUtil::udf_is_appliance},
            {type => 'f', name => 'is_misc', proc => \&Shib::ShibUI::QueryUtil::udf_is_misc},
            {type => 'f', name => 'is_crawler', proc => \&Shib::ShibUI::QueryUtil::udf_is_crawler},
            {type => 'f', name => 'is_unknown', proc => \&Shib::ShibUI::QueryUtil::udf_is_unknown},
            # {type => 'f', name => 'hoge', proc => sub {}},
        ]
    );
}

filter 'title_sidebar' => sub {
    my $app = shift;
    sub {
        my ($self, $c) = @_;
        $c->stash->{site_name} = 'ShibUI';
        $c->stash->{sidebar} = {
            view => {name => '結果データ', path => 'views', items => []},
            query => {name => 'クエリ', path => 'queries', items => []},
        };
        foreach my $s (@{$self->data->service_list}) {
            push $c->stash->{sidebar}->{view}->{items}, +{service => $s};
            push $c->stash->{sidebar}->{query}->{items}, +{service => $s};
        }
        $app->($self,$c);
    }
};

filter 'oneshots_sidebar' => sub {
    my $app = shift;
    sub {
        my ($self, $c) = @_;
        $c->stash->{site_name} = 'ShibUI';
        $c->stash->{sidebar} = {
            oneshot_users => {name => '自分の履歴 (max 10)', items => $self->data->recent_oneshots($c->stash->{username})},
            oneshot_all => {name => '全体の履歴 (max 20)', items => $self->data->recent_oneshots()},
        };
        $app->($self,$c);
    }
};

filter 'user' => sub {
    my $app = shift;
    sub {
        my ($self, $c) = @_;
        my $username = $c->req->header('X-Forwarded-User');
        if (not $username and $ENV{PLACK_ENV} ne 'production') {
            $username = 'dareka';
        }
        warnf "missing header X-Forwarded-User" unless $username;
        $c->halt(403) unless $username;
        $c->stash->{username} = $username;
        $app->($self, $c);
    }
};

filter 'urls' => sub {
    my $app = shift;
    sub {
        my ($self, $c) = @_;
        $c->stash->{urls} = {};
        $c->stash->{urls}->{shib} = 'http://' . Shib::ShibUI->config->{shib}->{host};
        $c->stash->{urls}->{hrforecast} = 'http://' . Shib::ShibUI->config->{hrforecast}->{host};
        $app->($self, $c);
    }
};

sub set_sidebar_active {
    my ($sidebar, $type, $value) = @_;
    if ($type eq 'view' or $type eq 'query') {
        my $items = $sidebar->{$type}->{items};
        foreach my $item (@$items) {
            next if $item->{service} ne $value;
            $item->{active} = 1;
        }
    }
    elsif ($type eq 'oneshot') {
        foreach my $item (@{$sidebar->{oneshot_users}->{items}}, @{$sidebar->{oneshot_all}->{items}}) {
            next if $item->{id} != $value;
            $item->{active} = 1;
        }
    }
}

get '/' => [qw/user title_sidebar urls/] => sub {
    my ($self, $c) = @_;
    $c->render(custom_view('index') || 'index.tx');
};

get '/docs' => [qw/user title_sidebar urls/] => sub {
    my ($self, $c) = @_;
    $c->render(custom_view('docs') || 'docs.tx');
};

get '/register' => [qw/user title_sidebar urls/] => sub {
    my ($self, $c) = @_;
    my $service_name = '';
    if ($c->req->param('s')) {
        $service_name = $c->req->param('s');
    }
    $c->render('register.tx', {service_name => $service_name});
};

post '/register' => [qw/user/] => sub {
    my ($self, $c) = @_;
    my $service = $c->req->param('service');
    my $query = $c->req->param('query');
    my $result = $c->req->validator([
        'service' => {
            'rule' => [
                ['NOT_NULL', 'サービス名がありません'],
            ],
        },
        'query' => {
            'rule' => [
                ['NOT_NULL', 'クエリが入力されていません'],
            ],
        }
    ]);
    if ($result->has_error) {
        my $res = $c->render_json({
            error => JSON::XS::true,
            messages => $result->errors
        });
        return $res;
    }

    my $inserted_id = $self->data->register_query(
        $c->stash->{username},
        $service,
        $query,
    );
    $c->render_json({
        error => 0,
        location => $c->req->uri_for('/query/' . $inserted_id)->as_string,
    });
};

get '/query_builder' => [qw/user title_sidebar oneshots_sidebar urls/] => sub {
    my ($self, $c) = @_;
    $c->render('query_builder.tx', {saved => 0});
};

post '/query_builder/build' => [qw/user oneshots_sidebar/] => sub {
    my ($self, $c) = @_;

    my $sexpression = Shib::ShibUI::QueryUtil::build_sexpression($c->req->body_parameters);
    my $builder = query_builder();
    my $hql = $builder->dump($sexpression);
    return $c->render_json({error => JSON::XS::true, message => $builder->{error}}) unless $hql;
    $c->render_json({
        error => 0,
        query => $hql,
    });
};

post '/query_builder/kill/:id' => [qw/user/] => sub {
    my ($self, $c) = @_;
    my $furl = Furl->new(agent => 'Furl Shib::ShibUI::Web (perl)', timeout => 30);

    my $oneshot = $self->data->oneshot($c->args->{id});

    unless ($oneshot->{status} eq 'waiting' and $self->shib->{support_huahin}) {
        return $c->render_json({error => JSON::XS::true, message => "HuahinManagerを有効にしてください"});
    }
    my $ret = Shib::ShibUI::ShibUtil::kill_job($furl, $oneshot->{shib_query_id});
    $c->render_json({
        error => (not $ret),
        location => $c->req->uri_for('/query_builder/show/' . $oneshot->{id})->as_string
    });
};

post '/query_builder/run' => [qw/user oneshots_sidebar/] => sub {
    my ($self, $c) = @_;
    my $result = $c->req->validator([
        query => { rule => [ ['NOT_NULL', 'クエリがありません'], ], },
        form =>  { rule => [ ['NOT_NULL', 'フォーム入力がありません'], ], },
        offset => { rule => [ [sub{$_[1] =~ m!^\d*$!}, '日数を数値で指定してください'], ], },
    ]);
    if ($result->has_error) {
        my $message = join("\n", values(%{$result->errors}));
        return $c->render_json({ error => JSON::XS::true, message => $message });
    }

    my $offset = $c->req->param('offset') || 0;

    my $query_string = $c->req->param('query');

    # transcode from 'x=v1&y=v2&...' to json over Hash::MultiValue
    my %form_items_params = URI->new('/?' . $c->req->param('form'))->canonical->query_form;
    my $form_items = {};
    foreach my $key (keys %form_items_params) {
        $form_items->{$key} = $form_items_params{$key};
    }
    my $form_items_json = JSON::XS::encode_json($form_items);

    use Shib::ShibUI::RunQuery;
    my $err = undef;
    my $shib_query_id;
    try {
        $shib_query_id = Shib::ShibUI::RunQuery->execute_oneshot($query_string, $offset);
    } catch {
        $err = $_;
    };
    return $c->render_json({error => JSON::XS::true, message => $err}) if $err;

    my $oneshot_id = $self->data->add_oneshot(
        $c->stash->{username},
        $query_string, $form_items_json, $shib_query_id, $offset
    );
    $c->render_json({
        error => 0,
        location => '/query_builder/show/' . $oneshot_id
    });
};

get '/query_builder/show/:id' => [qw/user oneshots_sidebar urls/] => sub {
    my ($self, $c) = @_;

    my $furl = Furl->new(agent => 'Furl Shib::ShibUI::Web (perl)', timeout => 30);

    my $oneshot = $self->data->oneshot($c->args->{id});
    my $killable = 0;
    if ($oneshot->{status} eq 'waiting' and $self->shib->{support_huahin}) {
        # set $oneshot->{progress}
        # jobid, name, priority, state, jobSetup, status, jobCleanup,
        # trackingURL, startTime, mapComplete, reduceComplete,
        # hiveQueryId, hiveQueryString
        my $status = Shib::ShibUI::ShibUtil::status_detail($furl, $oneshot->{shib_query_id});
        if (defined $status and defined $status->{state}) {
            $oneshot->{progress} = +{
                map => $status->{mapComplete}, reduce => $status->{reduceComplete},
            };
            if ($status->{state} ne 'PREP' or $status->{state} ne 'RUNNING') {
                my $result = Shib::ShibUI::ShibUtil::get_result($furl, $oneshot->{shib_query_id});
                if (defined $result->{state} and ($result->{state} eq 'done' or $result->{state} eq 'error')) {
                    $self->data->update_oneshot(
                        $oneshot->{id},
                        $result->{state},
                        Shib::ShibUI::ShibUtil::time_from_js($result->{completed_at})->mysql_timestamp,
                    );
                    $oneshot = $self->data->oneshot($oneshot->{id});
                }
            }
        }
    }

    my $data = [];
    my $header = [];
    my $resultid = '';
    if ($oneshot->{status} eq 'done') {
        # get result data from shib
        my $result = Shib::ShibUI::ShibUtil::get_result($furl, $oneshot->{shib_query_id});
        my $resultid = $result->{resultid};
        my $tsv_data = Shib::ShibUI::ShibUtil::download_result_tsv($furl, $resultid);
        if ($tsv_data) {
            $data = [map { [split(/\t/, $_)] } split(/\n/, $tsv_data)];
            $header = shift @$data;
            pop $data if scalar($data->[-1]) < 1; # delete blank line
        }
    }

    set_sidebar_active( $c->stash->{sidebar}, 'oneshot', $oneshot->{id} );
    $c->render('oneshot.tx', {oneshot => $oneshot, header => $header, data => $data, resultid => $resultid});
};

get '/query_builder/edit/:id' => [qw/user oneshots_sidebar urls/] => sub {
    my ($self, $c) = @_;

    my $oneshot = $self->data->oneshot($c->args->{id});
    my $form_items = JSON::XS::decode_json($oneshot->{form_items});

    my @conditions = ();
    my @results = ();
    foreach my $raw_key (sort keys %$form_items) {
        next if $raw_key =~ m!^([a-z]+)(\d+)_.+$!;
        my ($key,$num) = ($raw_key =~ m!^([a-z]+)(\d+)$!);
        my $val = $form_items->{$raw_key};

        my @optional_keys = grep { $_ =~ m!^${key}${num}_.+! } keys %$form_items;
        my $optionals = {};
        if (scalar(@optional_keys) > 0) {
            foreach my $k (@optional_keys) {
                my ($optkey) = ($k =~ m!^${key}${num}_(.+)$!);
                $optionals->{$optkey} = $form_items->{$k};
            }
        }

        if (scalar(grep {$key eq $_} @Shib::ShibUI::QueryUtil::COND_KEYWORDS) > 0) {
            push @conditions, {type => $key, num => $num, val => $val, opts => $optionals};
        }
        elsif (scalar(grep {$key eq $_} @Shib::ShibUI::QueryUtil::RESULT_KEYWORDS) > 0) {
            push @results, {type => $key, num => $num, val => $val, opts => $optionals};
        }
    }

    set_sidebar_active( $c->stash->{sidebar}, 'oneshot', $oneshot->{id} );
    $c->render('query_builder.tx', {saved => 1, oneshot => $oneshot, conditions => \@conditions, results => \@results});
};

get '/register_view' => [qw/user title_sidebar urls/] => sub {
    my ($self, $c) = @_;
    my $services = $self->data->service_list;
    $c->render('register_view.tx', { services => $services });
};

post '/register_view' => [qw/user/] => sub {
    my ($self, $c) = @_;
    my $furl = Furl->new(agent => 'Furl Shib::ShibUI::Web (perl)', timeout => 30);

    my $url = $c->req->param('url');
    my ($complex, $hr_service, $hr_section, $hr_graphname) = @{Shib::ShibUI::HRForecastUtil::parse_url($url)};

    my $result = $c->req->validator([
        'service' => { 'rule' => [ ['NOT_NULL', 'サービス名が選択されていません'], ]},
        'label' => { 'rule' => [ ['NOT_NULL', 'データの説明が入力されていません'], ]},
        'url' => { 'rule' => [
            ['NOT_NULL', 'URLが入力されていません'],
            [sub{ Shib::ShibUI::HRForecastUtil::check_url($_[1]) },
             'HRForecastのURLを入力してください'],
            [sub{ not $self->data->search_view($complex,$hr_service,$hr_section,$hr_graphname) },
             'そのグラフを対象としたviewは既に登録されています'],
            [sub{ Shib::ShibUI::HRForecastUtil::related_graphs($furl, $hr_service, $hr_section, $hr_graphname, $complex); },
             '入力されたURLのデータがHRForecastから取得できません'],
        ]},
    ]);
    if ($result->has_error) {
        return $c->render_json({ error => JSON::XS::true, messages => $result->errors });
    }

    my $graphdatalist = Shib::ShibUI::HRForecastUtil::related_graphs($furl, $hr_service, $hr_section, $hr_graphname, $complex);

    my $queryids = {};
    foreach my $graphdata (@$graphdatalist) {
        my $graphs = $self->data->search_graphs(@$graphdata);
        foreach my $graph (@$graphs) {
            next if $queryids->{$graph->{query_id}};
            $queryids->{$graph->{query_id}} = 1;
        }
    }
    my $inserted_id = $self->data->add_view(
        $c->stash->{username},
        $c->req->param('service'), $c->req->param('label'), $complex,
        $hr_service, $hr_section, $hr_graphname,
    );
    foreach my $query_id (keys %$queryids) {
        $self->data->add_component($inserted_id, $query_id);
    }
    $c->render_json({
        error => 0,
        location => $c->req->uri_for('/view/' . $inserted_id)->as_string,
    });
};

get '/queries/:servicename' => [qw/user title_sidebar urls/] => sub {
    my ($self, $c) = @_;
    my $servicename = $c->args->{servicename};

    set_sidebar_active( $c->stash->{sidebar}, 'query', $servicename );
    $c->render('queries.tx', { service => $servicename, queries => $self->data->queries($servicename) });
};

get '/query/:query_id' => [qw/user title_sidebar urls/] => sub {
    my ($self, $c) = @_;
    my $query_id = $c->args->{query_id};
    my $query = $self->data->query($query_id);

    $c->halt(404) unless $query;

    my $can_run = ($query->{query} and $query->{description} and defined($query->{date_field_num}) and $query->{date_format});
    my $graphs = [];
    my $schedules = [];
    my $histories = [];
    if ($can_run) {
        $graphs = $self->data->graphs($query_id);
        $schedules = $self->data->schedules($query_id);
        $histories = $self->data->recent_histories($query_id);
    }

    set_sidebar_active( $c->stash->{sidebar}, 'query', $query->{service} );
    $c->render('query.tx', {
        query => $query,
        can_run => $can_run,
        graphs => $graphs,
        schedules => $schedules,
        histories => $histories,
    });
};

post '/update/query/:query_id' => [qw/user/] => sub {
    my ($self, $c) = @_;
    my $query_id = $c->args->{query_id};
    my $query = $self->data->query($query_id);
    $c->halt(404) unless $query;

    my $result = $c->req->validator([
        query => {
            rule => [
                ['NOT_NULL', 'クエリが入力されていません'],
            ],
        },
        description => {
            rule => [
                ['NOT_NULL', 'クエリの説明は必ず入力してください']
            ],
        },
        date_field_num => {
            rule => [
                ['NOT_NULL', '選択されていません'],
                [['CHOICE', qw/-1 0 1/], '不正な選択(バグ？)'],
            ],
        },
        date_format => {
            rule => [
                ['NOT_NULL', '日時フォーマットは必ず指定してください'],
                [sub{not($_[1] =~ m!%[^YmdH]!)}, '日付フォーマットは %Y %m %d %H のみ使用できます'],
            ],
        },
        status => {
            rule => [
                ['NOT_NULL', '選択されていません'],
                [['CHOICE', qw/0 1/], '不正な選択(バグ？)'],
            ],
        },
        silent => {
            rule => [
                ['NOT_NULL', '選択されていません'],
                [['CHOICE', qw/0 1/], '不正な選択(バグ？)'],
            ],
        },
    ]);
    if ($result->has_error) {
        my $res = $c->render_json({
            error => JSON::XS::true,
            messages => $result->errors
        });
        return $res;
    }

    #my $query_text = $c->req->param('query');
    #chomp $query_text;
    # my ($self, $username, $query_id, $query, $status, $description, $date_field_num, $date_format) = @_;
    $self->data->update_query(
        $c->stash->{username},
        $query_id,
        $c->req->param('query'), $c->req->param('status'), $c->req->param('description'),
        $c->req->param('date_field_num'), $c->req->param('date_format'),
    );
    $c->render_json({
        error => 0,
        location => $c->req->uri_for('/query/' . $query_id)->as_string,
    });
};

post '/delete/query/:query_id' => [qw/user/] => sub {
    my ($self, $c) = @_;
    my $query_id = $c->args->{query_id};
    my $query = $self->data->query($query_id);
    my $service = $query->{service};
    $c->halt(404) unless $query;

    $self->data->delete_query($query_id);
    $c->render_json({
        error => 0,
        location => $c->req->uri_for('/queries/' . $service)->as_string,
    });
};

post '/run/query/:query_id' => [qw/user/] => sub {
    my ($self, $c) = @_;
    my $query_id = $c->args->{query_id};
    my $query = $self->data->query($query_id);
    $c->halt(404) unless $query;

    my $result = $c->req->validator([
        offset => {
            rule => [
                [sub{$_[1] =~ m!^\d*$!}, '数値で指定してください'],
            ],
        },
    ]);
    my $offset = $c->req->param('offset') || 0;

    use Shib::ShibUI::RunQuery;
    my $err = undef;
    try {
        Shib::ShibUI::RunQuery->execute($query_id, 1, $offset); # spot exec
    } catch {
        $err = $_;
    };
    return $c->render_json({ error => 1, messages => [$err] }) if $err;

    $c->render_json({
        error => 0,
        location => $c->req->uri_for('/query/' . $query_id)->as_string,
    });
};

post '/add/graph/:query_id' => [qw/user/] => sub {
    my ($self, $c) = @_;
    my $query_id = $c->args->{query_id};
    my $query = $self->data->query($query_id);
    $c->halt(404) unless $query;

    my $result = $c->req->validator([
        label => {
            rule => [
                ['NOT_NULL', 'このデータの名前を入れてください']
            ],
        },
        value_field_num => {
            rule => [
                [['CHOICE', qw/0 1 2 3 4 5 6 7 8 9/], '0から9番目までのどれかのカラムを指定してください'],
            ],
        },
        hr_service => {
            rule => [
                ['NOT_NULL', 'サービス名を入力してください'],
            ],
        },
        hr_section => {
            rule => [
                ['NOT_NULL', 'セクションを入力してください'],
            ],
        },
        hr_graphname => {
            rule => [
                ['NOT_NULL', 'グラフ名を入力してください'],
            ],
        },
    ]);
    if ($result->has_error) {
        my $res = $c->render_json({
            error => JSON::XS::true,
            messages => $result->errors
        });
        return $res;
    }

    my $label = $c->req->param('label');
    my $hr_service = $c->req->param('hr_service');
    my $hr_section = $c->req->param('hr_section');
    my $hr_graphname = $c->req->param('hr_graphname');

    $self->data->add_graph(
        $c->stash->{username},
        $query_id, $label, $c->req->param('value_field_num'),
        $hr_service, $hr_section, $hr_graphname,
    );

    my $view = $self->data->search_view(0, $hr_service, $hr_section, $hr_graphname);
    my $view_id = $view ? $view->{id} : $self->data->add_view(
        $c->stash->{username},
        $query->{service}, $query->{description} . ':' . $label,  0, $hr_service, $hr_section, $hr_graphname,
    );

    unless ($self->data->check_component($view_id, $query_id)) {
        $self->data->add_component( $view_id, $query_id );
    }
    $c->render_json({
        error => 0,
        location => $c->req->uri_for('/query/' . $query_id)->as_string,
    });
};

post '/delete/graph/:graph_id' => [qw/user/] => sub {
    my ($self, $c) = @_;
    my $graph_id = $c->args->{graph_id};
    my $graph = $self->data->graph($graph_id);
    $c->halt(404) unless $graph;
    my $query_id = $graph->{query_id};

    $self->data->delete_graph($graph_id);

    $c->render_json({
        error => 0,
        location => $c->req->uri_for('/query/' . $query_id)->as_string,
    });
};

my $dow_map = { Sun => 0, Mon => 1, Tue => 2, Wed => 3, Thu => 4, Fri => 5, Sat => 6 };
my $dowjp = [ '日曜', '月曜', '火曜', '水曜', '木曜', '金曜', '土曜' ];
post '/add/schedule/:query_id' => [qw/user/] => sub {
    my ($self, $c) = @_;
    my $query_id = $c->args->{query_id};
    my $query = $self->data->query($query_id);
    $c->halt(404) unless $query;

    my $result;
    my $type = $c->req->param('schedule_type');
    my $schedule;
    my $schedule_jp;
    if ($type eq 'daily') {
        $result = $c->req->validator([
            hour => { rule => [ [['CHOICE', 0..23], '時がエラー'], ], },
            minute => { rule => [ [['CHOICE', 0..59], '分がエラー'], ], },
        ]);
        my ($hour,$min) = ($c->req->param('hour'), $c->req->param('minute'));
        $schedule = "$min $hour * * *";
        $schedule_jp = sprintf('毎日 %02d:%02d', $hour, $min);
    }
    elsif ($type eq 'weekly') {
        $result = $c->req->validator([
            dayofweek => { rule => [ [['CHOICE', qw/Sun Mon Tue Wed Thu Fri Sat/], '実行曜日を選択してください'], ], },
            hour => { rule => [ [['CHOICE', 0..23], '時がエラー'], ], },
            minute => { rule => [ [['CHOICE', 0..59], '分がエラー'], ], },
        ]);
        my ($hour,$min) = ($c->req->param('hour'), $c->req->param('minute'));
        my $dayofweek = $dow_map->{$c->req->param('dayofweek')};
        $schedule = "$min $hour * * $dayofweek";
        $schedule_jp = sprintf('毎週%s %02d:%02d', $dowjp->[$dayofweek], $hour, $min);
    }
    else {
        $result = $c->req->validator([
            dayofmonth => { rule => [ [['CHOICE', 1..28], '日付がエラー'], ], },
            hour => { rule => [ [['CHOICE', 0..23], '時がエラー'], ], },
            minute => { rule => [ [['CHOICE', 0..59], '分がエラー'], ], },
        ]);
        my ($hour,$min) = ($c->req->param('hour'), $c->req->param('minute'));
        my $dayofmonth = $c->req->param('dayofmonth');
        $schedule = "$min $hour $dayofmonth * *";
        $schedule_jp = sprintf('毎月%d日 %02d:%02d', $dayofmonth, $hour, $min);
    }
    if ($result->has_error) {
        my $res = $c->render_json({
            error => JSON::XS::true,
            messages => $result->errors
        });
        return $res;
    }

    $self->data->add_schedule($c->stash->{username}, $query_id, $schedule, $schedule_jp);
    $c->render_json({
        error => 0,
        location => $c->req->uri_for('/query/' . $query_id)->as_string,
    });
};

post '/toggle/schedule/:schedule_id' => [qw/user/] => sub {
    my ($self, $c) = @_;
    my $schedule_id = $c->args->{schedule_id};
    my $schedule = $self->data->schedule($schedule_id);
    $c->halt(404) unless $schedule;
    my $query_id = $schedule->{query_id};

    $self->data->update_schedule_status($schedule_id, ($schedule->{status} ? 0 : 1));
    $c->render_json({
        error => 0,
        location => $c->req->uri_for('/query/' . $query_id)->as_string,
    });
};

post '/delete/schedule/:schedule_id' => [qw/user/] => sub {
    my ($self, $c) = @_;
    my $schedule_id = $c->args->{schedule_id};
    my $schedule = $self->data->schedule($schedule_id);
    $c->halt(404) unless $schedule;
    my $query_id = $schedule->{query_id};

    $self->data->delete_schedule($schedule_id);
    $c->render_json({
        error => 0,
        location => $c->req->uri_for('/query/' . $query_id)->as_string,
    });
};

get '/views/:servicename' => [qw/user title_sidebar urls/] => sub {
    my ($self, $c) = @_;
    my $servicename = $c->args->{servicename};

    set_sidebar_active( $c->stash->{sidebar}, 'view', $servicename );
    my $views = $self->data->views($servicename);
    foreach my $view (@$views) {
        $view->{iframe_uri} = Shib::ShibUI::HRForecastUtil::iframe_url(
            $view->{hr_service}, $view->{hr_section}, $view->{hr_graphname}, $view->{complex},
        );
        $view->{graph_path} = join('/',
                                   '/view',
                                   ($view->{complex} ? 'c' : 's'),
                                   $view->{hr_service}, $view->{hr_section}, $view->{hr_graphname});
    }
    $c->render('views.tx', { service => $servicename, views => $views });
};

get '/view/:view_id' => [qw/user title_sidebar urls/] => sub {
    my ($self, $c) = @_;
    my $view_id = $c->args->{view_id};
    my $view = $self->data->view($view_id);

    $c->halt(404) unless $view;

    set_sidebar_active( $c->stash->{sidebar}, 'view', $view->{service} );

    $view->{iframe_uri} = Shib::ShibUI::HRForecastUtil::iframe_url(
        $view->{hr_service}, $view->{hr_section}, $view->{hr_graphname}, $view->{complex},
    );
    $view->{hr_uri} = Shib::ShibUI::HRForecastUtil::view_url(
        $view->{hr_service}, $view->{hr_section}, $view->{hr_graphname}, $view->{complex},
    );

    my $components = $self->data->components($view_id);
    my $queries = [];
    foreach my $comp (@$components) {
        my $query = $self->data->query($comp->{query_id});
        $query->{schedules_jp} = [map {$_->{schedule_jp}} @{$self->data->schedules($query->{id})}];
        $query->{last_executed} = $self->data->last_history($query->{id});
        push $queries, $query;
    }

    $c->render('view.tx', { view => $view, queries => $queries });
};

get '/view/:type/:service/:section/:name' => [qw/user title_sidebar urls/] => sub {
    my ($self, $c) = @_;
    my ($type,$hr_service,$hr_section,$hr_graphname) = ($c->args->{type}, $c->args->{service}, $c->args->{section}, $c->args->{name});
    my $complex = $type eq 'c' ? 1 : 0;
    my $view = $self->data->search_view($complex, $hr_service, $hr_section, $hr_graphname);

    $c->halt(404) unless $view;

    set_sidebar_active( $c->stash->{sidebar}, 'view', $view->{service} );

    $view->{iframe_uri} = Shib::ShibUI::HRForecastUtil::iframe_url(
        $view->{hr_service}, $view->{hr_section}, $view->{hr_graphname}, $view->{complex},
    );
    $view->{hr_uri} = Shib::ShibUI::HRForecastUtil::view_url(
        $view->{hr_service}, $view->{hr_section}, $view->{hr_graphname}, $view->{complex},
    );

    my $components = $self->data->components($view->{id});
    my $queries = [];
    foreach my $comp (@$components) {
        my $query = $self->data->query($comp->{query_id});
        $query->{schedules_jp} = [map {$_->{schedule_jp}} @{$self->data->schedules($query->{id})}];
        $query->{last_executed} = $self->data->last_history($query->{id});
        push $queries, $query;
    }

    $c->render('view.tx', { view => $view, queries => $queries });
};

post '/delete/view/:view_id' => [qw/user/] => sub {
    my ($self, $c) = @_;
    my $view_id = $c->args->{view_id};
    my $view = $self->data->view($view_id);
    my $service = $view->{service};
    $c->halt(404) unless $view;

    $self->data->delete_view($view_id);
    $c->render_json({
        error => 0,
        location => $c->req->uri_for('/views/' . $service)->as_string,
    });
};

get '/resultview/:query_id/:history_id' => [qw/user title_sidebar urls/] => sub {
    my ($self, $c) = @_;
    my $query_id = $c->args->{query_id};
    my $history_id = $c->args->{history_id};
    my $query = $self->data->query($query_id);
    my $history = $self->data->history($history_id);

    $c->halt(404) unless $query and $history;

    set_sidebar_active( $c->stash->{sidebar}, 'query', $query->{service} );

    my $furl = Furl->new(agent => 'Furl Shib::ShibUI::Web (perl)', timeout => 30);
    my $result = Shib::ShibUI::ShibUtil::get_result($furl, $history->{shib_query_id});
    my $tsv_data = Shib::ShibUI::ShibUtil::download_result_tsv($furl, $result->{resultid});

    my $header = [];
    my @data = ();
    if ($tsv_data) {
        @data = map { [split(/\t/, $_)] } split(/\n/, $tsv_data);
        $header = shift @data;
        pop @data if scalar($data[-1]) < 1; # delete blank line
    }

    # update header with graph values
    my $graphs = $self->data->graphs($query_id);
    foreach my $graph (@$graphs) {
        $header->[$graph->{value_field_num}] = $graph->{label};
    }
    $self->mark($c->stash->{username}, $query_id);
    $c->render('resultview.tx', { query => $query, history => $history, resultid => $result->{resultid},
                                  header => $header, data => \@data });
};

get '/resultdata/:query_id/:shib_query_id' => sub {
    my ($self, $c) = @_;
    my $query_id = $c->args->{query_id};
    my $shib_query_id = $c->args->{shib_query_id};

    my $query = $self->data->query($query_id);
    $c->halt(404) unless $query;
    my $history = $self->data->history_shib_id($query_id, $shib_query_id);
    $c->halt(404) unless $history;

    my $furl = Furl->new(agent => 'Furl Shib::ShibUI::Web (perl)', timeout => 30);
    my $result = Shib::ShibUI::ShibUtil::get_result($furl, $history->{shib_query_id});
    $c->redirect(Shib::ShibUI::ShibUtil::url_result_tsv($result->{resultid}));
};

get '/resultdata/:query_id' => sub {
    my ($self, $c) = @_;
    my $query_id = $c->args->{query_id};
    my $query = $self->data->query($query_id);

    $c->halt(404) unless $query;

    my $history = $self->data->last_history($query_id);

    $c->halt(404) unless $history;

    my $furl = Furl->new(agent => 'Furl Shib::ShibUI::Web (perl)', timeout => 30);
    my $result = Shib::ShibUI::ShibUtil::get_result($furl, $history->{shib_query_id});
    $c->redirect(Shib::ShibUI::ShibUtil::url_result_tsv($result->{resultid}));
};

get '/schedules' => sub {
    my ($self, $c) = @_;
    my $this_month = scalar(localtime)->strftime('%Y%m');
    $c->redirect('/schedules/' . $this_month);
};

sub schedule_build {
    my $schedule_list = shift;
    foreach my $s (@$schedule_list) {
        my ($m, $h, $d, undef, $wd) = split(/ /, $s->{schedule});
        $s->{sched_data} = {wd => $wd, d => $d, h => $h, m => $m, t => sprintf('%02d:%02d', $h, $m)};
    }
    return [sort { $a->{sched_data}->{t} <=> $b->{sched_data}->{t} } @$schedule_list];
}

get '/schedules/:month' => [qw/user title_sidebar urls/] => sub {
    my ($self, $c) = @_;
    $c->halt(500) unless $c->args->{month} =~ m!^20\d\d\d\d$!;
    my $target = Time::Piece->strptime($c->args->{month}, '%Y%m');
    my $prev_month = $target - ONE_DAY;
    my $next_month = $target + (32* ONE_DAY);
    my $show = {
        month_disp => $target->strftime('%Y/%m'),
        prev => $prev_month->strftime('%Y%m'),
        prev_disp => $prev_month->strftime('%Y/%m'),
        next => $next_month->strftime('%Y%m'),
        next_disp => $next_month->strftime('%Y/%m'),
    };

    #'SELECT id,query_id,status,schedule,schedule_jp,created_at,created_by FROM schedules WHERE status=1 ORDER BY id'
    # schedule: '0 10 * * *'
    my $schedules = schedule_build($self->data->valid_schedules);
    my $hhmm = sub { my ($m,$h) = split(/ /, shift); return sprintf('%02d%02d',$h,$m); };
    {
        no warnings 'once';
        $schedules = [sort { $hhmm->($a->{schedule}) <=> $hhmm->($b->{schedule}) } @$schedules];
    }
    my %dummy_queries;
    @dummy_queries{ map { $_->{query_id} } @$schedules } = ();
    my $query_id_list = [keys %dummy_queries];

    #SELECT id,service,status,query,created_at,created_by,modified_at,modified_by,description,date_field_num,date_format
    my $queries = $self->data->query_list($query_id_list);
    my %query_map;
    foreach my $query (@$queries) {
        $query_map{$query->{id}} = $query;
    }

    #SELECT id,query_id,shib_query_id,status,started_at,completed_at,elapse
    my $histories = $self->data->history_list($query_id_list);
    my %history_map;
    foreach my $history (@$histories) {
        $history_map{$history->{query_id}} = $history;
    }

    my $schedule_rows = [];
    for(my $iter = Time::Piece->new($target) ; $iter->mon eq $target->mon ; $iter += ONE_DAY) {
        push $schedule_rows, {date => $iter->mon . '/' . $iter->mday, dayofweek => lc($iter->wdayname)};
        foreach my $sched (@$schedules) {
            # check if match, and push sched tr order by hour/min
            my $matched = 0;
            my ($d, $wd) = ($sched->{sched_data}->{d}, $sched->{sched_data}->{wd});
            $matched = 1 if $d eq '*' and $wd eq '*';
            $matched = 1 if $d ne '*' and $wd eq '*' and $d == $iter->mday;
            $matched = 1 if $d eq '*' and $wd ne '*' and $wd == $iter->_wday;
            next unless $matched;

            my $queryid = $sched->{query_id};

            next unless $query_map{$queryid}->{status};

            push $schedule_rows, +{
                queryid => $queryid,
                time => $sched->{sched_data}->{t},
                description => $query_map{$queryid}->{description},
                schedule => $sched->{schedule_jp},
                elapse => $history_map{$queryid}->{elapse}
            };
        }
    }
    $c->render('schedules.tx', { show => $show, schedules => $schedule_rows });
};

1;
