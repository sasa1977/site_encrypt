defmodule SiteEncrypt.Certification.Periodic do
  @moduledoc false

  def child_spec(config) do
    Periodic.child_spec(
      id: __MODULE__.Scheduler,
      run: fn -> SiteEncrypt.force_renew(config.id) end,
      every: :timer.seconds(1),
      when: fn -> time_to_renew?(config, utc_now(config)) end,
      on_overlap: :ignore,
      mode: config.mode,
      name: SiteEncrypt.Registry.name(config.id, __MODULE__)
    )
  end

  defp time_to_renew?(config, now) do
    rem(now.hour, 8) == 0 and now.minute == 0 and now.second == 0 and
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
          pems
          |> Keyword.fetch!(:cert)
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
