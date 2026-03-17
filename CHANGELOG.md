# Changelog for ConnGRPC


## v0.4.3

### Fix

- Add missing return value to `@spec` of `ConnGRPC.Pool.get_channel/1`

## v0.4.2

### Fix

- Prevent exception when pool is not started, return error tuple instead, by @guisehn

## v0.4.1

### Fix

- Fix pool overwriting user `on_connect`/`on_disconnect` callbacks, by @yordis

## v0.4.0

### Added

- Add bang function `ConnGRPC.Pool.get_channel!/1`, by @yordis

## v0.3.1

### Fix

- Handle disconnect when channel is not initialized, by @yordis (closes https://github.com/TheRealReal/conn_grpc/issues/22)

## v0.3.0

### Added

- `otp_app` option on `ConnGRPC.Pool`, by @yordis

## v0.2.1

### Fix

- Added a fallback value for `address` (`""`, empty string) in pool's configuration to avoid passing `nil` to `GRPC.Stub.connect/2`, therefore avoid crashing the pool, in case address is set to `nil`.

## v0.2.0

### Added

- `mock` option on `ConnGRPC.Channel`


## v0.1.0

### Added

- `ConnGRPC.Channel` module
- `ConnGRPC.Pool` module
