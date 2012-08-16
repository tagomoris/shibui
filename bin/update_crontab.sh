#!/bin/bash

SHIBUI_BIN_DIR=$(dirname $0)
SHIBUI_HOME=$SHIBUI_BIN_DIR"/../"
cd $SHIBUI_HOME
source $SHIBUI_HOME"/bin/env-alternative.sh"

# what we want
# crontab -l | filter old shibui jobs | cat - ./etc/shibui-queries | crontab -

exec >> $LOG_DIR/shibui_update_crontab.log
exec 2>&1

echo "============================================================="
echo "INFO: shibui update crontab job started at " $(date)
echo ""

# crontab tmp file: ./etc/cron.d/shibui-queries
TARGET=$SHIBUI_HOME/etc/cron.d/shibui-queries
TMP_TARGET=/tmp/shibui-queries.tmp
if [ -r $TARGET -a -w $TARGET ] && touch $TMP_TARGET ; then
    echo "ok to generate crontab data" > /dev/null
else
    echo "ERROR: cannot write to $TARGET or failed to touch $TMP_TARGET"
    exit 1
fi

echo "command:" perl -Iextlib/lib/perl5 -Ilib -MShib::ShibUI -MShib::ShibUI::GenerateCrontab \
     -e 'my $config = do $ARGV[0]; local $Shib::ShibUI::CONFIG = $config; Shib::ShibUI::GenerateCrontab->execute();' \
     $CONFIG > $TMP_TARGET

perl -Iextlib/lib/perl5 -Ilib -MShib::ShibUI -MShib::ShibUI::GenerateCrontab \
     -e 'my $config = do $ARGV[0]; local $Shib::ShibUI::CONFIG = $config; Shib::ShibUI::GenerateCrontab->execute();' \
     $CONFIG > $TMP_TARGET

diff -q $TMP_TARGET $TARGET >/dev/null 2>&1
if [ x"$?" = "x1" ] ; then
    echo "crontab update found"
    echo ""

    cat $TMP_TARGET > $TARGET

    genstart=$(crontab -l | grep '# AUTOGEN Shib::ShibUI::GenerateCrontab #' | sed -e 's/^\([0-9]*\):.*$/\1/')
    genend=$(crontab -l | grep '# END OF AUTOGEN #' | sed -e 's/^\([0-9]*\):.*$/\1/')
    if [ "x"$gemstart = "x" -o "x"$genend = "x" ]; then
        echo "ERROR: crontab auto generated lines marker not found"
        exit 1
    fi

    echo "Updating crontab ------------------------"
    crontab -l | sed '/^# AUTOGEN Shib::ShibUI::GenerateCrontab #/,/^# END OF AUTOGEN #/d' | cat - $TARGET
    # update crontab
    crontab -l | sed '/^# AUTOGEN Shib::ShibUI::GenerateCrontab #/,/^# END OF AUTOGEN #/d' | cat - $TARGET | crontab -
    echo "Updated crontab -------------------------"
fi

echo ""
echo "INFO: run_query job end at " $(date)
