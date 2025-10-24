# Changelog for ConnGRPC


## v0.3.0

### Added

- `otp_app` option on `ConnGRPC.Pool`

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
