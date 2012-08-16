#!/bin/bash

export PLACK_ENV="production"

SHIBUI_BIN_DIR=$(dirname $0)
SHIBUI_HOME=$SHIBUI_BIN_DIR"/../"
cd $SHIBUI_HOME
source $SHIBUI_HOME"/bin/env-alternative.sh"

exec perl -Iextlib/lib/perl5 -Ilib shibui.pl -c $CONFIG
