package Shib::ShibUI::QueryUtil;

use 5.014;
use utf8;
use Carp;

sub and_toplevel {
    my ($b, @args) = @_;
    join("\n  AND ", map { $b->produce_value($_) } @args);
}

sub udf_parse_agent {
    my ($b, @args) = @_;
    'parse_agent(' . $b->produce_value($args[0]) . ')';
}

sub udf_is_in {
    my ($b, @args) = @_;
    'is_in(' . join(", ", $b->produce_value($args[0]), $b->produce_value($args[1])) . ')';
}

sub udf_is_pc {
    my ($b, @args) = @_;
    'is_pc(' . $b->produce_value($args[0]) . ')';
}

sub udf_is_smartphone {
    my ($b, @args) = @_;
    'is_smartphone(' . $b->produce_value($args[0]) . ')';
}

sub udf_is_mobilephone {
    my ($b, @args) = @_;
    'is_mobilephone(' . $b->produce_value($args[0]) . ')';
}

sub udf_is_appliance {
    my ($b, @args) = @_;
    'is_appliance(' . $b->produce_value($args[0]) . ')';
}

sub udf_is_misc {
    my ($b, @args) = @_;
    'is_misc(' . $b->produce_value($args[0]) . ')';
}

sub udf_is_crawler {
    my ($b, @args) = @_;
    'is_crawler(' . $b->produce_value($args[0]) . ')';
}

sub udf_is_unknown {
    my ($b, @args) = @_;
    'is_unknown(' . $b->produce_value($args[0]) . ')';
}

our @COND_KEYWORDS = qw(
                           service date status path query referer refererhost refererpath refererquery
                           agent agenttype method virtualhost
                   );
our @RESULT_KEYWORDS = qw( rdate fields aggregates );

our %proc_map = (
    service => \&proc_service,
    date => \&proc_date,
    status => \&proc_status,
    path => \&proc_path,
    query => \&proc_query,
    referer => \&proc_referer,
    refererhost => \&proc_refererhost,
    refererpath => \&proc_refererpath,
    refererquery => \&proc_refererquery,
    agent => \&proc_agent,
    agenttype => \&proc_agenttype,
    method => \&proc_method,
    virtualhost => \&proc_virtualhost,

    rdate => \&proc_rdate,
    fields => \&proc_fields,
    aggregates => \&proc_aggregates,
);

sub tablename_and_overridden_procs { # returns tablename, and overridden %proc_map
    my $arg = shift;
    if ($arg->{'date0'} eq 'today') {
        return ('hourly_log', {%proc_map, date => \&proc_date_today, rdate => \&proc_rdate_today});
    }

    return ('access_log', \%proc_map);
}

sub build_sexpression {
    my $arg = shift;

    my ($tablename, $procs) = tablename_and_overridden_procs($arg);

    my @conds = ();
    foreach my $keyword (@COND_KEYWORDS) {
        push @conds, proc_cond($procs, $keyword, $arg);
    }
    my $where = '(where (and_toplevel ' . join(' ', @conds) . '))';

    my @fields = ();
    push @fields, proc_result($procs, 'rdate', $arg);
    push @fields, proc_result($procs, 'fields', $arg);

    my @aggregates = proc_result($procs, 'aggregates', $arg);

    my $select = '(select ' . join(' ', @fields, @aggregates) . ')';
    my $from = '(from (table ' . $tablename . '))';

    #TODO: 'order by' and 'limit'

    if (scalar(@aggregates) < 1) {
        return '(query ' . join(' ', $select, $from, $where) . ')';
    }

    my $group = '(group ' . join(' ', @fields) . ')';

    # my $order = '(order...)';
    # my $limit = '(limit...)';
    my $aggr = '(aggregate ' . $group . ')';

    my $hql = '(query ' . join(' ', $select, $from, $where, $aggr) . ')';
    $hql;
}

sub proc_cond {
    my ($procs, $keyword, $arg) = @_;
    my $params = {};
    foreach my $key (sort keys %$arg) {
        if ($key =~ m!^($keyword\d+)$!) {
            my $f = $1;
            $params->{$f} //= {};
            $params->{$f}->{value} = $arg->{$f};
        }
        elsif ($key =~ m!^(($keyword\d+)_(.+))$!) {
            my $ff = $1;
            my $f = $2;
            my $x = $3;
            $params->{$f} //= {};
            $params->{$f}->{$x} = $arg->{$ff};
        }
    }
    if (scalar(keys %$params) < 1) {
        return ();
    }
    if (scalar(keys %$params) > 1) {
        return "(or " . join(" ", map { $procs->{$keyword}->(%{$params->{$_}}) } sort keys(%$params)) . ")";
    }
    my $k = (keys(%$params))[0];
    $procs->{$keyword}->(%{$params->{$k}});
}

sub proc_result {
    my ($procs, $keyword, $arg) = @_;
    my $params = {};
    foreach my $key (sort keys %$arg) {
        if ($key =~ m!^($keyword\d+)$!) {
            my $f = $1;
            $params->{$f} //= {};
            $params->{$f}->{value} = $arg->{$f};
        }
        elsif ($key =~ m!^(($keyword\d+)_(.+))$!) {
            my $ff = $1;
            my $f = $2;
            my $x = $3;
            $params->{$f} //= {};
            $params->{$f}->{$x} = $arg->{$ff};
        }
    }
    if (scalar(keys %$params) < 1) {
        return ();
    }
    if (scalar(keys %$params) > 1) {
        return (map { $procs->{$keyword}->(%{$params->{$_}}) } sort keys(%$params));
    }
    my $k = (keys(%$params))[0];
    $procs->{$keyword}->(%{$params->{$k}});
}

sub proc_rdate {
    my %params = @_;
    my $v = $params{value};
    my $o = $params{option};
    if ($v eq 'datefield') { return "(field yyyymmdd)"; } #TODO: hourly_log ?
    elsif ($v eq 'month') { return "(substr (field yyyymmdd) (number 0) (number 6))"; }
    elsif ($v eq 'select') {
        if ($o eq 'today') { return "(string \"__TODAY__\")"; }
        if ($o eq 'today_month') { return "(string \"__MONTH__\")"; }
        if ($o eq 'yesterday') { return "(string \"__YESTERDAY__\")"; }
        if ($o eq 'yesterday_month') { return "(substr (string \"__YESTERDAY__\") (number 0) (number 6))"; }
        if ($o eq 'last_month') { return "(string \"__LASTMONTH__\")"; }
    }
    confess "invalid result date: $v($o)";
}

sub proc_rdate_today {
    my %params = @_;
    my $v = $params{value};
    my $o = $params{option};
    if ($v eq 'datefield') { return "(field yyyymmddhh)"; }
    elsif ($v eq 'month') { return "(substr (field yyyymmddhh) (number 0) (number 6))"; }
    elsif ($v eq 'select') {
        if ($o eq 'today') { return "(string \"__TODAY__\")"; }
        if ($o eq 'today_month') { return "(string \"__MONTH__\")"; }
        if ($o eq 'yesterday') { return "(string \"__YESTERDAY__\")"; }
        if ($o eq 'yesterday_month') { return "(substr (string \"__YESTERDAY__\") (number 0) (number 6))"; }
        if ($o eq 'last_month') { return "(string \"__LASTMONTH__\")"; }
    }
    confess "invalid result date: $v($o)";
}

sub proc_fields {
    my %params = @_;
    my $v = $params{value};
    my $o;
    if ($v eq 'time') {
        $o = $params{time};
        if ($o eq 'hhmmss') { return "(field hhmmss)"; }
        if ($o eq 'hhmm') { return "(substr (field hhmmss) (number 0) (number 4))"; }
        if ($o eq 'hh') { return "(substr (field hhmmss) (number 0) (number 2))"; }
        confess "invalid time option: $v($o)";
    }
    elsif ($v eq 'request') {
        $o = $params{request};
        if ($o eq 'method') { return "(field method)"; }
        if ($o eq 'full_path'){ return "(field path)"; }
        if ($o eq 'path') { return "(parse_url (concat (string \"http://x.jp\") (field path)) (string \"PATH\"))"; }
        if ($o eq 'topdir') { return "(concat (string \"/\") (array_get (split (field path) (string \"/\")) (number 1)))"; }
        if ($o eq 'vhost') { return "(field vhost)"; }
        if ($o eq 'refsite') { return "(parse_url (field referer) (string \"HOST\"))"; }
        if ($o eq 'referer') { return "(field referer)"; }
        confess "invalid request option: $v($o)";
    }
    elsif ($v eq 'response') {
        $o = $params{response};
        if ($o eq 'status') { return "(field status)"; }
        if ($o eq 'bytes') { return "(field bytes)"; }
        if ($o eq 'duration') { return "(field duration)"; }
        confess "invalid response option: $v($o)";
    }
    elsif ($v eq 'userinfo') {
        $o = $params{userinfo};
        if ($o eq 'agent') { return "(field agent)"; }
        if ($o eq 'agentcategory') { return "(map_get (parse_agent (field agent)) (string \"category\"))"; }
        if ($o eq 'agentname') { return "(map_get (parse_agent (field agent)) (string \"name\"))"; }
        if ($o eq 'agentos') { return "(map_get (parse_agent (field agent)) (string \"os\"))"; }
        if ($o eq 'rhost') { return "(field rhost)"; }
        if ($o eq 'userlabel') { return "(field userlabel)"; }
        confess "invalid userinfo option: $v($o)";
    }
    confess "invalid fields: $v";
}

sub proc_aggregates {
    my %params = @_;
    my $v = $params{value};
    my $o;
    if ($v eq 'count' or $v eq 'uucount') {
        $o = $params{count};
        if ($o eq 'lines') { return ($v eq 'count') ? "(count *)" : "(count distinct (field userlabel))"; }
        if ($o eq 'pvagents') {
            my $pvtargets = '(array_construct (string "pc") (string "smartphone") (string "mobilephone") (string "appliance"))';
            return "(count (is_in (parse_agent (field agent)) $pvtargets))";
        }
        if ($o eq 'pc' or $o eq 'smartphone' or $o eq 'mobilephone' or $o eq 'appliance' or
                $o eq 'misc' or $o eq 'misc' or $o eq 'crawler' or $o eq 'unknown') {
            return "(count (is_$o (parse_agent (field agent))))";
        }

        unless ($o eq 'path' or $o eq 'vhost' or $o eq 'referer') {
            confess "invalid count/uucount option: $v($o)";
        }

        my $c = ($v eq 'count') ? 'count' : 'count distinct';
        my $r = ($v eq 'count') ? '(true)' : '(field userlabel)';

        return "($c (if " . proc_text_field_equality("(field $o)", $params{countextmatch}, $params{countext}) . " $r (null)))";
    }

    my $c = $params{numaggr};

    if ($v eq 'sum' or $v eq 'avg' or $v eq 'min' or $v eq 'max') {
        return "($v (field $c))";
    }
    elsif ($v eq '50percentile') { return "(percentile (field $c) (number 50))"; }
    elsif ($v eq '90percentile') { return "(percentile (field $c) (number 90))"; }
    elsif ($v eq '95percentile') { return "(percentile (field $c) (number 95))"; }
    elsif ($v eq '98percentile') { return "(percentile (field $c) (number 98))"; }

    confess "invalid aggregate function specification: $v";
}

sub proc_text_field_equality {
    my ($leftside, $match, $value) = @_;
    my $op;
    if ($match eq 'equal') { $op = '='; }
    elsif ($match eq 'like') { $op = 'like'; }
    elsif ($match eq 'rlike') { $op = 'rlike'; }
    else {
        confess "invalid match: $match";
    }
    "($op $leftside (string \"$value\"))";
}

#     'service0' => 'hoge',
sub proc_service {
    my %params = @_;
    my $s = $params{value};
    "(= (field service) (string \"$s\"))";
}

#     'date0' => '1and2',
#     'date0_input' => '',
sub proc_date {
    my %params = @_;
    my $v = $params{value};
    my $part = sub {
        my $date = shift;
        "(= (field yyyymmdd) (string \"$date\"))";
    };
    if ($v eq 'yesterday') {
        return $part->("__YESTERDAY__");
    }
    elsif ($v eq '1and2') {
        return "(or " . join(" ", map { $part->($_) } ("__2DAYS_AGO__", "__1DAYS_AGO__")) . ")";
    }
    elsif ($v eq '7days') {
        return "(or " . join(" ", map { $part->("__" . $_ . "DAYS_AGO__") } (1...7)) . ")";
    }
    elsif ($v eq 'today') {
        return "(string \"today and yesterday are cannot be specified at same time\")";
    }
    elsif ($v eq 'lastmonth') {
        return "(like (field yyyymmdd) (string \"__LASTMONTH__%\"))";
    }
    elsif ($v eq 'specified') {
        return $part->($params{input});
    }
    die "invalid argument value: $v";
}

#     'date0' => '1and2',
#     'date0_hour' => '',
sub proc_date_today {
    my %params = @_;
    my $v = $params{value};
    my $part = sub {
        my $date = shift;
        "(= (field yyyymmddhh) (string \"$date\"))";
    };
    if ($v ne 'today' and $v ne 'specified') {
        return "(= (string \"Invalid conbination\") (null))"
    }
    if ($v eq 'specified') {
        return $part->($params{input});
    }
    return $part->('__TODAY__' . $params{hour});
}

sub proc_status {
    my %params = @_;
    my $v = $params{value};
    if ($v =~ m!^(\d)xx$!) {
        my $n1 = $1 . '00';
        my $n2 = $1 . '99';
        return "(and (>= (field status) (number $n1)) (<= (field status) (number $n2)))";
    }
    "(= (field status) (number $v)) ";
}

sub proc_path {
    my %params = @_;
    proc_text_field_equality('(field path)', $params{match}, $params{value});
}

sub proc_query {
    my %params = @_;
    my $key = $params{key};
    my $leftside = "(parse_url (concat (string \"http://x.jp\") (field path)) (string \"QUERY\") (string \"$key\"))";
    proc_text_field_equality($leftside, $params{match}, $params{value});
}

sub proc_referer {
    my %params = @_;
    proc_text_field_equality('(field referer)', $params{match}, $params{value});
}

sub proc_refererhost{
    my %params = @_;
    proc_text_field_equality('(parse_url (field referer) (string "HOST"))', $params{match}, $params{value});
}

sub proc_refererpath {
    my %params = @_;
    proc_text_field_equality('(parse_url (field referer) (string "PATH"))', $params{match}, $params{value});
}

sub proc_refererquery {
    my %params = @_;
    my $key = $params{key};
    my $leftside = "(parse_url (field referer) (string \"QUERY\") (string \"$key\"))";
    proc_text_field_equality($leftside, $params{match}, $params{value});
}

sub proc_agent {
    my %params = @_;
    proc_text_field_equality('(field agent)', $params{match}, $params{value});
}

sub proc_agenttype {
    my %params = @_;
    my $value = $params{value};
    if ($value eq 'pvagents') {
        my $pvtargets = '(array_construct (string "pc") (string "smartphone") (string "mobilephone") (string "appliance"))';
        return "(!= (is_in (parse_agent (field agent)) $pvtargets) (null))";
    }
    elsif ($value eq 'pc' or $value eq 'smartphone' or $value eq 'mobilephone' or $value eq 'appliance' or
               $value eq 'misc' or $value eq 'crawler' or $value eq 'unknown') {
        return "(!= (is_$value (parse_agent (field agent))) (null))";
    }
    die "invalid agent type: $value";
}

sub proc_method {
    my %params = @_;
    my $value = $params{value};
    "(= (field method) (string \"$value\"))";
}

sub proc_virtualhost {
    my %params = @_;
    proc_text_field_equality('(field vhost)', $params{match}, $params{value});
}

1;
