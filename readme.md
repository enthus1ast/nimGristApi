Simple rest api client for [grist](https://getgrist.com/).


changelog:

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
