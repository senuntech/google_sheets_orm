## 1.5.1

* Improved "insert" and "insertAll" logic to actively find and reuse empty/deleted rows instead of strictly appending at the end of the spreadsheet.
* Fixed row alignment bug during cascading deletes and overlapping formula generation.
* Enforced API cache bypass on mutation methods for real-time synchronization.

## 1.5.0

* Maintenance release and internal improvements

## 1.4.0

* Added automatic column protection for Formula and ForeignKey
* Added comprehensive unit test suite using mocktail

## 1.3.0

* Added insertByCell method
* Added formula support

## 1.2.2

* Fixed foreign key handling

## 1.2.1

* Fixed update method

## 1.2.0

* Added foreign key support

## 1.1.0

* Added insertAll method and deleteWhere method

## 1.0.1

* Added header synchronization

## 1.0.0

* Initial release
