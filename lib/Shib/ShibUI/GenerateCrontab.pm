package Shib::ShibUI::GenerateCrontab;

use 5.014;
use utf8;

use File::Basename qw/dirname/;
use Cwd qw/abs_path/;

use Shib::ShibUI;
use Shib::ShibUI::Data;

my $RUN_QUERY_SCRIPT_PATH = abs_path(dirname(__FILE__) . "/../../../bin/run_query.sh");

my $DATA;
sub data {
    $DATA ||= Shib::ShibUI::Data->new();
    $DATA;
}

sub execute {
    my ($this) = @_;
    my $schedules = $this->data->valid_schedules();
    print "# AUTOGEN Shib::ShibUI::GenerateCrontab #\n";
    foreach my $schedule (@$schedules) {
        print join(" ", $schedule->{schedule}, $RUN_QUERY_SCRIPT_PATH, $schedule->{query_id}), "\n";
    }
    print "# END OF AUTOGEN #\n";
}

1;
