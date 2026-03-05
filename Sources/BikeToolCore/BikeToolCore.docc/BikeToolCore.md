# ``BikeToolCore``

@Metadata {
  @DisplayName("BikeToolCore")
}

Read and safely edit Bike.app `.bike` outline files in-process from Swift.

## Overview

`BikeToolCore` provides the same core operations used by the `bike-tool` CLI:

- Parse Bike XML and read typed row values via ``BikeDocument/readRows()``.
- Add plain, linked, or rich-text rows using ``BikeDocument`` mutation APIs.
- Persist with configurable write and backup policies using ``WriteMode`` and ``BackupMode``.
- Manage retained backups through ``BackupManager``.

Use this module when you need deterministic, structured `.bike` mutations without hand-editing XML.

## Topics

### Essentials

- <doc:Getting-Started>
- <doc:Editing-Workflows>

### Reliability

- <doc:Error-Handling>
- <doc:Data-Preservation-Guarantees>

### Core APIs

- ``BikeDocument``
- ``Row``
- ``RowLink``
- ``AddPlacement``
- ``WriteMode``
- ``BackupMode``
- ``BackupManager``
- ``BikeToolCoreError``
