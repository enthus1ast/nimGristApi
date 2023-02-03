import strutils, uri, tables, json, strformat
import std/jsonutils
import puppy

type
  GristApi* = object
    server*: Uri
    docId*: string
    headers*: seq[(string, string)]
  # GristValueKind = enum
  #   gvString
  #   gvNumber
  #   gvBool
  # GristValue = object
  #   kind: GristValueKind
  # Row = Table[string, GristValue]
  # Row = Table[string, JsonNode]
  Row = JsonNode #Table[string, JsonNode]
  Rows = seq[Row]
  Id = int
  HttpMethod = enum GET, POST


proc newGristApi*(docId, apiKey: string, server: Uri | string): GristApi =
  result.docId = docId
  when server is Uri:
    result.server = server
  else:
    result.server = parseUri(server)
  # result.client = newAsyncHttpClient()
  # result.client.headers = newHttpHeaders(
  result.headers = @[("Authorization", fmt"Bearer {apiKey}")]


proc get(grist: GristApi, url: Uri, headers: seq[(string, string)] = @[]): string =
  var combinedHeaders = grist.headers & headers
  let resp = get($url, combinedHeaders)
  if resp.code != 200:
    raise newException(ValueError, resp.body)
  return resp.body


proc post(grist: GristApi, url: Uri, body = "", headers: seq[(string, string)] = @[]): string =
  ## TODO this is copy pasted from get
  var combinedHeaders = grist.headers & headers
  let resp = post($url, combinedHeaders, body)
  if resp.code != 200:
    raise newException(ValueError, resp.body)
  return resp.body


proc addRecords*(grist: GristApi, table: string, data: Rows, noparse = false): seq[Id] =
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


proc fetchTable*(grist: GristApi, table: string, filter: JsonNode = %* {}, limit = 0, sort = ""): Rows  =
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

