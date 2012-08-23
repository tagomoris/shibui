package Shib::ShibUI::HRForecastUtil;

use 5.014;
use utf8;
use Carp;

use Furl;
use HTTP::Request::Common qw//;

use Shib::ShibUI;

sub hrforecast_host {
    Shib::ShibUI->config->{hrforecast}->{host};
}

sub hrforecast_view_url_pattern {
    my $pattern = '^http://' . hrforecast_host() . '/(view|view_complex)/([^/]+)/([^/]+)/([^?/]+)($|\?)';
    qr!$pattern!;
}

sub check_url {
    my ($url) = @_;
    return scalar($url =~ hrforecast_view_url_pattern());
}

sub parse_url {
    my ($url) = @_;
    my ($type, $hr_service, $hr_section, $hr_graphname) = ($url =~ hrforecast_view_url_pattern());
    [($type eq 'view' ? 0 : 1), $hr_service, $hr_section, $hr_graphname];
}

sub api_url {
    my ($hr_service, $hr_section, $hr_graphname) = @_;
    'http://' . hrforecast_host() . '/api/' . join('/', $hr_service, $hr_section, $hr_graphname);
}

sub view_url {
    my ($hr_service, $hr_section, $hr_graphname, $complex) = @_;
    my $type = $complex ? 'view_complex' : 'view';
    join('/', ('http://' . hrforecast_host()), $type, $hr_service, $hr_section, $hr_graphname);
}

sub iframe_url {
    my ($hr_service, $hr_section, $hr_graphname, $complex) = @_;
    my $type = $complex ? 'ifr_complex' : 'ifr';
    join('/', ('http://' . hrforecast_host()), $type, $hr_service, $hr_section, $hr_graphname);
}

sub csv_url {
    my ($hr_service, $hr_section, $hr_graphname, $complex) = @_;
    my $type = $complex ? 'csv_complex' : 'csv';
    join('/', ('http://' . hrforecast_host()), $type, $hr_service, $hr_section, $hr_graphname);
}

sub post_data {
    my ($furl, $hr_service, $hr_section, $hr_graphname, $time, $value) = @_;
    my $url = api_url($hr_service, $hr_section, $hr_graphname);
    my $req = HTTP::Request::Common::POST(
        $url,
        Content_Type => 'form-data',
        Content      => [
            datetime => $time->strftime('%Y-%m-%d %H:00:00'),
            number => $value,
        ]
    );
    $furl->request($req);
}

sub related_graphs {
    my ($furl, $hr_service, $hr_section, $hr_graphname, $complex) = @_;
    my $res = $furl->get(csv_url($hr_service, $hr_section, $hr_graphname, $complex));

    return undef unless $res->code == 200;

    my $header_line = (split(/\n/, $res->body))[0];
    chomp $header_line;

    my $graphs = [];
    foreach my $col (split(/,/, $header_line)) {
        next if $col =~ m!^Date$!i;
        my ($service,$section,$graph) = ($col =~ m!^/([^/]+)/([^/]+)/([^/]+)$!);
        push $graphs, [$service,$section,$graph];
    }
    $graphs;
}

1;
