# For adding values find a good way to encode "GristObjCode" 
# https://support.getgrist.com/code/enums/GristData.GristObjCode/#list


import strutils, uri, tables, json, strformat, os
import std/jsonutils

import puppy
export MultipartEntry # puppy; for attachment upload

import sequtils, algorithm, hashes

type
  GristApi* = object
    server*: Uri
    docId*: string
    apiKey: string
    headers*: seq[(string, string)]
    timeout*: float32 # seconds
  Id = int
  ModRecord* = object
    id*: int
    fields*: JsonNode

proc apiKey*(grist: GristApi): string =
  return grist.apiKey

proc `apiKey=`*(grist: var GristApi, val: string) =
  if grist.headers.contains("Authorization"):
    for hkey, hval in grist.headers.mitems:
      if hkey == "Authorization":
        hval = fmt"Bearer {val}"
  else:
    grist.headers.add(("Authorization", fmt"Bearer {val}"))

proc newGristApi*(docId, apiKey: string, server: Uri | string): GristApi =
  result.docId = docId
  result.apiKey = apiKey
  result.timeout = 240'f32
  when server is Uri:
    result.server = server
  else:
    result.server = parseUri(server)
  # result.client = newAsyncHttpClient()
  # result.client.headers = newHttpHeaders(
  result.headers = @[("Authorization", fmt"Bearer {apiKey}")]

proc request*(grist: GristApi, url: Uri, body = "", headers: seq[(string, string)] = @[], verb: string = "get"): string =
  var combinedHeaders = grist.headers & headers
  var req = newRequest($url, verb, combinedHeaders)
  req.timeout = grist.timeout
  req.body = body
  var resp = fetch(req)
  if resp.code != 200:
    raise newException(ValueError, resp.body)
  return resp.body

template get*(grist: GristApi, url: Uri, headers: seq[(string, string)] = @[]): string =
  grist.request(url, "", headers, "get")

template post*(grist: GristApi, url: Uri, body: string, headers: seq[(string, string)] = @[]): string =
  grist.request(url, body, headers, "post")

template patch*(grist: GristApi, url: Uri, body: string, headers: seq[(string, string)] = @[]): string =
  grist.request(url, body, headers, "patch")

proc addRecords*(grist: GristApi, table: string, data: seq[JsonNode], noparse = false): seq[Id] =
  ## Adds records to the given table.
  ## The `data` json nodes must be a dict, where the keys correcspond to grist column names
  let path = fmt"/api/docs/{grist.docId}/tables/{table}/records"
  var url = grist.server / path
  url.query = encodeQuery([
    ("noparse", $noparse)
  ])
  var records = %* {"records": []}
  for row in data:
    if row.kind != JObject:
      raise newException(ValueError, "rows must be JsonObjects: " & $row)
    records["records"].add (%* {"fields": row})
  let respjs = parseJson(grist.post(url, body = $ %* records, headers = @[("Content-Type", "application/json")]))
  for elem in respjs["records"]:
    result.add elem["id"].getInt()

# proc addRecords*(grist: GristApi, table: string, data: seq[JsonNode], mappings: seq[string], noparse = false): seq[Id] =
#   ## Adds records to the given table.
#   ## The `data` json nodes can be a list, but you must provide a mapping.
#   let path = fmt"/api/docs/{grist.docId}/tables/{table}/records"
#   var url = grist.server / path
#   url.query = encodeQuery([
#     ("noparse", $noparse)
#   ])
#   var records = %* {"records": []}
#   for row in data:
#     if row.kind != JArray:
#       raise newException(ValueError, "a row must be a JsonArray: " & $row)
#     var j: JsonNode = %* {}
#     if row.len != mappings.len:
#       raise newException(ValueError, "row.len and mapping.len must be the same: " & $row)
#     for idx, mapping in mappings:
#       j[mapping] = row[idx]
#     records["records"].add(%* {"fields": j})
#   let respjs = parseJson(grist.post(url, body = $ %* records, headers = @[("Content-Type", "application/json")]))
#   for elem in respjs["records"]:
#     result.add elem["id"].getInt()
#
#
#
proc listTable*(grist: GristApi): seq[JsonNode] =
  ## Returns all the tables, with their fields
  let path = fmt"/api/docs/{grist.docId}/tables"
  let url = grist.server / path
  var respjs = parseJson(grist.get(url))
  for table in respjs["tables"]:
    result.add table

proc listTableNames*(grist: GristApi): seq[string] =
  ## Returns all the table names of the document
  for table in grist.listTable():
    result.add table["id"].getStr()

func genGroupHash(modRecord: ModRecord): Hash =
  var h = 0.Hash
  for elem in toSeq(modRecord.fields.keys).sorted(SortOrder.Ascending):
    h = h !& hash(elem)
  return !$h

proc modifyRecords*(grist: GristApi, table: string, modRecords: openArray[ModRecord]) =
  var groups: Table[Hash, seq[ModRecord]]
  # Since we cannot update records with different keys, we must group them first
  # then do multiple api calls, one for each group.
  for modRecord in modRecords:
    let gh = genGroupHash(modRecord)
    if not groups.hasKey(gh): groups[gh] = @[]
    groups[gh].add modRecord
  let path = fmt"/api/docs/{grist.docId}/tables/{table}/records"
  let url = grist.server / path
  for group in groups.values:
    var records = %* {"records": []}
    for modRecord in group:
      records["records"].add(%* {"id": modRecord.id, "fields": modRecord.fields})
      echo $records
    discard grist.patch(url, $records, headers = @[("Content-Type", "application/json")])


proc deleteRecords*(grist: GristApi, table: string, ids: openArray[Id]) =
  # /docs/{docId}/tables/{tableId}/data/delete
  let path = fmt"/api/docs/{grist.docId}/tables/{table}/data/delete"
  let url = grist.server / path
  discard grist.post(url, body = $ %* ids, headers = @[("Content-Type", "application/json")])

proc columns*(grist: GristApi, table: string): JsonNode =
  let path = fmt"/api/docs/{grist.docId}/tables/{table}/columns"
  let url = grist.server / path
  return parseJson(grist.get(url))

proc fetchTable*(grist: GristApi, table: string, filter: JsonNode = %* {}, limit = 0, sort = ""): seq[JsonNode]  =
  ## fetches rows from a grist document
  ## for details how to use this api please consult:
  ##   https://support.getgrist.com/api/#tag/records
  let path = fmt"/api/docs/{grist.docId}/tables/{table}/records"
  var url = grist.server / path
  url.query = encodeQuery([
    ("filter",$(filter)),
    ("limit", $limit),
    ("sort", sort)
  ])
  let body = grist.get(url)
  let js = parseJson(body)
  var ret: seq[JsonNode] = @[]
  if js.hasKey("records"):
    for record in js["records"].getElems():
      ret.add record
    return ret


proc fetchTableAsTable*(grist: GristApi, table: string, filter: JsonNode = %* {}, limit = 0, sort = ""): Table[int, JsonNode]  =
  ## same as fetchTable, but returns a table with
  ## id -> fields
  result = initTable[int, JsonNode]()
  for elem in fetchTable(grist, table, filter, limit, sort):
    result[elem["id"].getInt] = elem["fields"]

proc downloadXLSX*(grist: GristApi): string  =
  ## Download and returns the document as XLSX
  let path = fmt"/api/docs/{grist.docId}/download/xlsx"
  let url = grist.server / path
  return grist.get(url)

proc downloadCSV*(grist: GristApi, tableId: string): string  =
  ## Download and returns the document as CSV
  let path = fmt"/api/docs/{grist.docId}/download/csv"
  var url = grist.server / path
  url.query = encodeQuery([
    ("tableId", tableid)
  ])
  return grist.get(url)


proc downloadSQLITE*(grist: GristApi): string  =
  ## Download and returns the document as SQLITE
  let path = fmt"/api/docs/{grist.docId}/download"
  let url = grist.server / path
  return grist.get(url)

proc sql*(grist: GristApi, sql: string): seq[JsonNode] =
  ## Performs an sql query against the document.
  ## This internally uses the exposed `get` api endpoint
  ## For details consult: https://support.getgrist.com/api/#tag/sql
  let path = fmt"/api/docs/{grist.docId}/sql"
  var url = grist.server / path
  url.query = encodeQuery([
    ("q", sql)
  ])
  let body = grist.get(url)
  let js = parseJson(body)
  var ret: seq[JsonNode] = @[]
  if js.hasKey("records"):
    for record in js["records"].getElems():
      ret.add record
    return ret


proc sql*(grist: GristApi, sql: string, args: seq[string], timeout = 1000): seq[JsonNode] =
  ## Performs an sql query against the document.
  ## This internally uses the exposed `post` api endpoint
  ## For details consult: https://support.getgrist.com/api/#tag/sql
  let path = fmt"/api/docs/{grist.docId}/sql"
  let url = grist.server / path
  let reqBody = %* {
    "sql": sql,
    "args": args,
    "timeout": timeout
  }
  let body = grist.post(url, body = $reqBody, headers = @[("Content-Type", "application/json")])
  let js = parseJson(body)
  var ret: seq[JsonNode] = @[]
  if js.hasKey("records"):
    for record in js["records"].getElems():
      ret.add record
    return ret


proc attachmentsMetadata*(grist: GristApi, attachmentId: int): JsonNode =
  ## List attachments metadata for one attachment
  let path = fmt"/api/docs/{grist.docId}/attachments/{attachmentId}"
  let url = grist.server / path
  let body = grist.get(url)
  let js = parseJson(body)
  return js


proc attachmentsMetadata*(grist: GristApi, filter: JsonNode = %* {}, sort: string = "", limit: int = 0): seq[JsonNode] =
  ## List all the attachments metadata of the document
  ## https://support.getgrist.com/api/#tag/attachments/operation/listAttachments
  let path = fmt"/api/docs/{grist.docId}/attachments"
  var url = grist.server / path
  url.query = encodeQuery([
    ("filter",$(filter)),
    ("limit", $limit),
    ("sort", sort)
  ])
  let body = grist.get(url)
  let js = parseJson(body)
  var ret: seq[JsonNode] = @[]
  if js.hasKey("records"):
    for record in js["records"].getElems():
      ret.add record
    return ret


proc attachmentsDownload*(grist: GristApi, attachmentId: int): string = # TODO string is not correct for binaray data it should be seq[byte]
  ## returns the content of the attachment
  let path = fmt"/api/docs/{grist.docId}/attachments/{attachmentId}/download"
  let url = grist.server / path
  let body = grist.get(url)
  return body

proc attachmentsSave*(grist: GristApi, attachmentId: int, path: string) =
  ## saves the attachment on the filesystem as `path`
  writeFile(path, grist.attachmentsDownload(attachmentId))

proc attachmentsSaveSmart*(grist: GristApi, attachmentId: int, dir: string) =
  ## saves the attachment in the dir `dir`. This gets the name of the file and stores it with its original name
  let metadata = grist.attachmentsMetadata(attachmentId)
  let filename = metadata["fileName"].getStr()
  let path = $(parseUri(dir) / filename)
  grist.attachmentsSave(attachmentId, path)

proc attachmentsSaveSmart*(grist: GristApi, attachmentId: int, metadata: JsonNode, dir: string) =
  ## saves the attachment in the dir `dir`. This gets the name of the file and stores it with its original name
  let filename = metadata["fileName"].getStr()
  let path = $(parseUri(dir) / filename)
  grist.attachmentsSave(attachmentId, path)

proc attachmentsSaveAllSmart*(grist: GristApi, dir: string, filter: JsonNode = %* {}, sort: string = "", limit: int = 0) =
  ## saves all attachments in the dir `dir`
  for metadata in grist.attachmentsMetadata(filter, sort, limit):
    grist.attachmentsSaveSmart(metadata["id"].getInt, metadata["fields"], dir)

proc uploadAttachment*(grist: GristApi, entries: seq[MultipartEntry]): seq[int] =
  ## Request Body schema: multipart/form-data
  ## https://{subdomain}.getgrist.com/api/docs/{docId}/attachments
  ## Low level upload procedure:
  ##   ..code:
  ##
  ##  echo grist.uploadAttachment(@[MultipartEntry(
  ##    name: "upload",
  ##    fileName: "test.txt",
  ##    # contentType: "text/plain", # <- opional
  ##    payload: "TEST",
  ##  )])
  let path = fmt"/api/docs/{grist.docId}/attachments"
  let url = grist.server / path
  let (contentType, body) = encodeMultipart(entries)
  let resp = grist.post(url, body, @[("Content-Type", contentType)])
  let js = parseJson(resp)
  for id in js:
    result.add id.getInt()


proc uploadAttachment*(grist: GristApi, path: string): int =
  ## Upload a file from the filesystem
  let body = readFile(path)
  return grist.uploadAttachment(@[MultipartEntry(
    name: "upload",
    fileName: path.extractFilename,
    payload: body
  )])[0]


proc attachmentsDeleteAllUnused*(grist: GristApi) =
  ## *Undocumented api*, that deletes all unused attachments.
  ## Grist removes unused attachments periodically, so this is not strictly needed
  ##
  ## https://community.getgrist.com/t/how-to-upload-images-as-attachment-via-api-with-python/1216/3 
  ## POST /api/docs/{doc_id}/attachments/removeUnused
  let path = fmt"/api/docs/{grist.docId}/attachments/removeUnused"
  let url = grist.server / path
  let resp = grist.post(url, "")


proc cellAttachment*(id: int): JsonNode =
  ## Use this to reference an attachment as a cell value.
  return %* ["L", id]
# proc uploadAttachment*(grist: GristApi, files: seq[tuple[filename, content: string]]): seq[JsonNode] =
