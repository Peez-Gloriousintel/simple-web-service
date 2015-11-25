# LevelDB Web Service
LevelDB Web Service is a web service written in Perl in order to provide a key-value database based on LevelDB by Google, connecting through a simple RESTful API (GET, POST, DELETE, and PUT).

### Configuration
```
{
  "Port" : 8099,
  "DBName" : "sample.db",
  "Username" : "admin",
  "Password" : "admin"
}
```
 * Left Username and Password fields blank to bypass authentication
 
### Dependencies
 * Tie::LevelDB
 * IO::Socket
 * JSON
 * MIME::Base64

### Usage and Example
 * To set a key and its value
```
 Method: POST
 URL: http://localhost:8099/api/
 Body: 
 {
  "key" : "hello",
  "value" : "world"
 }
```
Test: ``` curl -H 'Content-Type: application/json' --user admin:admin -d '{ "key":"hello", "value":"world" }' -X POST http://localhost:8099/api/ ```

 * To get a value of a given key
```
 Method: GET
 URL: http://localhost:8099/api/<key>
 Body: {}
```
 Test: ``` curl -H "Content-Type: application/json"  --user admin:admin -X GET  http://localhost:8099/api/hello ```
 
  * To delete a key-value pair
```
 Method: DELETE
 URL: http://localhost:8099/api/<key>
 Body: {}
```
 Test: ``` curl -H "Content-Type: application/json"  --user admin:admin -X DELETE  http://localhost:8099/api/hello ```
 
 * To send batch commands, supporting only put and delete
```
 Method: PUT
 URL: http://localhost:8099/api/
 Body: 
 {
  "batch" : [
      "put <key> <value>",
      "...some commands here...", 
      "delete <key>"
  ]
 }
```
Test: ``` curl -H 'Content-Type: application/json' --user admin:admin -d '{ "batch": ["put hello world", "delete hello"] }' -X PUT http://localhost:8099/api/ ```
