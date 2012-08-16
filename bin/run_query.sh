#!/bin/bash

TARGET_QUERY_ID=$1

SHIBUI_BIN_DIR=$(dirname $0)
SHIBUI_HOME=$SHIBUI_BIN_DIR"/../"
cd $SHIBUI_HOME
source $SHIBUI_HOME"/bin/env-alternative.sh"

exec >> $LOG_DIR/shibui_run_query.log
exec 2>&1

echo "============================================================="
echo "INFO: run_query job started at " $(date)
echo ""
echo "command:" perl -Iextlib/lib/perl5 -Ilib -MShib::ShibUI -MShib::ShibUI::RunQuery \
     -e 'my $config = do $ARGV[0]; local $Shib::ShibUI::CONFIG = $config; Shib::ShibUI::RunQuery->execute($ARGV[1]);' \
     $CONFIG $TARGET_QUERY_ID
echo ""
perl -Iextlib/lib/perl5 -Ilib -MShib::ShibUI -MShib::ShibUI::RunQuery \
     -e 'my $config = do $ARGV[0]; local $Shib::ShibUI::CONFIG = $config; Shib::ShibUI::RunQuery->execute($ARGV[1]);' \
     $CONFIG $TARGET_QUERY_ID

echo ""
echo "INFO: run_query job end at " $(date)
