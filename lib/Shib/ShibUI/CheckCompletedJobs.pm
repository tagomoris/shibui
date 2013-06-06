package Shib::ShibUI::CheckCompletedJobs;

use 5.014;
use utf8;
use Carp;

use Try::Tiny;
use Time::Piece;
use Time::Seconds;
use Time::Piece::MySQL;
use Furl;
use HTTP::Request::Common qw//;

use Shib::ShibUI;

use Shib::ShibUI::Data;
use Shib::ShibUI::ShibUtil;
use Shib::ShibUI::HRForecastUtil;

my $DATA;
sub data {
    $DATA ||= Shib::ShibUI::Data->new();
    $DATA;
}

sub process_data {
    my ($furl, $query, $graphs, $data, $execute_offset) = @_;

    my $date_col = $query->{date_field_num};
    my $date_format = $query->{date_format};

    $execute_offset ||= 0;

    my @lines = split("\n", $data);
    shift @lines; # cut header line

    say "start to posting data about query_id ", $query->{query_id};

    foreach my $line (@lines) {
        my @cols = split("\t", $line);

        my $time;
        if ($date_col == -1) {
            $time = scalar(localtime) - (ONE_DAY * $execute_offset);
        }
        else {
            try {
                $time = Time::Piece->strptime($cols[$date_col], $date_format);
            } catch {
                say "Failed to parse time: " . $_;
            };
        }
        unless ($time) {
            say "Cannot parse date value, column " . $date_col . ", value " . $cols[$date_col] . ", format " . $date_format;
            next;
        }
        foreach my $graph (@$graphs) {
            my $num = $graph->{value_field_num};
            my $value = $cols[$num];
            if (not defined $value) {
                carp "No value exists in column number $num for graph name " . $graph->{label};
                next;
            }
            Shib::ShibUI::HRForecastUtil::post_data(
                $furl, $graph->{hr_service}, $graph->{hr_section}, $graph->{hr_graphname}, $time, $value
            );
        }
    }
    say "end of post data";
}


sub execute {
    my ($this) = @_;
    my $furl = Furl->new(agent => 'Furl Shib::ShibUI::RunQuery (perl)', timeout => 30);

    my $histories = $this->data->waiting_histories();
    foreach my $history (@$histories) {
        my $query = $this->data->query($history->{query_id});
        if (not $query) {
            carp "No query entry for query_id " . $history->{query_id} . " of history_id " . $history->{id};
            next;
        }
        my $result = Shib::ShibUI::ShibUtil::get_result($furl, $history->{shib_query_id});

        next if ($result->{state} ne 'done' and $result->{state} ne 'error');

        my $graphs = $this->data->graphs($history->{query_id});
        my $data = Shib::ShibUI::ShibUtil::download_result_tsv($furl, $result->{resultid});

        my $execute_offset = $history->{offset};
        process_data($furl, $query, $graphs, $data, $execute_offset);

        $this->data->update_history(
            $history->{id},
            $result->{state},
            Shib::ShibUI::ShibUtil::time_from_js($result->{completed_at})->mysql_timestamp,
        );
    }

    my $oneshots = $this->data->waiting_oneshots();
    foreach my $oneshot (@$oneshots) {
        my $result = Shib::ShibUI::ShibUtil::get_result($furl, $oneshot->{shib_query_id});

        next if $result->{state} ne 'done' and $result->{state} ne 'error';

        $this->data->update_oneshot(
            $oneshot->{id},
            $result->{state},
            Shib::ShibUI::ShibUtil::time_from_js($result->{completed_at})->mysql_timestamp,
        );
    }
}

1;
