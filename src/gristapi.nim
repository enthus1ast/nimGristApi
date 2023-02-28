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
  Id = int
  ModRecord = object
    id: int
    fields: JsonNode

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

# proc listTables*(grist: GristApi):

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


when isMainModule and true:
  import times
  var grist = newGristApi(
    # docId = "kTveggjMFamxzQL7AbFoxu",
    # apiKey = "d17a2270af40484d3592cba694157b9fb720e01a",
    # server = "http://192.168.174.238:8484/"
    # server = "http://172.16.3.210:8484/"
    docId = "irtKNL9u3sBr6HCove2iKZ",
    apiKey = "da073fa6d424d4126e65a8a054a6693de19f485e",
    server = "http://127.0.0.1:8484/"
  )

  for row in grist.fetchTable("TODO", %* {"Done": [true]}, limit = 3, sort = "Added"):
    # echo row
    echo row["fields"]

  echo grist.addRecords("TODO", @[
      %* {"Task": "PETER", "Details": "DETAILS!!!"},
      %* {"Task": "PETER2", "Details": "DETAILS!!!2", "Deadline": "HAHA"}
    ]
  )

  grist.modifyRecords("TODO", @[
      ModRecord(id: 4, fields: %* {"Task": "ASD"}),
      ModRecord(id: 5, fields: %* {"Task": "BBBB", "Details": "DET"}),
      ModRecord(id: 6, fields: %* {"Task": "BBBB", "Details": "DET", "Deadline": "2022.01.13"}),
      # ModRecord(id: 2, fields: %* {"Task": "PETER2", "Details": "DETAILS!!!2", "Deadline": "HAHA"})
    ]
  )

  # grist.deleteRecords("TODO", [1,2,3])
  echo grist.columns("TODO")

  # let dateStr = ($now()).replace(":", "-")

  # let dataSqlite = grist.downloadSQLITE()
  # writeFile(fmt"gene__{dateStr}.sqlite", dataSqlite)

  # let dataXLSX = grist.downloadXLSX()
  # writeFile(fmt"gene__{dateStr}.xlsx", dataXLSX)

  # let dataCSV = grist.downloadCSV("Entries")
  # writeFile(fmt"geneEntries__{dateStr}.csv", dataCSV)

# when isMainModule and false:
#   var grist = newGristApi(
#     docId = "v2GoPdCvmv5p",
#     apiKey = "da073fa6d424d4126e65a8a054a6693de19f485e",
#     server = "http://127.0.0.1:8484/"
#   )
#   # var emails: OrderedTable[int, JsonNode]
#   # for elem in waitFor grist.fetchTable("Emails"):
#   #   echo elem
#   #   emails[elem["id"].getInt] = elem
#   #   # echo elem{"fields", "User"}.getStr(), " " ,  elem{"fields", "Email"}.getStr()
#   #   # echo elem

#   var users: OrderedTable[int, JsonNode]
#   for elem in waitFor grist.fetchTable("Users", filters = {"FirstName": "Ivan"}.toTable()):
#     # echo elem
#     # users[elem["id"].getInt] = elem
#     echo elem{"fields", "FullName"}.getStr().alignLeft(40), " ", elem{"fields", "Email"}.getElems()
#     # echo elem{"fields", "User"}.getStr(), " " ,  elem{"fields", "Email"}.getStr()
#     # echo elem

#   # for emailElem in emails.values:
#     # echo users[emailElem{"id"}.getInt]{"fields", "FullName"}

