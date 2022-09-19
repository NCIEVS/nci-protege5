#!/bin/sh
protocol=https
host=
port=
user=
password=

# if troubleshooting, add -v to the two curl commands
curl -k -v -X POST -H "Content-Type:application/json" $protocol://$host:$port/nci_protege/login -d "{\"user\":\"$user\", \"password\":\"$password\"}" | jq --raw-output '. | .userid, .token' > usertok



res=""
for i in `cat usertok`
do
    res="${res}${i}"
    res="${res}:"
done
AUTH=`echo ${res%?} | tr -d "\n" | openssl enc -base64 -A`

#if troubleshooting, uncomment the following line
# echo $AUTH

curl -k -X POST -H "Authorization: Basic ${AUTH}" $protocol://$host:$port/nci_protege/server/shutdown | jq '.'
