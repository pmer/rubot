#!/bin/bash

ulimit -u 200
sudo -u nobody ruby1.8 start.rb $*

