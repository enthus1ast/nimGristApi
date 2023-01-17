# import asyncdispatch, httpclient,
import strutils, uri, tables, json, strformat
import std/jsonutils
import puppy
# import httpcore

type
  # GristApi[AsyncHttpClient | * = object
  GristApi* = object
    server*: Uri
    docId*: string
    # client*: AsyncHttpClient
    # headers*: HttpHeaders
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
  return get($url, combinedHeaders).body


# proc addRecords*(grist: GristApi, tableId: string, data: Rows) =
#   discard

# proc fetchTable*(grist: GristApi, table: string, filters: Table[string, string]): Rows  =
#   let path = fmt"/api/docs/{grist.docId}/tables/{table}/records"
#   var url = grist.server / path
#   echo "#############################"
#   # echo encodeQuery(%* filters)
#   # echo $ (%* filters)
#   echo "#############################"

#   # if filters.len > 0:
#     # url = url ? filters

#   let body = await (await grist.client.get(url)).body
#   let js = parseJson(body)
#   var ret: seq[JsonNode] = @[]
#   if js.hasKey("records"):
#     for record in js["records"].getElems():
#       ret.add record
#     return ret

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
    docId = "kTveggjMFamxzQL7AbFoxu",
    apiKey = "d17a2270af40484d3592cba694157b9fb720e01a",
    server = "http://192.168.174.238:8484/"
    # server = "http://172.16.3.210:8484/"

  )

  let dateStr = ($now()).replace(":", "-")

  let dataSqlite = grist.downloadSQLITE()
  writeFile(fmt"gene__{dateStr}.sqlite", dataSqlite)

  let dataXLSX = grist.downloadXLSX()
  writeFile(fmt"gene__{dateStr}.xlsx", dataXLSX)

  let dataCSV = grist.downloadCSV("Entries")
  writeFile(fmt"geneEntries__{dateStr}.csv", dataCSV)

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

