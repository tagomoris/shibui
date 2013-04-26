package Shib::ShibUI::RunQuery;

use 5.014;
use utf8;
use Carp;

use Time::Piece;
use Time::Seconds;
use Time::Piece::MySQL;
use Furl;

use Shib::ShibUI::Data;
use Shib::ShibUI::ShibUtil;

my $SHIB_MAX_TRIES = 3;
my $SHIB_RETRY_INTERVAL_SECONDS = 30;

my $DATA;
sub data {
    $DATA ||= Shib::ShibUI::Data->new();
    $DATA;
}

sub get_xdays_ago {
    my ($days, $format) = @_;
    my $today = localtime;
    my $t = $today - $days * ONE_DAY;
    $t->strftime($format);
}

sub xdays_ago {
    my $days = shift;
    get_xdays_ago($days, '%Y%m%d');
}

sub today {
    my $offset = shift || 0;
    get_xdays_ago($offset, '%Y%m%d');
}

sub yesterday {
    my $offset = shift || 0;
    get_xdays_ago($offset + 1, '%Y%m%d');
}

sub month {
    my $offset = shift || 0;
    get_xdays_ago($offset, '%Y%m');
}

sub lastmonth {
    my $offset = shift || 0;
    my $time = localtime;
    $time = $time - ($offset * ONE_DAY);
    ($time - $time->mday * ONE_DAY)->strftime('%Y%m');
}

# __SERVICE__
# サービス名
# __TODAY__
# クエリ実行時の日付 (YYYYMMDD)
# __xDAYS_AGO__
# クエリ実行時よりx日前の日付(1-9) (YYYYMMDD)
# __YESTERDAY__
# クエリ実行時の前日の日付(__1DAYS_AGO__) (YYYYMMDD)
# __MONTH__
# クエリ実行時の月 (YYYYMM)
# __LASTMONTH__
# クエリ実行時の前月 (YYYYMM)

sub build_query {
    my ($query, $service, $description, $offset) = @_;
    my ($today, $yesterday, $month, $lastmonth) = (today($offset), yesterday($offset), month($offset), lastmonth($offset));
    $query =~ s/_{2}SERVICE_{2}/$service/g;
    $query =~ s/_{2}TODAY_{2}/$today/g;
    $query =~ s/_{2}YESTERDAY_{2}/$yesterday/g;
    $query =~ s/_{2}MONTH_{2}/$month/g;
    $query =~ s/_{2}LASTMONTH_{2}/$lastmonth/g;
    foreach my $n (1..9) {
        my $t = xdays_ago($offset + $n);
        $query =~ s/_{2}${n}DAYS_AGO_{2}/$t/g;
    }
    $query;
}

sub execute {
    my ($this, $query_id, $spot, $offset) = @_;
    $spot //= 0;
    $offset //= 0;
    my $query = $this->data->query($query_id);
    die "query id ${query_id} not found" unless $query;

    if ($query->{status} == 0) {
        die "Marked not to run (id:${query_id})";
    }

    my $querystring = build_query($query->{query}, $query->{service}, $query->{description}, $offset);

    my $furl = Furl->new(agent => 'Furl Shib::ShibUI::RunQuery (perl)', timeout => 30);

    my $shib_query;
    my $tries = 0;
    while ($tries < $SHIB_MAX_TRIES) {
	$shib_query = Shib::ShibUI::ShibUtil::execute_query($furl, $querystring);
	last if $shib_query;

	$tries++;
	sleep $SHIB_RETRY_INTERVAL_SECONDS;
    }
    unless ($shib_query) {
	my $failed_history_id = $this->data->insert_history(
	    $query_id,
	    '-', # shib_queryid
	    ($spot ? $offset : -1)# save_offset
	);
	$this->data->update_history($failed_history_id, 'error', Time::Piece->new->mysql_timestamp);

	die "failed to execute query with shib errors.";
    }

    my $shib_queryid = $shib_query->{queryid};

    my $save_offset = -1;
    if ($spot) {
        $save_offset = $offset;
    }
    my $history_id = $this->data->insert_history(
        $query_id,
        $shib_queryid,
        $save_offset
    );
}

sub execute_oneshot {
    my ($this, $query, $offset) = @_;
    my $querystring = build_query($query, '__SERVICE__', 'dummy....', $offset);
    my $furl = Furl->new(agent => 'Furl Shib::ShibUI::RunQuery (perl)', timeout => 30);

    my $shib_query = Shib::ShibUI::ShibUtil::execute_query($furl, $querystring);
    $shib_query->{queryid};
}

1;
