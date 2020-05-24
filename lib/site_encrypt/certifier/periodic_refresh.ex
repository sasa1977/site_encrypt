defmodule SiteEncrypt.Certifier.PeriodicRefresh do
  def child_spec(config) do
    Periodic.child_spec(
      id: __MODULE__.Scheduler,
      run: fn -> SiteEncrypt.Certifier.force_renew(config.id) end,
      every: :timer.seconds(1),
      when: fn -> midnight?(config) and time_to_renew?(config) end,
      on_overlap: :ignore,
      mode: config.mode,
      name: SiteEncrypt.Registry.name(config.id, __MODULE__)
    )
  end

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

  defp time_to_renew?(config),
    do: NaiveDateTime.compare(renewal_date(config), utc_now(config.id)) in [:lt, :eq]

  defp midnight?(config),
    do: match?(%NaiveDateTime{hour: 0, minute: 0, second: 0}, utc_now(config.id))

  def renewal_date(config) do
    cert_valid_until = cert_valid_until(config)

    {:ok, renewal_date} =
      NaiveDateTime.new(
        Date.add(cert_valid_until, -config.renew_before_expires_in_days),
        NaiveDateTime.to_time(cert_valid_until)
      )

    renewal_date
  end

  defp utc_now(id), do: :persistent_term.get({__MODULE__, id}, NaiveDateTime.utc_now())

  def cert_valid_until(config) do
    case config.certifier.pems(config) do
      :error ->
        utc_now(config.id)

      {:ok, pems} ->
        {:Validity, _from, to} =
          pems
          |> Keyword.fetch!(:cert)
          |> X509.Certificate.from_pem!()
          |> X509.Certificate.validity()

        to
        |> X509.DateTime.to_datetime()
        |> DateTime.to_naive()
    end
  end
end
