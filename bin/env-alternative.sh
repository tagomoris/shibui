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

envfile=$shibuidir"/bin/env.sh"
CONFIG="config.pl"

if [ $env = "production" ]; then
    if [ -f $shibuidir"/bin/env.production.sh" ]; then
        envfile=$shibuidir"/bin/env.production.sh"
    fi
    if [ -f "production.pl" ]; then
        CONFIG="production.pl"
    fi
    export PLACK_ENV="production"
fi

source $envfile

[ -f $PERLBREW_BASHRC_PATH ] && source $PERLBREW_BASHRC_PATH
