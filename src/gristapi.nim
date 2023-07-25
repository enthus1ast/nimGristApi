import strutils, uri, tables, json, strformat
import std/jsonutils
import puppy
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
  let path = fmt"/api/docs/{grist.docId}/tables/{table}/records"
  var url = grist.server / path
  url.query = encodeQuery([
    ("noparse", $noparse)
  ])
  var records = %* {"records": []}
  for row in data:
    records["records"].add (%* {"fields": row})
  let respjs = parseJson(grist.post(url, body = $ %* records, headers = @[("Content-Type", "application/json")]))
  for elem in respjs["records"]:
    result.add elem["id"].getInt()

proc listTable*(grist: GristApi): seq[JsonNode] =
  ## Returns all the tables, with their fields
  let path = fmt"/api/docs/{grist.docId}/tables"
  var url = grist.server / path
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
  var url = grist.server / path
  for group in groups.values:
    var records = %* {"records": []}
    for modRecord in group:
      records["records"].add(%* {"id": modRecord.id, "fields": modRecord.fields})
      echo $records
    discard grist.patch(url, $records, headers = @[("Content-Type", "application/json")])


proc deleteRecords*(grist: GristApi, table: string, ids: openArray[Id]) =
  # /docs/{docId}/tables/{tableId}/data/delete
  let path = fmt"/api/docs/{grist.docId}/tables/{table}/data/delete"
  var url = grist.server / path
  discard grist.post(url, body = $ %* ids, headers = @[("Content-Type", "application/json")])


proc columns*(grist: GristApi, table: string): JsonNode =
  let path = fmt"/api/docs/{grist.docId}/tables/{table}/columns"
  var url = grist.server / path
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
  var url = grist.server / path
  return grist.get(url)


proc downloadCSV*(grist: GristApi, tableId: string): string  =
  ## Download and returns the document as CSV
  let path = fmt"/api/docs/{grist.docId}/download/csv?tableId={tableId}"
  var url = grist.server / path
  return grist.get(url)


proc downloadSQLITE*(grist: GristApi): string  =
  ## Download and returns the document as SQLITE
  let path = fmt"/api/docs/{grist.docId}/download"
  var url = grist.server / path
  return grist.get(url)


