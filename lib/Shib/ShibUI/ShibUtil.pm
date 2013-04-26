package Shib::ShibUI::ShibUtil;

use 5.014;
use utf8;
use Carp;

use Time::Piece;
use Time::Seconds;
use Furl;
use HTTP::Request::Common qw//;
use JSON::XS qw//;

use Shib::ShibUI;

sub shib_url {
    'http://' . Shib::ShibUI->config->{shib}->{host} . '/';
}

sub time_from_js {
    # to parse 'Thu Jan 26 2012 11:10:39 GMT+0900 (JST)' as '%a %b %d %Y %H:%M:%S GMT%z (%Z)'
    # but time-zone is useless
    my $time = shift;
    $time =~ s/ GMT[-+].*$//;
    Time::Piece->strptime($time, '%a %b %d %Y %H:%M:%S');
}

sub get_result {
    my ($furl, $shib_queryid) = @_;
    my $res = $furl->get(shib_url() . 'lastresult/' . $shib_queryid);
    if ($res->status ne '200' or $res->content_type !~ m!^application/json!) {
        return undef;
    }
    # say "result json body:", $res->body;
    return undef if $res->body eq 'null';
    my $result = JSON::XS::decode_json($res->body || '{}');
    if (not defined $result or not defined $result->{executed_at}) {
        return undef;
    }
    $result;
}

sub status_detail {
    my ($furl, $shib_queryid) = @_;
    my $res = $furl->get(shib_url() . 'detailstatus/' . $shib_queryid);
    if ($res->status ne '200' or $res->content_type !~ m!^application/json!) {
        return undef;
    }
    return undef if $res->body eq 'null';
    JSON::XS::decode_json($res->body || '{}');
}

sub kill_job {
    my ($furl, $shib_queryid) = @_;
    my $req = HTTP::Request::Common::POST(
        shib_url() . 'giveup',
        Content_Type => 'form-data',
        Content      => [
            queryid => $shib_queryid,
        ]
    );
    my $res = $furl->request($req);

    if ($res->status ne '200' or $res->content_type !~ m!^application/json!) {
        return undef;
    }
    return 1;
}

sub url_result_tsv {
    my ($shib_resultid) = @_;
    shib_url() . 'download/tsv/' . $shib_resultid;
}

sub download_result_tsv {
    my ($furl, $shib_resultid) = @_;
    my $res = $furl->get(url_result_tsv($shib_resultid));
    if ($res->status ne '200') {
        return undef;
    }
    # say "result tsv body:";
    # say $res->body;
    $res->body;
}

sub execute_query {
    my ($furl, $querystring) = @_;
    if (utf8::is_utf8($querystring)){
        utf8::encode($querystring);
    }
    my $req = HTTP::Request::Common::POST(
        shib_url() . 'execute',
        Content_Type => 'form-data',
        Content      => [
            scheduled => 'yes',
            querystring => $querystring
        ]
    );
    my $res = $furl->request($req);

    if ($res->status ne '200' or $res->content_type !~ m!^application/json!) {
        carp "For /execute, shib returns code " . $res->status . " and message:" . $res->body;
        return undef;
    }
    # say "query json body:", $res->body;
    my $shib_query = JSON::XS::decode_json($res->body);
    if (not defined $shib_query or not defined $shib_query->{queryid}) {
        carp "shib doesn't return queryid, status " . $res->status . " and message:" . $res->body;
        return undef;
    }
    $shib_query;
}

1;
