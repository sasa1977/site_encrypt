defmodule SiteEncrypt.Certification.Periodic do
  @moduledoc false

  @hour_interval 8

  @type offset :: %{hour: 0..unquote(@hour_interval), minute: 0..59, second: 0..59}

  @spec offset :: offset
  def offset do
    # Offset for periodical job. This offset is randomized to reduce traffic spikes on the CA
    # server, as suggested at https://letsencrypt.org/docs/integration-guide/
    %{
      hour: :rand.uniform(@hour_interval) - 1,
      minute: :rand.uniform(60) - 1,
      second: :rand.uniform(60) - 1
    }
  end

  def child_spec(config) do
    Periodic.child_spec(
      id: __MODULE__.Scheduler,
      run: fn -> SiteEncrypt.force_certify(config.id) end,
      every: :timer.seconds(1),
      when: fn -> time_to_renew?(config, utc_now(config)) end,
      on_overlap: :ignore,
      mode: config.mode,
      name: SiteEncrypt.Registry.name(config.id, __MODULE__)
    )
  end

  defp time_to_renew?(config, now) do
    rem(now.hour, @hour_interval) == config.periodic_offset.hour and
      now.minute == config.periodic_offset.minute and
      now.second == config.periodic_offset.second and
      cert_due_for_renewal?(config, now)
  end

  def cert_due_for_renewal?(config, now \\ nil) do
    now = now || utc_now(config)
    Date.compare(DateTime.to_date(now), renewal_date(config)) in [:eq, :gt]
  end

  def renewal_date(config) do
    cert_valid_until = cert_valid_until(config)
    Date.add(cert_valid_until, -config.days_to_renew)
  end

  def cert_valid_until(config) do
    case SiteEncrypt.client(config).pems(config) do
      :error ->
        DateTime.to_date(utc_now(config))

      {:ok, pems} ->
        {:Validity, _from, to} =
          pems.cert
          |> X509.Certificate.from_pem!()
          |> X509.Certificate.validity()

        to
        |> X509.DateTime.to_datetime()
        |> DateTime.to_date()
    end
  end

  defp utc_now(config), do: :persistent_term.get({__MODULE__, config.id}, DateTime.utc_now())

  @doc false
  # for test purposes only
  def tick(id, datetime) do
    :persistent_term.put({__MODULE__, id}, datetime)

    case Periodic.Test.sync_tick(SiteEncrypt.Registry.name(id, __MODULE__), :infinity) do
      {:ok, :normal} -> :ok
      {:ok, abnormal} -> {:error, abnormal}
      error -> error
    end
  after
    :persistent_term.erase({{__MODULE__, id}, datetime})
  end
end
