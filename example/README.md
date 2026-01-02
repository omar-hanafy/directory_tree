# Directory Tree Example

This example shows how to build a virtual project tree with
`package:directory_tree` and print it to the console.

```sh
cd example
dart pub get
dart run
```

Expected output:

```
Visible tree from "lib":

lib/
  src/
    services/
      auth_service.dart
    router.dart
  main.dart

Full tree (including synthetic root):

tree/
  directory_tree_example/
    lib/
      src/
        services/
          auth_service.dart
        router.dart
      main.dart
  ReleaseNotes.md (virtual)
```
