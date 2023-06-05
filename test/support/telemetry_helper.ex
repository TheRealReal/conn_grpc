defmodule TelemetryHelper do
  # Sets up handlers to help testing telemetry events. Whenever one of the events
  # is called, the test will receive a
  # `{:telemetry_executed, event_name, measurements, metadata}` message.

  @moduledoc false

  def setup_telemetry(process_name, events) do
    :ok = :telemetry.attach_many(
      "handler_#{process_name}",
      events,
      &TelemetryHelper.handle/4,
      %{process_name: process_name}
    )
  end

  def handle(event_name, measurements, metadata, %{process_name: process_name}) do
    if Process.whereis(process_name) do
      send(process_name, {:telemetry_executed, event_name, measurements, metadata})
    end
  end
end
