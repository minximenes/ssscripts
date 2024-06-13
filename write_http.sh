#!/bin/bash

PDIR=$1
# write service conf
cat << EOF > http.tmp
[Unit]
Description=flask http
After=network.target

[Service]
User=ubuntu
Group=ubuntu
WorkingDirectory=$PDIR
Environment="PYTHONPATH=$PDIR"
ExecStart=gunicorn -b 0.0.0.0:5000 --workers 4 httpservice:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF