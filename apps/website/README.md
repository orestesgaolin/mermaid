# website

A new Jaspr project

## Running the project

Run your project using `jaspr serve`.

The development server will be available on `http://localhost:8080`.

## Building the project

Build your project using `jaspr build`.

The output will be located inside the `build/jaspr/` directory.

## ELK reference comparison

The `/elk` gallery compares Dart ELK with precomputed elkjs output. Both engines
receive the exact JSON shown in each example. SVG styling and coordinate scale
are shared; the amber outline shows each engine's returned layout bounds.

After changing graph examples or serialized options, regenerate references:

```sh
(cd ../../packages/elk/tool/validation && npm ci)
dart run tool/generate_elk_reference.dart
flutter test test/elk_demos_test.dart test/elk_reference_test.dart
```

Run these commands from `apps/website`. The generator records the installed
elkjs version (pinned by the validation package lockfile). Tests reject missing
or stale references. References remain checked in so builds do not need Node.
The comparison covers the graph fields used by this gallery, not all ELK options.
