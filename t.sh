#!/bin/bash

DB="http://adm:pass@127.0.0.1:15984"

echo -e "Create db:"
curl -XDELETE $DB/db
curl -XPUT $DB/db

echo -e "\nInsert bulk docs:"
curl -XPOST $DB/db/_bulk_docs \
  -H 'Content-Type: application/json' \
  -d '{
	"docs": [
		{
			"_id": "FishStew",
			"servings": 4,
			"subtitle": "Delicious with freshly baked bread",
			"title": "FishStew"
		},
		{
			"_id": "LambStew",
			"servings": 6,
			"subtitle": "Serve with a whole meal scone topping",
			"title": "LambStew"
		},
		{
			"_id": "BeefStew",
			"servings": 8,
			"subtitle": "Hand-made dumplings make a great accompaniment",
			"title": "BeefStew"
		}
	]
}'

echo -e "\nGet db/_all_docs:"
curl $DB/db/_all_docs

echo -e "\nReplicate from db to db2:"
curl -XPUT $DB/_replicator/rep_id \
  -H 'Content-Type: application/json' \
  -d '{
	"source": {
		"url": "http://adm:pass@127.0.0.1:15984/db"
	},
	"target": {
		"url": "http://adm:pass@127.0.0.1:15984/db2"
	},
	"create_target": true
}'

echo -e "\nCheck db2:"
curl $DB/db2

echo -e "\nCheck db2/_all_docs:"
curl $DB/db2/_all_docs
