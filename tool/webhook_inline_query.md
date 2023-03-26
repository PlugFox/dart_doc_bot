# How to test webhook and inline query

(set webhook)[https://core.telegram.org/bots/api#setwebhook]

### Inline query:

```bash
curl -v -k -X POST -H "Content-Type: application/json" -H "Cache-Control: no-cache"  -d '{
"update_id":10000,
"inline_query":{
  "id": 134567890097,
  "from":{
     "last_name":"Test Lastname",
     "type": "private",
     "id":1111111,
     "first_name":"Test Firstname",
     "username":"Testusername"
  },
  "query": "inline query",
  "offset": ""
}
}' "https://YOUR.BOT.URL:YOURPORT/"
```

### Chosen inline query:

```bash
curl -v -k -X POST -H "Content-Type: application/json" -H "Cache-Control: no-cache"  -d '{
"update_id":10000,
"chosen_inline_result":{
  "result_id": "12",
  "from":{
     "last_name":"Test Lastname",
     "type": "private",
     "id":1111111,
     "first_name":"Test Firstname",
     "username":"Testusername"
  },
  "query": "inline query",
  "inline_message_id": "1234csdbsk4839"
}
}' "https://YOUR.BOT.URL:YOURPORT/"
```

### Callback query:

```bash
curl -v -k -X POST -H "Content-Type: application/json" -H "Cache-Control: no-cache"  -d '{
"update_id":10000,
"callback_query":{
  "id": "4382bfdwdsb323b2d9",
  "from":{
     "last_name":"Test Lastname",
     "type": "private",
     "id":1111111,
     "first_name":"Test Firstname",
     "username":"Testusername"
  },
  "data": "Data from button callback",
  "inline_message_id": "1234csdbsk4839"
}
}' "https://YOUR.BOT.URL:YOURPORT/"
```
