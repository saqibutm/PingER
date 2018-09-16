#!/bin/bash

#The following line points to where the PingER measurements are to be found

cd /usr/local/share/pinger/data

HOST=ftp.slac.stanford.edu #This is the FTP servers host or IP address.
USER=anonymous #This is the FTP user that has access to the server.
PASS=saqibutm@outlook.com #This is the password for the FTP user.


# Call 1. Uses the ftp command with the -inv switches.
#-i turns off interactive prompting.
#-n Restrains FTP from attempting the auto-login feature.
#-v enables verbose and progress.

ftp -inv $HOST << EOF

# Call 2. Here the login credentials are supplied by calling the variables.

user $USER $PASS

cd incoming
cd 2001:da8:270:2018:f816:3eff:fef3:bd3
dir
binary
put ping-2018-06.txt
dir
quit
# End FTP Connection
bye

EOF