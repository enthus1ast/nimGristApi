Simple rest api client for [grist](https://getgrist.com/).

Examples:

```nim
import gristapi, json, times, strformat

# Create a new grist api client object.
var grist = newGristApi(
  docId = "<myDocId>",
  apiKey = "<myApiKey>",
  server = "http://127.0.0.1:8484/"
)

# `%*` is used to convert data to json in Nim.
# Here we fetch 3 items from the `TODO` table which are not done yet, sorted by the "Added" column
for row in grist.fetchTable("TODO", %* {"Done": [false]}, limit = 3, sort = "Added"):
  echo row["id"] # the id of the row
  echo row["fields"] # all the fields of the row


# Add some records to the `TODO` table
echo grist.addRecords("TODO", @[
    %* {"Task": "PETER", "Details": "DETAILS!!!"},
    %* {"Task": "PETER2", "Details": "DETAILS!!!2", "Deadline": "HAHA"}
  ]
)

grist.modifyRecords("TODO", @[
    ModRecord(id: 4, fields: %* {"Task": "ASD"}),
    ModRecord(id: 5, fields: %* {"Task": "BBBB", "Details": "DET"}),
    ModRecord(id: 6, fields: %* {"Task": "BBBB", "Details": "DET", "Deadline": "2022.01.13"}),
  ]
)

# Delete some records from the table `TODO`
grist.deleteRecords("TODO", [1,2,3])

# Download the document
let dateStr = $now() # `$` converts to a string in Nim

# `fmt` is one of Nim's string interpolation libraries.
# It is provided by the `strformat` imports above.
let dataSqlite = grist.downloadSQLITE()
writeFile(fmt"gene__{dateStr}.sqlite", dataSqlite)

let dataXLSX = grist.downloadXLSX()
writeFile(fmt"gene__{dateStr}.xlsx", dataXLSX)

let dataCSV = grist.downloadCSV("Entries")
writeFile(fmt"geneEntries__{dateStr}.csv", dataCSV)


# Readonly sql endpoint
## The simple get api
echo grist.sql("select * from TABLE1 where title == 'Foo'")
echo grist.sql("select startDate from TABLE1 where title == 'Foo'")

## More advanced post api
echo grist.sql("select startDate from TABLE1 where title == ?", @["Foo"], timeout = 500)
echo grist.sql("select startDate from TABLE1 where title == 'Foo'", @[], timeout = 500)


# Attachments
# Upload an attachment
# Attachments must be first uploaded to the grist document THEN they must be referenced
let id = grist.uploadAttachment("someFile.png")

# Reference attachment in a cell
# Use `cellAttachment(id)` or manually via `%* ["L", id]`
echo grist.addRecords("Table1", @[%* {"A": "AAA", "B": "BBB", "uploads": cellAttachment(id)}])

# Upload and reference in one step
echo grist.addRecords("Table1", @[%* {"A": "AAA", "B": "BBB", "uploads": cellAttachment(grist.uploadAttachment("someFile.png"))}])

# Get attachments metadata
echo grist.attachmentsMetadata(id)

# List all attachments
for metadata in grist.attachmentsMetadata():
  echo metadata

for metadata in grist.attachmentsMetadata(limit = 10):
  echo metadata

for file in grist.attachmentsMetadata(filter = %* {"fileName":["someFile.png"]}):
  echo file


# Download one attachment
echo grist.attachmentsDownload(id) # print the content of "someFile.png"
echo grist.attachmentsSaveSmart(id, "/tmp/") # saves the attachment to the folder "/tmp/" under its original name


# Download all attachments
grist.attachmentsSaveAllSmart("/tmp/") # saves all attachments 


## Webhooks

# List all webhooks
echo grist.webhooksGet()

# Remove all webhooks
grist.webhookRemoveAll()

# Create a webhook
# we need to use a `WebhookConfig` for this
var wh = WebhookConfig()
wh.name = "abc"
wh.memo = "foo baa baz"
wh.url = "http://asdf.com"
wh.enabled = true
wh.eventTypes = @[WHadd, WHupdate]
wh.isReadyColumn = ""
wh.tableId = "Todo"
 
let id = grist.webhookCreate(wh) # returns the id of the webhook
echo "Created: ", id

# We can use the id to modify the webhook
wh.name = "abc update"
grist.webhookModify(id, wh)

# And also to remove the webhook
echo grist.webhookRemove(id)


```




changelog:
- v0.2.9:
  - Added `timeout` parameter 
- v0.2.8:
  - Added webhook procs
- v0.2.7:
  - Added attachment procs
- v0.2.6:
  - Added sql endpoint.
- v0.2.5:
  - Added examples.
- v0.2.4:
  - FIX: Exported ModRecord
    - ModRecord is needed to change records in grist.
- v0.2.3:
  - Added `fetchTableAsTable`
    - To fetch grist tables as nim tables
- v0.2.2:
  - Added `listTable` and `listTableNames`
- v0.2.1:
  - Fixed bug that the `gristApi` was always empty.
- v0.2.0:
  - Added addRecords and fetchTable
- v0.1.0:
  - Download grist documents in sqlite, xlsx and csv
