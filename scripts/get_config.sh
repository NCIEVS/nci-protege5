#!/bin/sh
protocol=http
host=localhost
port=8080
user=
password=
out=config

# if troubleshooting, add -v to the two curl commands
curl -k -v -X POST -H "Content-Type:application/json" $protocol://$host:$port/nci_protege/login -d "{\"user\":\"$user\", \"password\":\"$password\"}" | jq --raw-output '. | .userid, .token' > usertok

res=""
for i in `cat usertok`
do
    res="${res}${i}"
    res="${res}:"
done
echo -n ${res%?}
## AUTH=`echo -n ${res%?} | openssl enc -base64 | tr -d "\n"`
AUTH=`echo ${res%?} | tr -d "\n" | openssl enc -base64`

#if troubleshooting, uncomment the following line
#echo $AUTH

curl -v -X GET -H "Authorization: Basic ${AUTH}" $protocol://$host:$port/nci_protege/meta/metaproject > $out
