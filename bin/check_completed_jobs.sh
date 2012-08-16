#!/bin/bash

SHIBUI_BIN_DIR=$(dirname $0)
SHIBUI_HOME=$SHIBUI_BIN_DIR"/../"
cd $SHIBUI_HOME
source $SHIBUI_HOME"/bin/env-alternative.sh"

exec >> $LOG_DIR/shibui_check_completed.log
exec 2>&1

echo "============================================================="
echo "INFO: check_completed_jobs job started at " $(date)
echo ""
echo "command:" perl -Iextlib/lib/perl5 -Ilib -MShib::ShibUI -MShib::ShibUI::CheckCompletedJobs \
     -e 'my $config = do $ARGV[0]; local $Shib::ShibUI::CONFIG = $config; Shib::ShibUI::CheckCompletedJobs->execute();' \
     $CONFIG
echo ""
perl -Iextlib/lib/perl5 -Ilib -MShib::ShibUI -MShib::ShibUI::CheckCompletedJobs \
     -e 'my $config = do $ARGV[0]; local $Shib::ShibUI::CONFIG = $config; Shib::ShibUI::CheckCompletedJobs->execute();' \
     $CONFIG
echo ""
echo "INFO: check_completed_jobs job end at " $(date)
