# Changelog

## [1.1.0](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/compare/hyperdrive_labs_telemetry-v1.0.1...hyperdrive_labs_telemetry-v1.1.0) (2026-07-31)


### Features

* add better retry and deadlock mechanism using dead-letter queue and .retry sidecar files ([100e057](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/commit/100e057b45c6a932685e37ecd1c6fffb8c6788de))
* add logging implementation using the default 'logging' package ([a2bc69a](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/commit/a2bc69af61979e7e2a8dca02cb5bd298cc0b8de6))


### Bug Fixes

* properly add version to DiskQueueSpanExporter scopeSpans.scope ([7453dba](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/commit/7453dba6c41caa21b6a40fe51ffe57b00f76d25b))

## [1.0.1](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/compare/hyperdrive_labs_telemetry-v1.0.0...hyperdrive_labs_telemetry-v1.0.1) (2026-07-26)


### Bug Fixes

* remove incorrect delete file in flushQueue ([877023a](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/commit/877023a598e823d0864c2be8162866c65fc03f28))

## [1.0.0](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/compare/hyperdrive_labs_telemetry-v0.2.1...hyperdrive_labs_telemetry-v1.0.0) (2026-07-24)


### ⚠ BREAKING CHANGES

* **hyperdrive_labs_telemetry:** Core telemetry handling and initialization flows have been restructured. Existing configurations or custom exporters may need to adapt to the new architecture.

### Features

* **hyperdrive_labs_telemetry:** add buildDeviceResource helper for device telemetry metadata ([e2d41f1](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/commit/e2d41f10dad3185afdb80a464e57062ca428725b))
* **hyperdrive_labs_telemetry:** add DiskQueueSpanExporter for offline-first telemetry caching ([cce72da](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/commit/cce72da3530d4f80ea3effb00f9689f047e6a475))
* **hyperdrive_labs_telemetry:** add OTelDioInterceptor for Dio network tracing ([1a8c7a3](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/commit/1a8c7a30870a4267a674dc5b41e9abb95c928ad6))
* **hyperdrive_labs_telemetry:** add OTelNavigatorObserver for automated screen tracking ([5435be6](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/commit/5435be643aecda6e7d6b401bd74d83f835bedc60))
* **hyperdrive_labs_telemetry:** overhaul core telemetry engine and lifecycle management ([ae6e6ce](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/commit/ae6e6ce8b6fcb5194351490104006a03b6b10e41))

## [0.2.1](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/compare/hyperdrive_labs_telemetry-v0.2.0...hyperdrive_labs_telemetry-v0.2.1) (2026-07-23)


### Bug Fixes

* **hyperdrive_labs_telemetry:** downgrade package_info_plus to ^9.0.1 ([09a4285](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/commit/09a42854af0018a8add6ad8e9960f7a66be97ae1))

## [0.2.0](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/compare/hyperdrive_labs_telemetry-v0.1.0...hyperdrive_labs_telemetry-v0.2.0) (2026-07-23)


### Features

* **hyperdrive_labs_telemetry:** add exception.type and exception.message attributes to log record ([4d1b44f](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/commit/4d1b44f95cc4331cd6b614125338dbef151ed748))
* **hyperdrive_labs_telemetry:** add os.version to resource attributes ([0490c7f](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/commit/0490c7fc77e3c051e83223c7b32fa6a21f24646e))
* **hyperdrive_labs_telemetry:** add scope to scopeLogs ([b024d44](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/commit/b024d4427afc3b2169ed14b768cbd461d89e0f8f))
* **hyperdrive_labs_telemetry:** add service.version to resource attributes ([37c56d8](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/commit/37c56d88a21d97af17230233d32f588eb9e86e45))

## [0.1.0](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/compare/hyperdrive_labs_telemetry-v0.0.1...hyperdrive_labs_telemetry-v0.1.0) (2026-07-21)


### Features

* **hyperdrive_labs_telemetry:** add example app ([b66e396](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/commit/b66e396337d3e96e6f3e9200c6de8b9aab0a5f73))
* **hyperdrive_labs_telemetry:** initial release ([a8efdf5](https://github.com/Hyperdrive-Labs-Dev/hyperdrive_labs_flutter/commit/a8efdf5807d46a303728c8aeb87552b749598c47))
