defmodule TelemetryHelper do
  # Sets up handlers to help testing telemetry events. Whenever one of the events
  # is called, the test will receive a
  # `{:telemetry_executed, event_name, measurements, metadata}` message.
  #
  # This assumes that the test process is registered with the name `:test`.

  @moduledoc false

  def setup_telemetry(test, events) do
    :ok = :telemetry.attach_many(
      test,
      events,
      &TelemetryHelper.handle/4,
      nil
    )
  end

  def handle(event_name, measurements, metadata, _) do
    if Process.whereis(:test) do
      send(:test, {:telemetry_executed, event_name, measurements, metadata})
    end
  end
end
