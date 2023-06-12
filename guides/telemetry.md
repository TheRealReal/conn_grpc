ConnGRPC sends `telemetry` events.

Call `:telemetry.attach/4` or `:telemetry.attach_many/4` to attach your handler function to any of the following events:

## Channel events

- `[:conn_grpc, :channel, :get]`: reports the duration of the call to `ConnGRPC.Channel.get/1`. If it's taking too long, the channel process is overwhelmed with messages, and increasing pool size may help.

- `[:conn_grpc, :channel, :connected]`: reports a successful connection, and how long it took to establish the connection

- `[:conn_grpc, :channel, :connection_failed]`: reports a failed connection, and how long it took trying to establish the connection

- `[:conn_grpc, :channel, :disconnected]`: reports a disconnection, and how long the connection stayed up

## Pool events

- `[:conn_grpc, :pool, :get_channel]`: reports the duration of the call to `ConnGRPC.Pool.get_channel/1`.

- `[:conn_grpc, :pool, :status]`: reports the pool status, with the expected size (fixed pool size) and current size (amount of channels currently on the pool). This event is reported periodically.
