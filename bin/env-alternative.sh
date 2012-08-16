#!/bin/bash

shibuidir=$(dirname $0)"/../"

env="development"

# 1. PLACK_ENV == 'production' ?
if [ "x"$PLACK_ENV = "xproduction" ]; then
    env="production"
fi

if [ "x"$PLACK_ENV = "x" ]; then
    # 2. env.production.sh and production.pl exists ?
    if [ -f $shibuidir"/bin/env.production.sh" -o -f $shibuidir"/production.pl" ]; then
        env="production"
    fi
fi

if [ $env = "production" ]; then
    envfile=$shibuidir"/bin/env.production.sh"
    CONFIG="production.pl"
    export PLACK_ENV="production"
else
    envfile=$shibuidir"/bin/env.sh"
    CONFIG="config.pl"
fi

source $envfile

[ -f $PERLBREW_BASHRC_PATH ] && source $PERLBREW_BASHRC_PATH
